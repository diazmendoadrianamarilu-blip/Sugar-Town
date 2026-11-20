--!strict
-- CombateController: combo cuerpo a cuerpo de la heroína local.
--   • Clic izquierdo (mantenido = sigue golpeando), botón 👊 del HUD (móvil) o botón X del mando.
--   • Combo puño → puño → patada. El cliente PREDICE el paso para animar al instante, pero solo
--     envía la intención (dirección); el servidor decide paso, objetivo, distancia y daño.
--   • Animaciones: PoseVueloController (golpe con prioridad sobre la pose de vuelo; en vuelo usa
--     un puñetazo/patada aéreos propios). Cada cliente anima a las demás al recibir "EfectoGolpe".
--   • Al impactar: chispas, palabra de cómic, parpadeo blanco del monstruo y, en la pantalla de
--     quien golpea, hit-stop, sacudida de cámara y contador "xN COMBO!".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Combate = require(Shared.Config.Combate)
local Heroinas = require(Shared.Config.Heroinas)
local Remotes = require(Shared.Remotes)
local EfectosController = require(script.Parent.EfectosController)
local PoseVueloController = require(script.Parent.PoseVueloController)
local UIController = require(script.Parent.UIController)
local VueloController = require(script.Parent.VueloController)

local jugador = Players.LocalPlayer
local eventoGolpear: RemoteEvent

local BUFFER_ENTRADA = 0.2 -- un clic hecho justo antes de poder golpear se guarda y se lanza al estar listo
-- Apuntado automático: al golpear, la heroína se gira sola hacia el monstruo más cercano que esté
-- a esta distancia extra del alcance del golpe (el servidor sigue validando la distancia real).
local ALCANCE_AUTOAPUNTADO = 6

-- Predicción del combo (el servidor lleva el estado real)
local paso = 0
local ultimoGolpe = -math.huge
local listoEn = 0
local golpePendiente = false
local botonMantenido = false

local CombateController = {}

-- Las animaciones de los golpes las hace PoseVueloController (único sistema que mueve las
-- articulaciones: el golpe tiene prioridad sobre la pose de vuelo/carrera).
local function reproducirAnimacion(character: Model, nombre: string)
	PoseVueloController.ReproducirGolpe(character, nombre)
end

-- Hit-stop: congela un instante la pose del golpe de la heroína local.
local function hitStop()
	local character = jugador.Character
	if character then
		PoseVueloController.HitStop(character, Combate.HitStop)
	end
end

-- ─── Golpear ─────────────────────────────────────────────────────────────────

local function personajeLocal(): (Model?, BasePart?, Humanoid?)
	local character = jugador.Character
	if not character then
		return nil, nil, nil
	end
	local raiz = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if raiz and raiz:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return character, raiz, humanoid
	end
	return nil, nil, nil
end

-- Monstruo más cercano al alcance (misma idea que el servidor) para girarse hacia él.
local function monstruoCercano(origen: Vector3, alcance: number): Vector3?
	local mejor: Vector3? = nil
	local mejorDistancia = math.huge
	for _, instancia in CollectionService:GetTagged("Enemigo") do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) then
			local humanoid = instancia:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local caja, tamano = instancia:GetBoundingBox()
				local relativo = caja:PointToObjectSpace(origen)
				local medio = tamano / 2
				local punto = caja:PointToWorldSpace(Vector3.new(
					math.clamp(relativo.X, -medio.X, medio.X),
					math.clamp(relativo.Y, -medio.Y, medio.Y),
					math.clamp(relativo.Z, -medio.Z, medio.Z)
				))
				local distancia = (punto - origen).Magnitude
				if distancia <= alcance and distancia < mejorDistancia then
					mejor, mejorDistancia = punto, distancia
				end
			end
		end
	end
	return mejor
end

local function direccionDeAtaque(raiz: BasePart, alcance: number): Vector3
	local objetivo = monstruoCercano(raiz.Position, alcance + ALCANCE_AUTOAPUNTADO)
	if objetivo then
		local hacia = Vector3.new(objetivo.X - raiz.Position.X, 0, objetivo.Z - raiz.Position.Z)
		if hacia.Magnitude > 0.1 then
			return hacia.Unit
		end
	end
	local camara = Workspace.CurrentCamera
	local mirada = if camara then camara.CFrame.LookVector else raiz.CFrame.LookVector
	local plano = Vector3.new(mirada.X, 0, mirada.Z)
	return if plano.Magnitude > 0.01 then plano.Unit else Vector3.new(0, 0, -1)
end

