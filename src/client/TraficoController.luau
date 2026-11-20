--!strict
-- TraficoController: dibuja los autos de caricatura (solo visual, en este cliente) y el mareo de
-- las heroínas atropelladas (estrellitas girando + sonido). La ruta sale de Shared/Trafico: todos
-- los clientes ven los autos en el mismo sitio porque usan la hora del servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Trafico = require(ReplicatedStorage.Shared.Trafico)
local EfectosController = require(script.Parent.EfectosController)

local COLORES = {
	Color3.fromRGB(255, 120, 190),
	Color3.fromRGB(110, 220, 190),
	Color3.fromRGB(255, 215, 80),
	Color3.fromRGB(110, 180, 255),
	Color3.fromRGB(190, 140, 255),
	Color3.fromRGB(255, 160, 90),
}

local jugadorLocal = Players.LocalPlayer
local carpeta: Folder
local autos: { Model } = {}
type Mareo = { estrellas: { BasePart }, inicio: number }
local mareos: { [Model]: Mareo } = {}

local TraficoController = {}

local function pieza(modelo: Model, nombre: string, forma: Enum.PartType, tamano: Vector3, rel: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = nombre
	p.Shape = forma
	p.Size = tamano
	p.CFrame = rel
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false -- no atropella monstruos ni bloquea calles
	p.CanQuery = false -- los rayos y láseres lo atraviesan
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = modelo
	return p
end

-- Auto redondito de caricatura (mira hacia -Z), con ojos en los faros.
local function crearAuto(color: Color3): Model
	local modelo = Instance.new("Model")
	modelo.Name = "AutoCaricatura"
	local carroceria = pieza(modelo, "Carroceria", Enum.PartType.Block, Vector3.new(7, 2.6, 14), CFrame.new(0, 0, 0), color)
	modelo.PrimaryPart = carroceria
	pieza(modelo, "Cabina", Enum.PartType.Block, Vector3.new(6, 2.6, 7), CFrame.new(0, 2.4, 1.2), color:Lerp(Color3.new(1, 1, 1), 0.35))
	pieza(modelo, "Ventana", Enum.PartType.Block, Vector3.new(5.6, 1.8, 0.2), CFrame.new(0, 2.5, -2.35), Color3.fromRGB(170, 225, 255))
	pieza(modelo, "Parachoques", Enum.PartType.Block, Vector3.new(7.4, 0.8, 0.8), CFrame.new(0, -0.7, -7.1), Color3.fromRGB(240, 240, 250))
	for _, x in { -2.2, 2.2 } do
		pieza(modelo, "Ojo", Enum.PartType.Ball, Vector3.one * 1.8, CFrame.new(x, 0.4, -7), Color3.new(1, 1, 1))
		pieza(modelo, "Pupila", Enum.PartType.Ball, Vector3.one * 0.8, CFrame.new(x, 0.45, -7.75), Color3.fromRGB(30, 20, 40))
	end
	for _, x in { -3.4, 3.4 } do
		for _, z in { -4.5, 4.5 } do
			pieza(modelo, "Rueda", Enum.PartType.Cylinder, Vector3.new(1.4, 3, 3), CFrame.new(x, -1.2, z), Color3.fromRGB(40, 35, 50))
		end
	end
	-- Guardar posiciones relativas a la carrocería para moverlo con PivotTo
	return modelo
end

local function quitarMareo(character: Model)
	local mareo = mareos[character]
	if mareo then
		for _, estrella in mareo.estrellas do
			estrella:Destroy()
		end
		mareos[character] = nil
	end
end

local function empezarMareo(character: Model)
	if mareos[character] then
		return
	end
	local estrellas = {}
	for _ = 1, 3 do
		local e = Instance.new("Part")
		e.Shape = Enum.PartType.Ball
		e.Size = Vector3.one * 0.9
		e.Color = Color3.fromRGB(255, 225, 60)
		e.Material = Enum.Material.Neon -- detalle pequeño (permitido)
		e.Anchored = true
		e.CanCollide = false
		e.CanQuery = false
		e.CanTouch = false
		e.CastShadow = false
		e.Parent = carpeta
		table.insert(estrellas, e)
	end
	mareos[character] = { estrellas = estrellas, inicio = os.clock() }
	local raiz = character:FindFirstChild("HumanoidRootPart")
	local posicion = if raiz and raiz:IsA("BasePart") then raiz.Position else nil
	EfectosController.Sonido("Bocina", posicion)
	EfectosController.Sonido("Mareo", posicion)
	if character == jugadorLocal.Character then
		EfectosController.Sacudir(0.5)
	end
end

local function actualizar()
	local t = Workspace:GetServerTimeNow()
	for i, auto in autos do
		auto:PivotTo(Trafico.CFrameAuto(i, t))
	end
	-- Mareos: estrellitas girando sobre la cabeza de cada heroína aturdida
	for _, jugador in Players:GetPlayers() do
		local character = jugador.Character
		if character then
			if character:GetAttribute("Aturdida") == true then
				empezarMareo(character)
			elseif mareos[character] then
				quitarMareo(character)
			end
		end
	end
	for character, mareo in mareos do
		local cabeza = character:FindFirstChild("Head")
		if not character.Parent or not cabeza or not cabeza:IsA("BasePart") then
			quitarMareo(character)
			continue
		end
		local giro = (os.clock() - mareo.inicio) * 6
		for k, estrella in mareo.estrellas do
			local a = giro + (k - 1) * (2 * math.pi / 3)
			estrella.CFrame = CFrame.new(cabeza.Position + Vector3.new(math.cos(a) * 1.6, 1.4, math.sin(a) * 1.6))
		end
	end
end

function TraficoController.Init()
	carpeta = Instance.new("Folder")
	carpeta.Name = "TraficoLocal"
	carpeta.Parent = Workspace
	for i = 1, Trafico.CantidadAutos do
		local auto = crearAuto(COLORES[(i - 1) % #COLORES + 1])
		auto.Parent = carpeta
		table.insert(autos, auto)
	end
end

function TraficoController.Start()
	RunService.RenderStepped:Connect(actualizar)
end

return TraficoController
