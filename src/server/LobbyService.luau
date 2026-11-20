--!strict
-- LobbyService: patio de espera 3D en Juego.Lobby.Centro (separado de la ciudad).
--   • Aparición principal: todas las jugadoras entran aquí (los demás SpawnLocation se desactivan).
--   • Izquierda: tubo de Esencia Estelar → recompensa por tiempo jugado (Impulsos permanentes).
--   • Derecha: mostrador "CLASES" (Dra. Chispa + 3 iconos con ProximityPrompt) y cartel "INSIGNIAS".
--   • Fondo: 3 plataformas (SOLO / DÚO / ESCUADRÓN). Detección con GetPartBoundsInBox cada 0.25 s,
--     cuenta atrás de 5 s y teletransporte del grupo a la Plaza Central de Sugar Town.
--   • Atributo del jugador "EnCiudad": si reaparece estando en la ciudad, vuelve a la plaza.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Heroinas = require(Shared.Config.Heroinas)
local Juego = require(Shared.Config.Juego)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local EdificioService = require(script.Parent.EdificioService)
local HeroinaService = require(script.Parent.HeroinaService)

type ConfigPlataforma = { Nombre: string, Maximo: number, X: number }
type Plataforma = {
	config: ConfigPlataforma,
	parte: BasePart,
	estado: TextLabel,
	contador: TextLabel,
	restante: number?,
}

local LOBBY = Juego.Lobby
local C = LOBBY.Centro -- centro del suelo; la superficie está en C.Y + 1
local SUELO = C.Y + 1
local FUENTE = Enum.Font.FredokaOne
local NEGRO = Color3.new(0, 0, 0)

local plataformas: { Plataforma } = {}
local aparicion: SpawnLocation
local eventoAnuncio: RemoteEvent
local conexiones: { [Player]: RBXScriptConnection } = {}

local LobbyService = {}

-- ─── Utilidades ──────────────────────────────────────────────────────────────

local function bloque(
	nombre: string,
	tamano: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	padre: Instance,
	forma: Enum.PartType?
): Part
	local parte = Instance.new("Part")
	parte.Name = nombre
	parte.Shape = forma or Enum.PartType.Block
	parte.Size = tamano
	parte.CFrame = cframe
	parte.Color = color
	parte.Material = material
	parte.Anchored = true
	parte.TopSurface = Enum.SurfaceType.Smooth
	parte.BottomSurface = Enum.SurfaceType.Smooth
	parte.Parent = padre
	return parte
end

