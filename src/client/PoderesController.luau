--!strict
-- PoderesController: entrada de poderes de la heroína local.
--   Primario:   E  poder único (desde el nivel 5)   (mando: R2) · el clic izquierdo es el combo
--   Secundario: Q  rayo láser  (desde el nivel 3)   (mando: L2)
--   Los niveles salen de Config/Poderes (NivelRequerido); el servidor vuelve a comprobarlos.
--   Móvil / ratón: también se pueden pulsar las ranuras del HUD.
-- Envía al servidor solo la INTENCIÓN (ranura + punto apuntado); el servidor decide el daño.
-- Muestra el efecto al instante (predicción) y el enfriamiento en el HUD.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Poderes = require(Shared.Config.Poderes)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local EfectosController = require(script.Parent.EfectosController)
local UIController = require(script.Parent.UIController)
local VueloController = require(script.Parent.VueloController)

type Ranura = Types.Ranura
type PoderConfig = Types.PoderConfig

local ALCANCE_APUNTADO = 600

local jugador = Players.LocalPlayer
local eventoUsar: RemoteEvent
local eventoEstallido: RemoteEvent
local listoEn: { [string]: number } = {}

local PoderesController = {}

local function obtenerPersonaje(): (BasePart?, Humanoid?)
	local character = jugador.Character
	if not character then
		return nil, nil
	end
	local raiz = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if raiz and raiz:IsA("BasePart") and humanoid then
		return raiz, humanoid
	end
	return nil, nil
end

-- Punto del mundo al que apunta la jugadora (ratón, o centro de pantalla en mando/móvil/shift-lock).
local function puntoApuntado(usarCentro: boolean): Vector3
	local camara = Workspace.CurrentCamera
	if not camara then
		return Vector3.zero
	end
	local rayo: Ray
	if usarCentro or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		rayo = camara:ViewportPointToRay(camara.ViewportSize.X / 2, camara.ViewportSize.Y / 2)
	else
		local raton = UserInputService:GetMouseLocation()
		rayo = camara:ViewportPointToRay(raton.X, raton.Y)
	end

	local excluir: { Instance } = {}
	if jugador.Character then
		table.insert(excluir, jugador.Character)
	end
	local efectos = Workspace:FindFirstChild("EfectosLocales")
	if efectos then
		table.insert(excluir, efectos)
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir

	local resultado = Workspace:Raycast(rayo.Origin, rayo.Direction * ALCANCE_APUNTADO, parametros)
	return if resultado then resultado.Position else rayo.Origin + rayo.Direction * ALCANCE_APUNTADO
end

local function distanciaASegmento(punto: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local largo2 = ab:Dot(ab)
	if largo2 < 1e-6 then
		return (punto - a).Magnitude
	end
	local t = math.clamp((punto - a):Dot(ab) / largo2, 0, 1)
	return (punto - (a + ab * t)).Magnitude
end

-- Apuntado automático del láser: si la línea apuntada no pasa por ningún monstruo, apunta al
-- monstruo vivo más cercano dentro del alcance (el servidor recalcula el impacto igualmente).
local function apuntarLaser(raiz: BasePart, objetivo: Vector3, poder: PoderConfig): Vector3
	local origen = raiz.Position
	local hacia = objetivo - origen
	local fin = origen + (if hacia.Magnitude > 0.1 then hacia.Unit else raiz.CFrame.LookVector) * poder.Alcance
	local masCercano: Vector3? = nil
	local mejor = math.huge
	for _, instancia in CollectionService:GetTagged("Enemigo") do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) then
			local humanoid = instancia:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local centro = instancia:GetPivot().Position
				local medio = instancia:GetExtentsSize().Magnitude / 2
				if distanciaASegmento(centro, origen, fin) <= poder.Radio + medio then
					return objetivo -- ya apunta a un monstruo
				end
				local distancia = (centro - origen).Magnitude - medio
				if distancia <= poder.Alcance and distancia < mejor then
					masCercano, mejor = centro, distancia
				end
			end
		end
	end
	return masCercano or objetivo
end