function CombateController.Golpear()
	if UIController.MenuAbierto() then
		return
	end
	local character, raiz = personajeLocal()
	if not character or not raiz or character:GetAttribute("Aturdida") == true or character:GetAttribute("Derribada") == true then
		return
	end
	local ahora = os.clock()
	if ahora < listoEn then
		-- Buffer: el clic se guarda si falta muy poco para poder golpear
		if listoEn - ahora <= BUFFER_ENTRADA and not golpePendiente then
			golpePendiente = true
			task.delay(listoEn - ahora, function()
				golpePendiente = false
				CombateController.Golpear()
			end)
		end
		return
	end

	paso = if ahora - ultimoGolpe <= Combate.VentanaCombo then paso % #Combate.Golpes + 1 else 1
	local golpe = Combate.Golpes[paso]
	ultimoGolpe = ahora
	listoEn = ahora + golpe.Recuperacion

	local direccion = direccionDeAtaque(raiz, golpe.Alcance)
	-- En tierra, la heroína se gira hacia el golpe (ella es dueña de su física)
	if not VueloController.EstaVolando() then
		raiz.CFrame = CFrame.lookAt(raiz.Position, raiz.Position + direccion)
	end
	reproducirAnimacion(character, golpe.Animacion)
	EfectosController.Sonido("GolpeAire", raiz.Position, if paso == #Combate.Golpes then 0.8 else 1)
	eventoGolpear:FireServer(direccion)
end

-- ─── Respuesta del servidor ──────────────────────────────────────────────────

local function alEfectoGolpe(atacante: unknown, pasoServidor: unknown, impacto: unknown, enemigo: unknown, combo: unknown)
	if typeof(atacante) ~= "Instance" or not (atacante :: Instance):IsA("Player") then
		return
	end
	if typeof(pasoServidor) ~= "number" then
		return
	end
	local golpe = Combate.Golpes[pasoServidor :: number]
	if not golpe then
		return
	end
	local quien = atacante :: Player
	local esLocal = quien == jugador

	-- Las demás heroínas: animación y sonido de aire (la local ya lo hizo al pulsar)
	if not esLocal then
		local character = quien.Character
		if character then
			reproducirAnimacion(character, golpe.Animacion)
			local raiz = character:FindFirstChild("HumanoidRootPart")
			if raiz and raiz:IsA("BasePart") then
				EfectosController.Sonido("GolpeAire", raiz.Position, nil, 0.6)
			end
		end
	end

	if typeof(impacto) ~= "Vector3" then
		return -- golpe al aire
	end
	local punto = impacto :: Vector3
	local color = Heroinas.Obtener(quien:GetAttribute("Arquetipo")).ColorPrincipal
	EfectosController.ImpactoGolpe(punto, color, pasoServidor :: number)
	EfectosController.Sonido(golpe.Sonido, punto)
	if typeof(enemigo) == "Instance" and (enemigo :: Instance):IsA("Model") then
		EfectosController.ParpadeoBlanco(enemigo :: Model)
	end

	if esLocal then
		hitStop()
		EfectosController.Sacudir(if golpe.Empuje > 0 then Combate.SacudidaPatada else Combate.SacudidaGolpe)
		if typeof(combo) == "number" then
			local n = combo :: number
			local bono = n > 0 and n % Combate.CadaCuantosBono == 0
			UIController.MostrarCombo(n, bono, Combate.DuracionContador)
			if n >= 2 then
				EfectosController.Sonido("Combo", nil, 1 + math.min(n, 20) * 0.03)
			end
		end
	end
end

-- Un ataque de monstruo lanza a la heroína: el servidor manda la velocidad y aquí se aplica
-- (la heroína es dueña de su física).
local function alEmpujon(velocidad: unknown)
	if typeof(velocidad) ~= "Vector3" then
		return
	end
	local v = velocidad :: Vector3
	if v.Magnitude ~= v.Magnitude or v.Magnitude > 300 then
		return
	end
	local _, raiz, humanoid = personajeLocal()
	if not raiz or not humanoid then
		return
	end
	EfectosController.Sacudir(0.45)
	if VueloController.EstaVolando() then
		VueloController.Impulsar(v)
	else
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		raiz.AssemblyLinearVelocity = v
	end
end

-- ─── Entrada ─────────────────────────────────────────────────────────────────

local function alPulsar(input: InputObject, procesado: boolean)
	if procesado or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		botonMantenido = true
		CombateController.Golpear()
	elseif input.KeyCode == Enum.KeyCode.ButtonX then
		CombateController.Golpear()
	end
end

local function alSoltar(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		botonMantenido = false
	end
end

function CombateController.Init()
	eventoGolpear = Remotes.Evento("Golpear")
	Remotes.Evento("EfectoGolpe").OnClientEvent:Connect(alEfectoGolpe)
	Remotes.Evento("Empujon").OnClientEvent:Connect(alEmpujon)
	UIController.AlGolpear(CombateController.Golpear)
end

function CombateController.Start()
	UserInputService.InputBegan:Connect(alPulsar)
	UserInputService.InputEnded:Connect(alSoltar)
	-- Mantener el clic sigue el combo sin tener que hacer clic una y otra vez
	RunService.Heartbeat:Connect(function()
		if botonMantenido and os.clock() >= listoEn and not golpePendiente then
			CombateController.Golpear()
		end
	end)
	UIController.AlGolpear(CombateController.Golpear)
end

return CombateController