-- Cilindro vertical apoyado en "base" (Size.X = altura)
local function cilindro(nombre: string, alto: number, diametro: number, base: Vector3, color: Color3, material: Enum.Material, padre: Instance): Part
	return bloque(nombre, Vector3.new(alto, diametro, diametro), CFrame.new(base + Vector3.new(0, alto / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, padre, Enum.PartType.Cylinder)
end

local function etiqueta(padre: Instance, texto: string, color: Color3, posicionY: number, alto: number, grosor: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0, posicionY)
	t.Size = UDim2.fromScale(1, alto)
	t.Font = FUENTE
	t.Text = texto
	t.TextScaled = true
	t.TextColor3 = color
	t.Parent = padre
	local trazo = Instance.new("UIStroke")
	trazo.Thickness = grosor
	trazo.Color = NEGRO
	trazo.Parent = t
	return t
end

local function cartel(parte: BasePart, cara: Enum.NormalId, texto: string, color: Color3)
	local superficie = Instance.new("SurfaceGui")
	superficie.Face = cara
	superficie.PixelsPerStud = 25
	superficie.LightInfluence = 0
	superficie.Parent = parte
	etiqueta(superficie, texto, color, 0.05, 0.9, 3)
end

local function anunciar(jugador: Player, titulo: string, subtitulo: string, color: Color3)
	eventoAnuncio:FireClient(jugador, titulo, subtitulo, color)
end

local function aviso(texto: string, padre: Instance, accion: string, objeto: string, distancia: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = accion
	prompt.ObjectText = objeto
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distancia
	prompt.RequiresLineOfSight = false
	prompt.Name = texto
	prompt.Parent = padre
	return prompt
end

-- ─── Construcción ────────────────────────────────────────────────────────────

local function construirSueloYMuros(padre: Instance)
	bloque("Camino", Vector3.new(90, 2, 130), CFrame.new(C), Color3.fromRGB(230, 205, 165), Enum.Material.Sand, padre)
	for _, lado in { -1, 1 } do
		bloque("Cesped", Vector3.new(25, 2.4, 130), CFrame.new(C + Vector3.new(lado * 57.5, 0.2, 0)), Color3.fromRGB(65, 185, 55), Enum.Material.Grass, padre)
	end

	local alto, grosor = 28, 3
	local yMuro = SUELO + alto / 2
	local blanco = Color3.fromRGB(225, 225, 230)
	-- Derecho: ladrillo · Izquierdo, frontal y trasero: bloques blancos de hormigón
	bloque("MuroDerecho", Vector3.new(grosor, alto, 136), CFrame.new(C.X + 71.5, yMuro, C.Z), Color3.fromRGB(195, 145, 105), Enum.Material.Brick, padre)
	local izquierdo = bloque("MuroIzquierdo", Vector3.new(grosor, alto, 136), CFrame.new(C.X - 71.5, yMuro, C.Z), blanco, Enum.Material.Concrete, padre)
	local frontal = bloque("MuroFrontal", Vector3.new(146, alto, grosor), CFrame.new(C.X, yMuro, C.Z - 66.5), blanco, Enum.Material.Concrete, padre)
	bloque("MuroTrasero", Vector3.new(146, alto, grosor), CFrame.new(C.X, yMuro, C.Z + 66.5), blanco, Enum.Material.Concrete, padre)

	-- Enredaderas colgando de la parte superior del muro frontal e izquierdo (cara interior)
	local verde = Color3.fromRGB(75, 175, 60)
	local aleatorio = Random.new(7)
	local cima = SUELO + alto
	for x = -68, 68, 7 do
		local largo = aleatorio:NextNumber(3, 9)
		bloque("Enredadera", Vector3.new(aleatorio:NextNumber(4, 7), largo, 0.8), CFrame.new(C.X + x, cima - largo / 2, frontal.Position.Z + 1.9), verde, Enum.Material.Grass, padre).CanCollide = false
	end
	for z = -62, 62, 7 do
		local largo = aleatorio:NextNumber(3, 9)
		bloque("Enredadera", Vector3.new(0.8, largo, aleatorio:NextNumber(4, 7)), CFrame.new(izquierdo.Position.X + 1.9, cima - largo / 2, C.Z + z), verde, Enum.Material.Grass, padre).CanCollide = false
	end
	bloque("RemateVerde", Vector3.new(146, 1.2, 4), CFrame.new(C.X, cima + 0.6, C.Z - 66.5), verde, Enum.Material.Grass, padre)
	bloque("RemateVerde", Vector3.new(4, 1.2, 136), CFrame.new(C.X - 71.5, cima + 0.6, C.Z), verde, Enum.Material.Grass, padre)
end

local function construirTubo(padre: Instance)
	local base = C + Vector3.new(-26, 1, -15)
	local metal = Color3.fromRGB(150, 155, 165)
	cilindro("BaseTubo", 3, 14, base, metal, Enum.Material.Metal, padre)
	local cristal = cilindro("Tubo", 18, 13, base + Vector3.new(0, 3, 0), Color3.fromRGB(180, 230, 255), Enum.Material.Glass, padre)
	cristal.Transparency = 0.45
	cilindro("EsenciaEstelar", 4, 12, base + Vector3.new(0, 3, 0), Color3.fromRGB(255, 45, 210), Enum.Material.Neon, padre)
	cilindro("TapaTubo", 2, 14, base + Vector3.new(0, 21, 0), metal, Enum.Material.Metal, padre)

	-- Burbujas rosas subiendo (emisor sin rotar para que "Top" sea hacia arriba)
	local emisor = bloque("EmisorBurbujas", Vector3.new(9, 0.2, 9), CFrame.new(base + Vector3.new(0, 7.2, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, padre)
	emisor.Transparency = 1
	emisor.CanCollide = false
	emisor.CanQuery = false
	local burbujas = Instance.new("ParticleEmitter")
	burbujas.Color = ColorSequence.new(Color3.fromRGB(255, 120, 230), Color3.fromRGB(255, 220, 250))
	burbujas.EmissionDirection = Enum.NormalId.Top
	burbujas.Rate = 8
	burbujas.Lifetime = NumberRange.new(3, 4.5)
	burbujas.Speed = NumberRange.new(2, 3.5)
	burbujas.SpreadAngle = Vector2.new(8, 8)
	burbujas.Size = NumberSequence.new(0.6, 0.25)
	burbujas.Transparency = NumberSequence.new(0.25, 1)
	burbujas.LightEmission = 0.3
	burbujas.Parent = emisor

	-- Consola azul al costado
	local consola = bloque("Consola", Vector3.new(4, 5, 4), CFrame.new(base + Vector3.new(10, 2.5, 0)), Color3.fromRGB(40, 110, 210), Enum.Material.Metal, padre)
	local pantalla = bloque("Pantalla", Vector3.new(3.4, 2.4, 0.3), CFrame.new(base + Vector3.new(10, 4.4, -2.1)) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(20, 30, 60), Enum.Material.SmoothPlastic, padre)
	cartel(pantalla, Enum.NormalId.Front, "⭐", Color3.fromRGB(255, 120, 230))
	aviso("Reclamar", consola, "Reclamar impulso", "Esencia Estelar", 14)

	-- (El tiempo restante y los impulsos se muestran en una píldora del HUD, no en un cartel flotante)
end

-- NPC original: Dra. Chispa (bata blanca, gafas de laboratorio en la frente, pelo plateado)
local function construirCientifica(origen: CFrame, padre: Instance)
	local modelo = Instance.new("Model")
	modelo.Name = "DraChispa"
	local bata = Color3.fromRGB(245, 245, 250)
	local piel = Color3.fromRGB(240, 195, 160)
	local pantalon = Color3.fromRGB(25, 25, 30)
	local pelo = Color3.fromRGB(215, 220, 235)
	local function p(nombre: string, tamano: Vector3, desplazamiento: CFrame, color: Color3, forma: Enum.PartType?): Part
		return bloque(nombre, tamano, origen * desplazamiento, color, Enum.Material.SmoothPlastic, modelo, forma)
	end
	for _, lado in { -1, 1 } do
		p("Pierna", Vector3.new(0.9, 2.6, 0.9), CFrame.new(lado * 0.5, 1.3, 0), pantalon)
		p("Brazo", Vector3.new(0.8, 2.4, 0.8), CFrame.new(lado * 1.45, 3.65, 0) * CFrame.Angles(0, 0, math.rad(lado * 6)), bata)
		p("Mano", Vector3.one * 0.75, CFrame.new(lado * 1.55, 2.35, 0), piel, Enum.PartType.Ball)
	end
	p("Torso", Vector3.new(2, 2.4, 1.1), CFrame.new(0, 3.8, 0), bata)
	p("Faldon", Vector3.new(2.2, 1.4, 1.2), CFrame.new(0, 2.3, 0), bata)
	p("Corbata", Vector3.new(0.35, 1.3, 0.1), CFrame.new(0, 4.2, -0.6), Color3.fromRGB(0, 170, 170))
	p("Cabeza", Vector3.one * 1.7, CFrame.new(0, 5.9, 0), piel, Enum.PartType.Ball)
	p("Pelo", Vector3.one * 1.85, CFrame.new(0, 6.15, 0.18), pelo, Enum.PartType.Ball)
	for i = -1, 1 do
		p("Mechon", Vector3.new(0.4, 0.8, 0.4), CFrame.new(i * 0.5, 7, 0.1) * CFrame.Angles(0, 0, math.rad(i * 25)), pelo)
	end
	p("Gafas", Vector3.new(1.75, 0.3, 0.15), CFrame.new(0, 6.45, -0.8), Color3.fromRGB(40, 40, 50))
	for _, lado in { -1, 1 } do
		p("Lente", Vector3.new(0.1, 0.5, 0.5), CFrame.new(lado * 0.42, 6.45, -0.88) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(80, 220, 220), Enum.PartType.Cylinder)
		p("Ojo", Vector3.new(0.18, 0.28, 0.06), CFrame.new(lado * 0.35, 5.95, -0.84), NEGRO)
	end
	p("Sonrisa", Vector3.new(0.5, 0.08, 0.06), CFrame.new(0, 5.5, -0.84), Color3.fromRGB(150, 40, 60))

	local nombre = Instance.new("BillboardGui")
	nombre.Size = UDim2.fromOffset(160, 30)
	nombre.StudsOffset = Vector3.new(0, 8, 0)
	nombre.MaxDistance = 40
	nombre.Adornee = modelo:FindFirstChild("Cabeza") :: BasePart
	nombre.Parent = modelo
	etiqueta(nombre, "Dra. Chispa", Color3.fromRGB(150, 255, 150), 0, 1, 2)
	modelo.Parent = padre
end

local function iconoClase(id: Types.ArquetipoId, posicion: Vector3, padre: Instance)
	local config = Heroinas.Lista[id]
	local color = config.ColorPrincipal
	local soporte = bloque("Icono" .. id, Vector3.new(2.6, 3, 2.6), CFrame.new(posicion + Vector3.new(0, 1.5, 0)), color, Enum.Material.SmoothPlastic, padre)
	soporte.Transparency = 1
	soporte.CanCollide = false
	local mirar = CFrame.new(posicion + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, math.rad(90), 0) -- de cara al centro (-X)
	if id == "Fuerza" then
		-- Estrella rosa de 8 puntas (dos cuadrados girados)
		for _, giro in { 0, 45 } do
			bloque("Estrella", Vector3.new(1.8, 1.8, 0.4), mirar * CFrame.Angles(0, 0, math.rad(giro)), color, Enum.Material.SmoothPlastic, padre)
		end
	elseif id == "Velocidad" then
		-- Rayo azul en zigzag
		bloque("Rayo", Vector3.new(0.5, 1.4, 0.4), mirar * CFrame.new(0.25, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-25)), color, Enum.Material.SmoothPlastic, padre)
		bloque("Rayo", Vector3.new(1.1, 0.35, 0.4), mirar * CFrame.new(0, 0, 0), color, Enum.Material.SmoothPlastic, padre)
		bloque("Rayo", Vector3.new(0.5, 1.4, 0.4), mirar * CFrame.new(-0.25, -0.5, 0) * CFrame.Angles(0, 0, math.rad(-25)), color, Enum.Material.SmoothPlastic, padre)
	else
		-- Escudo verde
		bloque("Escudo", Vector3.new(0.4, 2, 2), mirar * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.SmoothPlastic, padre, Enum.PartType.Cylinder)
		bloque("Cruz", Vector3.new(0.3, 1.2, 0.45), mirar, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, padre)
	end
	local prompt = aviso("ElegirClase", soporte, "Elegir Clase", `Heroína de {config.Nombre}`, 10)
	prompt.Triggered:Connect(function(jugador)
		if HeroinaService.AsignarArquetipo(jugador, id) then
			anunciar(jugador, `{config.Icono} {string.upper(config.Nombre)}`, "¡Clase elegida!", color)
		end
	end)
end

local function construirMostrador(padre: Instance)
	local base = C + Vector3.new(26, 1, -10)
	local gris = Color3.fromRGB(150, 150, 160)
	local madera = Color3.fromRGB(95, 55, 30)
	local verde = Color3.fromRGB(90, 255, 110)
	bloque("Mostrador", Vector3.new(6, 4, 28), CFrame.new(base + Vector3.new(0, 2, 0)), gris, Enum.Material.SmoothPlastic, padre)

	-- Barrotes de laboratorio detrás (fondo de jaula) y viga superior
	for z = -13, 13, 3.25 do
		cilindro("Barrote", 15, 0.5, base + Vector3.new(9, 0, z), Color3.fromRGB(110, 115, 125), Enum.Material.Metal, padre)
	end
	bloque("Viga", Vector3.new(1, 1, 28), CFrame.new(base + Vector3.new(9, 15, 0)), Color3.fromRGB(110, 115, 125), Enum.Material.Metal, padre)

	-- Carteles de madera oscura con texto verde (cara hacia el centro del lobby: -X = Left)
	local clases = bloque("CartelClases", Vector3.new(1, 5, 16), CFrame.new(base + Vector3.new(0.5, 12, -4)), madera, Enum.Material.Wood, padre)
	cartel(clases, Enum.NormalId.Left, "CLASES", verde)
	local insignias = bloque("CartelInsignias", Vector3.new(1, 5, 14), CFrame.new(base + Vector3.new(0.5, 12, 24)), madera, Enum.Material.Wood, padre)
	cartel(insignias, Enum.NormalId.Left, "INSIGNIAS", verde)
	local tablon = bloque("TablonInsignias", Vector3.new(1, 6, 10), CFrame.new(base + Vector3.new(4, 4, 24)), madera:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Wood, padre)
	aviso("VerInsignias", tablon, "Ver insignias", "Tus logros", 12).Triggered:Connect(function(jugador)
		local function n(nombre: string): number
			local v = jugador:GetAttribute(nombre)
			return if typeof(v) == "number" then v else 0
		end
		anunciar(jugador, "🏅 TUS INSIGNIAS", `👾 {n("Derrotados")} monstruos · Nv. {math.max(1, n("Nivel"))} · ⭐ {n("Impulsos")} impulsos`, verde)
	end)

	construirCientifica(CFrame.lookAt(base + Vector3.new(5, 0, -2), base + Vector3.new(-5, 0, -2)), padre)

	-- Los 3 iconos de clase sobre la mesa
	local ids: { Types.ArquetipoId } = { "Fuerza", "Velocidad", "Estrategia" }
	for i, id in ids do
		iconoClase(id, base + Vector3.new(0, 4, -12 + i * 6), padre)
	end
end

local function construirFlechas(padre: Instance)
	local amarillo = Color3.fromRGB(255, 235, 30)
	for i = 0, 4 do
		local punta = Vector3.new(C.X, SUELO + 0.06, C.Z + 22 - i * 11) -- apuntan hacia el fondo (-Z)
		for _, lado in { -1, 1 } do
			local direccion = Vector3.new(lado, 0, 1).Unit
			local centro = punta + direccion * 3
			bloque("Flecha", Vector3.new(1.4, 0.12, 6.5), CFrame.lookAt(centro, centro + direccion), amarillo, Enum.Material.Neon, padre).CanCollide = false
		end
	end
end

local function construirPlataformas(padre: Instance)
	for _, config in LOBBY.Plataformas do
		local centro = C + Vector3.new(config.X, 1.2, -45)
		bloque("BordePlataforma", Vector3.new(15, 0.9, 15), CFrame.new(centro - Vector3.new(0, 0.1, 0)), Color3.fromRGB(60, 60, 70), Enum.Material.SmoothPlastic, padre)
		local parte = bloque("Plataforma" .. config.Nombre, Vector3.new(14, 1, 14), CFrame.new(centro), Color3.fromRGB(245, 245, 250), Enum.Material.SmoothPlastic, padre)

		local gui = Instance.new("BillboardGui")
		gui.Adornee = parte
		-- Tamaño en STUDS (no en píxeles): el cartel encoge con la distancia como un letrero real y,
		-- al medir menos que la separación entre plataformas (18), nunca se monta sobre los vecinos.
		gui.Size = UDim2.fromScale(12, 5.6)
		gui.StudsOffset = Vector3.new(0, 4.5, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		gui.Parent = parte
		etiqueta(gui, config.Nombre, Color3.fromRGB(255, 235, 30), 0, 0.38, 3)
		local estado = etiqueta(gui, "Disponible", Color3.new(1, 1, 1), 0.38, 0.3, 2)
		local contador = etiqueta(gui, `👥 0/{config.Maximo}`, Color3.fromRGB(150, 230, 255), 0.68, 0.32, 2)

		table.insert(plataformas, { config = config, parte = parte, estado = estado, contador = contador, restante = nil })
	end
end

local function construirAparicion(padre: Instance)
	aparicion = Instance.new("SpawnLocation")
	aparicion.Name = "AparicionLobby"
	aparicion.Size = Vector3.new(12, 1, 12)
	aparicion.CFrame = CFrame.lookAt(C + Vector3.new(0, 1.5, 48), C + Vector3.new(0, 1.5, 0))
	aparicion.Anchored = true
	aparicion.Neutral = true
	aparicion.Duration = 0
	aparicion.Enabled = true
	aparicion.Color = Color3.fromRGB(255, 200, 220)
	aparicion.Material = Enum.Material.SmoothPlastic
	aparicion.TopSurface = Enum.SurfaceType.Smooth
	aparicion.Parent = padre
end

-- ─── Lógica ──────────────────────────────────────────────────────────────────

local function llevarACiudad(grupo: { Player })
	local destino = EdificioService.PuntoAparicionHeroinas()
	for i, jugador in grupo do
		local character = jugador.Character
		if character then
			jugador:SetAttribute("EnCiudad", true)
			character:PivotTo(destino * CFrame.new((i - (#grupo + 1) / 2) * 6, 0, 0))
			anunciar(jugador, "¡A DEFENDER SUGAR TOWN!", if #grupo > 1 then `Equipo de {#grupo} heroínas` else "Misión en solitario", Color3.fromRGB(255, 110, 199))
		end
	end
end

local function revisarPlataformas()
	local personajes: { Instance } = {}
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(personajes, jugador.Character)
		end
	end
	local parametros = OverlapParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Include
	parametros.FilterDescendantsInstances = personajes

	for _, plataforma in plataformas do
		local encima: { Player } = {}
		local vistos: { [Player]: boolean } = {}
		if #personajes > 0 then
			for _, parte in Workspace:GetPartBoundsInBox(plataforma.parte.CFrame * CFrame.new(0, 4.5, 0), Vector3.new(14, 8, 14), parametros) do
				local modelo = parte:FindFirstAncestorOfClass("Model")
				local jugador = if modelo then Players:GetPlayerFromCharacter(modelo) else nil
				if jugador and not vistos[jugador] then
					vistos[jugador] = true
					table.insert(encima, jugador)
				end
			end
		end

		local maximo = plataforma.config.Maximo
		local grupo: { Player } = {}
		for i = 1, math.min(#encima, maximo) do
			grupo[i] = encima[i]
		end
		plataforma.contador.Text = `👥 {#grupo}/{maximo}`

		if #grupo == 0 then
			plataforma.restante = nil
			plataforma.estado.Text = "Disponible"
		else
			local restante = (plataforma.restante or (LOBBY.CuentaAtrasGrupo + LOBBY.IntervaloDeteccion)) - LOBBY.IntervaloDeteccion
			if restante <= 0 then
				plataforma.restante = nil
				plataforma.estado.Text = "¡Despegando!"
				llevarACiudad(grupo)
			else
				plataforma.restante = restante
				plataforma.estado.Text = if #encima > maximo then "Llena" else `Saliendo en {math.ceil(restante)}…`
			end
		end
	end
end

local function alReclamar(jugador: Player)
	local ahora = Workspace:GetServerTimeNow()
	local listaEn = jugador:GetAttribute("RecompensaEn")
	local impulsosValor = jugador:GetAttribute("Impulsos")
	local impulsos = if typeof(impulsosValor) == "number" then impulsosValor else 0
	if impulsos >= LOBBY.MaxImpulsos then
		anunciar(jugador, "⭐ ¡AL MÁXIMO!", `Ya tienes {LOBBY.MaxImpulsos} impulsos permanentes`, Color3.fromRGB(255, 120, 230))
		return
	end
	if typeof(listaEn) == "number" and ahora < listaEn then
		local faltan = math.ceil(listaEn - ahora)
		anunciar(jugador, "⏳ AÚN NO", string.format("Faltan %d:%02d para el próximo impulso", faltan // 60, faltan % 60), Color3.fromRGB(255, 120, 230))
		return
	end
	jugador:SetAttribute("Impulsos", impulsos + 1)
	jugador:SetAttribute("RecompensaEn", ahora + LOBBY.IntervaloRecompensa)
	anunciar(jugador, "⭐ ¡IMPULSO PERMANENTE!", `+{math.floor(LOBBY.BonoPorImpulso * 100)}% de monedas para siempre ({impulsos + 1}/{LOBBY.MaxImpulsos})`, Color3.fromRGB(255, 120, 230))
end

local function alEntrar(jugador: Player)
	jugador:SetAttribute("EnCiudad", false)
	if typeof(jugador:GetAttribute("Impulsos")) ~= "number" then
		jugador:SetAttribute("Impulsos", 0)
	end
	jugador:SetAttribute("RecompensaEn", Workspace:GetServerTimeNow() + LOBBY.IntervaloRecompensa)

	-- Si reaparece mientras está "en la ciudad", vuelve a la plaza (no al lobby)
	conexiones[jugador] = jugador.CharacterAdded:Connect(function(character)
		if jugador:GetAttribute("EnCiudad") ~= true then
			return
		end
		local raiz = character:WaitForChild("HumanoidRootPart", 10)
		if raiz and character.Parent then
			character:PivotTo(EdificioService.PuntoAparicionHeroinas())
		end
	end)
end

-- ─── API pública ─────────────────────────────────────────────────────────────

-- Devuelve a la jugadora al lobby (fuera de la ciudad): al cambiar EnCiudad recupera su avatar.
function LobbyService.EnviarAlLobby(jugador: Player)
	jugador:SetAttribute("EnCiudad", false)
	local character = jugador.Character
	if character and aparicion then
		character:PivotTo(aparicion.CFrame + Vector3.new(0, 4, 0))
	end
end

function LobbyService.Init()
	eventoAnuncio = Remotes.Evento("Anuncio")

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	construirSueloYMuros(lobby)
	construirTubo(lobby)
	construirMostrador(lobby)
	construirFlechas(lobby)
	construirPlataformas(lobby)
	construirAparicion(lobby)
	lobby.Parent = Workspace

	-- El lobby es la ÚNICA aparición activa (también desactiva los de plantillas del lugar)
	for _, descendiente in Workspace:GetDescendants() do
		if descendiente:IsA("SpawnLocation") and descendiente ~= aparicion then
			descendiente.Enabled = false
		end
	end

	local consola = lobby:FindFirstChild("Consola")
	local prompt = if consola then consola:FindFirstChildOfClass("ProximityPrompt") else nil
	if prompt then
		prompt.Triggered:Connect(alReclamar)
	end

	Remotes.Evento("VolverLobby").OnServerEvent:Connect(function(jugador: Player)
		local character = jugador.Character
		if not character then
			return
		end
		LobbyService.EnviarAlLobby(jugador)
	end)
end

function LobbyService.Start()
	Players.PlayerAdded:Connect(alEntrar)
	Players.PlayerRemoving:Connect(function(jugador)
		local conexion = conexiones[jugador]
		if conexion then
			conexion:Disconnect()
			conexiones[jugador] = nil
		end
	end)
	for _, jugador in Players:GetPlayers() do
		task.spawn(alEntrar, jugador)
	end

	task.spawn(function()
		while true do
			task.wait(LOBBY.IntervaloDeteccion)
			revisarPlataformas()
		end
	end)
end

return LobbyService
