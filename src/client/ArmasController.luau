--!strict
-- ArmasController: armas de fantasía de la heroína local (Config/Armas).
--   • Disparar: tecla T, botón ARMA del HUD (móvil) o L1 del mando.
--   • Cambiar de arma: teclas 1 / 2 / 3, o la pastilla "1/3" del botón ARMA.
-- Solo se ven las armas que TIENE (pase de Robux o desbloqueo con monedas). Envía al servidor la
-- intención (clave + punto apuntado); el servidor comprueba propiedad, enfriamiento y daño.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Armas = require(Shared.Config.Armas)
local Remotes = require(Shared.Remotes)
local EfectosController = require(script.Parent.EfectosController)
local UIController = require(script.Parent.UIController)

local ALCANCE_APUNTADO = 600

local jugador = Players.LocalPlayer
local eventoUsar: RemoteEvent
local listoEn: { [string]: number } = {}
local propias: { Armas.ArmaConfig } = {}
local equipada = 1

local ArmasController = {}

local function actualizarPropias()
	local anterior = propias[equipada]
	table.clear(propias)
	for _, arma in Armas.Lista do
		if Armas.Tiene(jugador, arma.Clave) then
			table.insert(propias, arma)
		end
	end
	-- Mantener la misma arma equipada si sigue disponible
	equipada = 1
	if anterior then
		for i, arma in propias do
			if arma.Clave == anterior.Clave then
				equipada = i
			end
		end
	end
	UIController.MostrarArma(propias[equipada], equipada, #propias)
end

local function puntoApuntado(usarCentro: boolean): Vector3
	local camara = Workspace.CurrentCamera
	if not camara then
		return Vector3.zero
	end
	local rayo: Ray
	if usarCentro or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.TouchEnabled then
		rayo = camara:ViewportPointToRay(camara.ViewportSize.X / 2, camara.ViewportSize.Y / 2)
	else
		local raton = UserInputService:GetMouseLocation()
		rayo = camara:ViewportPointToRay(raton.X, raton.Y)
	end
	local excluir: { Instance } = {}
	if jugador.Character then
		table.insert(excluir, jugador.Character)
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	local resultado = Workspace:Raycast(rayo.Origin, rayo.Direction * ALCANCE_APUNTADO, parametros)
	return if resultado then resultado.Position else rayo.Origin + rayo.Direction * ALCANCE_APUNTADO
end

-- Apuntado automático: si la línea apuntada no pasa cerca de ningún monstruo, el más cercano.
local function apuntar(raiz: BasePart, objetivo: Vector3, alcance: number): Vector3
	local origen = raiz.Position
	local hacia = objetivo - origen
	local direccion = if hacia.Magnitude > 0.1 then hacia.Unit else raiz.CFrame.LookVector
	-- ¿La línea apuntada toca de verdad el cuerpo de un monstruo? (misma prueba que el servidor)
	local soloEnemigos = RaycastParams.new()
	soloEnemigos.FilterType = Enum.RaycastFilterType.Include
	soloEnemigos.FilterDescendantsInstances = CollectionService:GetTagged("Enemigo")
	if Workspace:Spherecast(origen, 2, direccion * alcance, soloEnemigos) then
		return objetivo
	end
	local mejor: Vector3? = nil
	local menor = math.huge
	for _, instancia in CollectionService:GetTagged("Enemigo") do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) then
			local humanoid = instancia:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local centro = instancia:GetPivot().Position
				local medio = instancia:GetExtentsSize().Magnitude / 2
				local rel = centro - origen
				local distancia = rel.Magnitude - medio
				if distancia <= alcance and distancia < menor then
					mejor, menor = centro, distancia
				end
			end
		end
	end
	return mejor or objetivo
end

function ArmasController.Disparar(usarCentro: boolean?)
	local arma = propias[equipada]
	if not arma or UIController.MenuAbierto() then
		return
	end
	local character = jugador.Character
	local raiz = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not raiz or not raiz:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	if character:GetAttribute("Aturdida") == true or character:GetAttribute("Derribada") == true then
		return
	end
	local poder = arma.Poder
	local ahora = os.clock()
	if ahora < (listoEn[poder.Id] or 0) then
		return
	end
	listoEn[poder.Id] = ahora + poder.Enfriamiento
	local alcance = if poder.Tipo == "Martillo" then poder.Radio + poder.Alcance else poder.Alcance
	local objetivo = apuntar(raiz, puntoApuntado(usarCentro == true), alcance)
	-- En tierra se gira hacia el disparo (ella es dueña de su física)
	local plano = Vector3.new(objetivo.X - raiz.Position.X, 0, objetivo.Z - raiz.Position.Z)
	if character:GetAttribute("Volando") ~= true and plano.Magnitude > 0.1 then
		raiz.CFrame = CFrame.lookAt(raiz.Position, raiz.Position + plano)
	end
	EfectosController.Reproducir(jugador, poder, objetivo)
	eventoUsar:FireServer(arma.Clave, objetivo)
	UIController.IniciarEnfriamiento(poder.Id, poder.Enfriamiento)
end

function ArmasController.Cambiar(indice: number?)
	if #propias == 0 then
		return
	end
	equipada = if indice then math.clamp(indice, 1, #propias) else (equipada % #propias) + 1
	UIController.MostrarArma(propias[equipada], equipada, #propias)
end

local TECLAS_NUMERO = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }

function ArmasController.Init()
	eventoUsar = Remotes.Evento("UsarArma")
	UIController.AlUsarArma(function()
		ArmasController.Disparar(true)
	end)
	UIController.AlCambiarArma(function()
		ArmasController.Cambiar(nil)
	end)
end

function ArmasController.Start()
	jugador.AttributeChanged:Connect(function(nombre)
		if string.sub(nombre, 1, 5) == "Pase_" or string.sub(nombre, 1, #Armas.PrefijoAtributo) == Armas.PrefijoAtributo then
			actualizarPropias()
		end
	end)
	actualizarPropias()
	UserInputService.InputBegan:Connect(function(input, procesado)
		if procesado or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.T or input.KeyCode == Enum.KeyCode.ButtonL1 then
			ArmasController.Disparar(input.KeyCode == Enum.KeyCode.ButtonL1)
		elseif TECLAS_NUMERO[input.KeyCode] then
			ArmasController.Cambiar(TECLAS_NUMERO[input.KeyCode])
		end
	end)
end

return ArmasController