-- Impulso Relámpago: mueve a la heroína (ella es dueña de su física) y devuelve el punto final.
local function ejecutarImpulso(raiz: BasePart, poder: PoderConfig): Vector3
	local camara = Workspace.CurrentCamera
	local mirada = if camara then camara.CFrame.LookVector else raiz.CFrame.LookVector
	local volando = VueloController.EstaVolando()

	local direccion = mirada
	if not volando then
		local plano = Vector3.new(mirada.X, 0, mirada.Z)
		direccion = if plano.Magnitude > 0.01 then plano.Unit else raiz.CFrame.LookVector
	end
	local rapidez = poder.Alcance / poder.Duracion

	if volando then
		VueloController.Impulsar(direccion * rapidez) -- luego el vuelo frena solo
	else
		local attachment = Instance.new("Attachment")
		attachment.Name = "ImpulsoAttachment"
		attachment.Parent = raiz
		local velocidad = Instance.new("LinearVelocity")
		velocidad.Name = "ImpulsoVelocidad"
		velocidad.Attachment0 = attachment
		velocidad.RelativeTo = Enum.ActuatorRelativeTo.World
		velocidad.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		velocidad.VectorVelocity = direccion * rapidez
		velocidad.MaxForce = raiz.AssemblyMass * 3000
		velocidad.Parent = raiz
		Debris:AddItem(velocidad, poder.Duracion)
		Debris:AddItem(attachment, poder.Duracion)
	end

	return raiz.Position + direccion * poder.Alcance
end

function PoderesController.Usar(ranura: Ranura, usarCentro: boolean?)
	if UIController.MenuAbierto() then
		return
	end
	local raiz, humanoid = obtenerPersonaje()
	if not raiz or not humanoid or humanoid.Health <= 0 then
		return
	end

	local poder = Poderes.Obtener(jugador:GetAttribute("Arquetipo"), ranura)
	local estado, restante = Poderes.EstadoUso(jugador, poder, Workspace:GetServerTimeNow())
	if estado == "Bloqueado" then
		UIController.AvisoBloqueado(poder) -- el servidor también lo comprueba
		return
	elseif estado == "Recarga" then
		UIController.Aviso(`⏳ {poder.Nombre} se recarga: {math.ceil(restante)} s`)
		return
	end
	local character = jugador.Character
	if character and (character:GetAttribute("Aturdida") == true or character:GetAttribute("Derribada") == true) then
		return
	end
	local ahora = os.clock()
	if ahora < (listoEn[poder.Id] or 0) then
		return -- en enfriamiento (el servidor también lo comprueba)
	end
	listoEn[poder.Id] = ahora + poder.Enfriamiento

	local objetivo = if poder.Tipo == "Impulso"
		then ejecutarImpulso(raiz, poder)
		else puntoApuntado(usarCentro == true)
	if poder.Tipo == "Laser" then
		objetivo = apuntarLaser(raiz, objetivo, poder)
		-- En tierra se gira hacia el disparo (ella es dueña de su física)
		local plano = Vector3.new(objetivo.X - raiz.Position.X, 0, objetivo.Z - raiz.Position.Z)
		if not VueloController.EstaVolando() and plano.Magnitude > 0.1 then
			raiz.CFrame = CFrame.lookAt(raiz.Position, raiz.Position + plano)
		end
	end

	EfectosController.Reproducir(jugador, poder, objetivo)
	eventoUsar:FireServer(ranura, objetivo)
	UIController.IniciarEnfriamiento(poder.Id, poder.Enfriamiento)
end

-- ⭐ Estallido Estelar: requiere la Esencia Estelar llena (el servidor lo vuelve a comprobar).
function PoderesController.UsarEstallido()
	if UIController.MenuAbierto() then
		return
	end
	local raiz, humanoid = obtenerPersonaje()
	local energia = jugador:GetAttribute("Energia")
	if not raiz or not humanoid or humanoid.Health <= 0 then
		return
	end
	if jugador.Character and jugador.Character:GetAttribute("Derribada") == true then
		return
	end
	if typeof(energia) ~= "number" or energia < Poderes.EnergiaMaxima then
		return
	end
	eventoEstallido:FireServer()
	EfectosController.Reproducir(jugador, Poderes.Especial, raiz.Position)
end

local function alPulsar(input: InputObject, procesado: boolean)
	if procesado or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then -- el clic izquierdo es el combo (CombateController)
		PoderesController.Usar("Primario")
	elseif input.KeyCode == Enum.KeyCode.Q then
		PoderesController.Usar("Secundario")
	elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonR1 then
		PoderesController.UsarEstallido()
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		PoderesController.Usar("Primario", true)
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		PoderesController.Usar("Secundario", true)
	end
end

function PoderesController.Init()
	eventoUsar = Remotes.Evento("UsarPoder")
	eventoEstallido = Remotes.Evento("UsarEstallido")
	UIController.AlUsarEstallido(PoderesController.UsarEstallido)
	-- Ranuras del HUD (táctil/ratón): apuntan al centro de la pantalla
	UIController.AlUsarPoder(function(ranura)
		PoderesController.Usar(ranura, true)
	end)
end

function PoderesController.Start()
	UserInputService.InputBegan:Connect(alPulsar)
end

return PoderesController
