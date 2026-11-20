--!strict
-- EdificioService: genera "Sugar Town" y gestiona los 5 edificios defendibles.
--   • Iluminación limpia: SIN efectos de post-procesado (Bloom/Blur/ColorCorrection se eliminan).
--   • Materiales reales: asfalto, hormigón, ladrillo, césped y ventanas de cristal. Neon PROHIBIDO en
--     paredes, techos y suelos (a gran escala quema la cámara en blanco).
--   • Ciudad ×3: calles anchas con línea neón, pasos de cebra, farolas, aceras, parques con árboles,
--     rascacielos de 70–160 studs (cornisas, ventanas encendidas, azoteas con antena/depósito/aguja,
--     letreros neón, puentes aéreos).
--   • Fondo: anillo de rascacielos lejanos + anillo de colinas para que nunca se vea el borde del mapa.
--   • 5 edificios principales con vida (atributos + BillboardGui MaxDistance 200) que los monstruos atacan.
-- Atributos en ReplicatedStorage: EdificiosEnPie, EdificiosTotales.
-- Nota: los edificios NO llevan Highlight (Roblox dibuja como máximo 31 a la vez; se reservan para personajes y monstruos).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Juego = require(Shared.Config.Juego)
local Types = require(Shared.Types)

type EdificioConfig = Types.EdificioConfig

type EstadoEdificio = {
	config: EdificioConfig,
	modelo: Model,
	cuerpo: BasePart,
	base: CFrame, -- centro de la planta a nivel del suelo, mirando al centro de la ciudad
	vida: number,
	destruido: boolean,
	parpadeando: boolean,
	originales: { [BasePart]: { cframe: CFrame, color: Color3 } },
	tweens: { Tween },
	barra: Frame,
	textoVida: TextLabel,
}

local ETIQUETA_EDIFICIO = "Edificio"
local FUENTE = Enum.Font.FredokaOne
local COLOR_CONTORNO = Color3.fromRGB(30, 10, 50)
local COLOR_ASFALTO = Color3.fromRGB(50, 52, 60)
local COLOR_LINEA = Color3.fromRGB(240, 240, 240)
local COLOR_CEBRA = Color3.fromRGB(245, 245, 245)
local COLOR_ACERA = Color3.fromRGB(185, 185, 195)
local COLOR_SUELO = Color3.fromRGB(85, 170, 75)
local COLOR_CESPED = Color3.fromRGB(70, 180, 65)
local COLOR_RUINAS = Color3.fromRGB(70, 60, 80)
local COLOR_VENTANA = Color3.fromRGB(60, 90, 120)
local ALTURA_ACERA = 0.8

-- Fachadas: saturadas pero NO luminosas
local PASTELES = {
	Color3.fromRGB(235, 110, 150), -- rosa coral
	Color3.fromRGB(95, 175, 235), -- azul cielo
	Color3.fromRGB(100, 205, 150), -- verde menta
	Color3.fromRGB(240, 225, 195), -- crema
}
local MATERIALES_FACHADA = { Enum.Material.Brick, Enum.Material.Concrete }
-- Acentos (cornisas, letreros, toldos): SmoothPlastic, nunca Neon
local NEONES = {
	Color3.fromRGB(200, 60, 120),
	Color3.fromRGB(40, 120, 200),
	Color3.fromRGB(40, 160, 90),
	Color3.fromRGB(230, 170, 40),
	Color3.fromRGB(130, 80, 190),
}
local COLORES_COLINA = {
	Color3.fromRGB(130, 210, 150),
	Color3.fromRGB(110, 190, 160),
	Color3.fromRGB(170, 150, 220),
	Color3.fromRGB(150, 200, 120),
}
-- Nombres originales para los letreros neón
local LETREROS = { "CARAMELOS", "SÚPER CINE", "ARCADE", "HELADOS", "RADIO POP", "GOMITAS", "BRILLO TV", "PASTELERÍA", "TURBO PIZZA", "DISCO LUNA" }

-- Manzanas que se convierten en parques (X, Z relativos)
local PARQUES = { Vector2.new(-405, 135), Vector2.new(405, 135), Vector2.new(-135, -405), Vector2.new(135, 405) }

local edificios: { EstadoEdificio } = {}
local porModelo: { [Model]: EstadoEdificio } = {}
local alCaerTodos: (() -> ())? = nil
local puntoAparicion: CFrame = CFrame.new()

local EdificioService = {}

-- ─── Utilidades de construcción ──────────────────────────────────────────────

local function bloque(
	nombre: string,
	tamano: Vector3,
	cframe: CFrame,
	color: Color3,
	padre: Instance,
	forma: Enum.PartType?,
	material: Enum.Material?
): Part
	local parte = Instance.new("Part")
	parte.Name = nombre
	parte.Shape = forma or Enum.PartType.Block
	parte.Size = tamano
	parte.CFrame = cframe
	parte.Color = color
	parte.Material = material or Enum.Material.SmoothPlastic
	parte.Anchored = true
	parte.TopSurface = Enum.SurfaceType.Smooth
	parte.BottomSurface = Enum.SurfaceType.Smooth
	parte.Parent = padre
	return parte
end

-- Detalle de color (SmoothPlastic). Antes era Neon: se quitó porque quemaba la cámara.
local function detalle(nombre: string, tamano: Vector3, cframe: CFrame, color: Color3, padre: Instance, forma: Enum.PartType?): Part
	return bloque(nombre, tamano, cframe, color, padre, forma, Enum.Material.SmoothPlastic)
end

-- Banda de ventanas de cristal oscuro con reflejo
local function ventana(nombre: string, tamano: Vector3, cframe: CFrame, padre: Instance): Part
	local parte = bloque(nombre, tamano, cframe, COLOR_VENTANA, padre, nil, Enum.Material.Glass)
	parte.Reflectance = 0.25
	parte.CanCollide = false
	parte.CanQuery = false
	parte.CanTouch = false
	return parte
end

-- Detalle sin colisión ni consultas (no estorba al vuelo ni a los rayos)
local function decorado(parte: BasePart): BasePart
	parte.CanCollide = false
	parte.CanQuery = false
	parte.CanTouch = false
	return parte
end

-- Disco horizontal (cilindro con el eje X apuntando hacia arriba)
local function disco(nombre: string, radio: number, alto: number, centro: Vector3, color: Color3, padre: Instance, material: Enum.Material?): Part
	local cframe = CFrame.new(centro) * CFrame.Angles(0, 0, math.rad(90))
	return bloque(nombre, Vector3.new(alto, radio * 2, radio * 2), cframe, color, padre, Enum.PartType.Cylinder, material)
end

-- Cilindro vertical
local function columna(nombre: string, radio: number, alto: number, base: Vector3, color: Color3, padre: Instance, material: Enum.Material?): Part
	return disco(nombre, radio, alto, base + Vector3.new(0, alto / 2, 0), color, padre, material)
end

local function letreroTexto(parte: BasePart, texto: string, cara: Enum.NormalId)
	local superficie = Instance.new("SurfaceGui")
	superficie.Face = cara
	superficie.LightInfluence = 0
	superficie.PixelsPerStud = 20
	superficie.Parent = parte
	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.Font = FUENTE
	etiqueta.Text = texto
	etiqueta.TextScaled = true
	etiqueta.TextColor3 = Color3.new(1, 1, 1)
	etiqueta.TextStrokeTransparency = 0
	etiqueta.TextStrokeColor3 = COLOR_CONTORNO
	etiqueta.Parent = superficie
end

local function aMundo(relativa: Vector2, altura: number): Vector3
	return Juego.Ciudad.Centro + Vector3.new(relativa.X, altura, relativa.Y)
end

-- ─── Iluminación estilo consola ──────────────────────────────────────────────

local function configurarIluminacion()
	-- Fuera TODO el post-procesado (causaba la pantalla en blanco)
	for _, efecto in Lighting:GetChildren() do
		if efecto:IsA("BloomEffect") or efecto:IsA("BlurEffect") or efecto:IsA("ColorCorrectionEffect") or efecto:IsA("SunRaysEffect") or efecto:IsA("DepthOfFieldEffect") then
			efecto:Destroy()
		end
	end

	Lighting.Brightness = 1.5
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(110, 115, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(145, 150, 165)
	Lighting.ClockTime = 14
	Lighting.GlobalShadows = true

	local atmosfera = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosfera then
		local nueva = Instance.new("Atmosphere")
		nueva.Name = "AtmosferaSugarTown"
		nueva.Parent = Lighting
		atmosfera = nueva
	end
	if atmosfera then
		atmosfera.Density = 0.15
		atmosfera.Offset = 0
		atmosfera.Color = Color3.fromRGB(190, 220, 255)
		atmosfera.Glare = 0
		atmosfera.Haze = 0
	end

	local nubes = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	nubes.Cover = 0.5
	nubes.Density = 0.55
	nubes.Color = Color3.fromRGB(255, 255, 255)
	nubes.Parent = Workspace.Terrain
end

-- ─── Suelo, calles, cebras y farolas ─────────────────────────────────────────

local function construirSuelo(padre: Instance)
	-- 3×3 losas de 900 (el tamaño máximo de una pieza es 2048)
	local centro = Juego.Ciudad.Centro
	for ix = -1, 1 do
		for iz = -1, 1 do
			bloque("Suelo", Vector3.new(900, 4, 900), CFrame.new(centro + Vector3.new(ix * 900, -2, iz * 900)), COLOR_SUELO, padre, nil, Enum.Material.Grass)
		end
	end
end

local function construirCalles(padre: Instance)
	local ciudad = Juego.Ciudad
	local centro = ciudad.Centro
	local ancho = ciudad.AnchoCalle
	local largo = ciudad.Tamano
	local k = math.floor(largo / 2 / ciudad.SeparacionCalles)

	local calles = Instance.new("Folder")
	calles.Name = "Calles"
	calles.Parent = padre
	for i = -k, k do
		local d = i * ciudad.SeparacionCalles
		-- Alturas ligeramente distintas para evitar parpadeo en los cruces
		bloque("CalleX", Vector3.new(largo, 0.3, ancho), CFrame.new(centro + Vector3.new(0, 0.15, d)), COLOR_ASFALTO, calles, nil, Enum.Material.Asphalt)
		decorado(detalle("LineaX", Vector3.new(largo, 0.36, 1.2), CFrame.new(centro + Vector3.new(0, 0.18, d)), COLOR_LINEA, calles))
		bloque("CalleZ", Vector3.new(ancho, 0.34, largo), CFrame.new(centro + Vector3.new(d, 0.17, 0)), COLOR_ASFALTO, calles, nil, Enum.Material.Asphalt)
		decorado(detalle("LineaZ", Vector3.new(1.2, 0.4, largo), CFrame.new(centro + Vector3.new(d, 0.2, 0)), COLOR_LINEA, calles))
	end

	-- Pasos de cebra en los cruces interiores
	local cebras = Instance.new("Folder")
	cebras.Name = "PasosCebra"
	cebras.Parent = padre
	local franjas = math.floor(ancho / 5)
	for ix = -(k - 1), k - 1 do
		for iz = -(k - 1), k - 1 do
			local cruce = centro + Vector3.new(ix * ciudad.SeparacionCalles, 0.45, iz * ciudad.SeparacionCalles)
			local separacion = ancho / 2 + 7
			for _, lado in { -1, 1 } do
				for f = 0, franjas - 1 do
					local desplazamiento = -ancho / 2 + 2.5 + f * 5
					-- Cruzando la calle este-oeste (franjas largas en X)
					decorado(bloque("Cebra", Vector3.new(9, 0.1, 2.6), CFrame.new(cruce + Vector3.new(lado * separacion, 0, desplazamiento)), COLOR_CEBRA, cebras))
					-- Cruzando la calle norte-sur (franjas largas en Z)
					decorado(bloque("Cebra", Vector3.new(2.6, 0.1, 9), CFrame.new(cruce + Vector3.new(desplazamiento, 0, lado * separacion)), COLOR_CEBRA, cebras))
				end
			end
		end
	end

	-- Farolas en ambas aceras, saltando los cruces
	local farolas = Instance.new("Folder")
	farolas.Name = "Farolas"
	farolas.Parent = padre
	local paso = 90
	for i = -k, k do
		local d = i * ciudad.SeparacionCalles
		local t = -largo / 2 + paso / 2
		while t < largo / 2 do
			local enCruce = math.abs(((t + ciudad.SeparacionCalles / 2) % ciudad.SeparacionCalles) - ciudad.SeparacionCalles / 2) < ancho
			if not enCruce then
				for _, lado in { -1, 1 } do
					local acera = lado * (ancho / 2 + 4)
					for _, eje in { "X", "Z" } do
						local base = if eje == "X"
							then centro + Vector3.new(t, 0, d + acera)
							else centro + Vector3.new(d + acera, 0, t)
						columna("Poste", 0.6, 20, base, Color3.fromRGB(80, 60, 120), farolas)
						decorado(detalle("Bombilla", Vector3.one * 3, CFrame.new(base + Vector3.new(0, 21, 0)), Color3.fromRGB(255, 240, 200), farolas, Enum.PartType.Ball))
					end
				end
			end
			t += paso
		end
	end
end

-- ─── Vegetación y parques ────────────────────────────────────────────────────

local function arbol(posicion: Vector3, aleatorio: Random, padre: Instance)
	local alto = aleatorio:NextNumber(10, 16)
	columna("Tronco", 1.4, alto, posicion, Color3.fromRGB(170, 110, 80), padre)
	local copa = aleatorio:NextNumber(12, 18)
	bloque("Copa", Vector3.one * copa, CFrame.new(posicion + Vector3.new(0, alto + copa * 0.3, 0)), COLORES_COLINA[aleatorio:NextInteger(1, #COLORES_COLINA)], padre, Enum.PartType.Ball)
end

local function construirParque(centro: Vector3, lado: number, aleatorio: Random, padre: Instance)
	local suelo = centro.Y + ALTURA_ACERA
	bloque("Cesped", Vector3.new(lado - 10, 0.6, lado - 10), CFrame.new(centro + Vector3.new(0, ALTURA_ACERA + 0.3, 0)), COLOR_CESPED, padre, nil, Enum.Material.Grass)
	-- Caminos en cruz
	bloque("Camino", Vector3.new(lado - 10, 0.7, 10), CFrame.new(centro + Vector3.new(0, ALTURA_ACERA + 0.35, 0)), COLOR_ACERA, padre)
	bloque("Camino", Vector3.new(10, 0.72, lado - 10), CFrame.new(centro + Vector3.new(0, ALTURA_ACERA + 0.36, 0)), COLOR_ACERA, padre)
	-- Fuente central
	local acento = NEONES[aleatorio:NextInteger(1, #NEONES)]
	disco("BordeFuente", 16, 1, Vector3.new(centro.X, suelo + 1, centro.Z), acento, padre, Enum.Material.SmoothPlastic)
	columna("Fuente", 14, 4, Vector3.new(centro.X, suelo + 1, centro.Z), Color3.new(1, 1, 1), padre)
	columna("Agua", 12, 4.3, Vector3.new(centro.X, suelo + 1, centro.Z), Color3.fromRGB(120, 220, 255), padre, Enum.Material.SmoothPlastic)
	decorado(detalle("Chorro", Vector3.new(4, 14, 4), CFrame.new(centro.X, suelo + 12, centro.Z), Color3.fromRGB(190, 240, 255), padre))
	-- Árboles en los cuatro cuadrantes
	for _, cuadrante in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		for _ = 1, 3 do
			local x = cuadrante.X * aleatorio:NextNumber(20, lado / 2 - 20)
			local z = cuadrante.Y * aleatorio:NextNumber(20, lado / 2 - 20)
			arbol(Vector3.new(centro.X + x, suelo + 0.6, centro.Z + z), aleatorio, padre)
		end
	end
end

-- ─── Rascacielos ─────────────────────────────────────────────────────────────

local function rascacielos(centro: Vector3, ancho: number, fondo: number, alto: number, aleatorio: Random, padre: Instance): Model
	local color = PASTELES[aleatorio:NextInteger(1, #PASTELES)]
	local acento = NEONES[aleatorio:NextInteger(1, #NEONES)]
	local modelo = Instance.new("Model")
	modelo.Name = "Rascacielos"
	local suelo = centro.Y + ALTURA_ACERA

	-- Zócalo + cuerpo
	bloque("Zocalo", Vector3.new(ancho + 4, 8, fondo + 4), CFrame.new(centro.X, suelo + 4, centro.Z), color:Lerp(COLOR_CONTORNO, 0.35), modelo)
	bloque("Cuerpo", Vector3.new(ancho, alto, fondo), CFrame.new(centro.X, suelo + alto / 2, centro.Z), color, modelo, nil, MATERIALES_FACHADA[aleatorio:NextInteger(1, #MATERIALES_FACHADA)])

	-- Ventanas encendidas: bandas finas alrededor del cuerpo
	local y = suelo + 14
	while y < suelo + alto - 8 do
		ventana("Ventanas", Vector3.new(ancho + 0.4, 4, fondo + 0.4), CFrame.new(centro.X, y, centro.Z), modelo)
		y += 9
	end

	-- Retranqueo (piso superior más estrecho) en algunos
	local techo = suelo + alto
	local escalaCima = 1
	if aleatorio:NextNumber() < 0.4 then
		local alto2 = alto * aleatorio:NextNumber(0.15, 0.3)
		escalaCima = 0.65
		bloque("Torre", Vector3.new(ancho * escalaCima, alto2, fondo * escalaCima), CFrame.new(centro.X, techo + alto2 / 2, centro.Z), color:Lerp(Color3.new(1, 1, 1), 0.2), modelo)
		bloque("CornisaBaja", Vector3.new(ancho + 3, 2, fondo + 3), CFrame.new(centro.X, techo, centro.Z), acento:Lerp(color, 0.4), modelo)
		techo += alto2
	end

	-- Cornisa superior
	bloque("Cornisa", Vector3.new(ancho * escalaCima + 3, 2.5, fondo * escalaCima + 3), CFrame.new(centro.X, techo + 1, centro.Z), acento:Lerp(color, 0.4), modelo)

	-- Azotea
	local tipo = aleatorio:NextInteger(1, 4)
	local cima = Vector3.new(centro.X, techo + 2.2, centro.Z)
	if tipo == 1 then
		columna("Antena", 0.8, 28, cima, Color3.fromRGB(235, 235, 255), modelo)
		decorado(detalle("LuzAntena", Vector3.one * 3, CFrame.new(cima + Vector3.new(0, 29, 0)), Color3.fromRGB(255, 60, 80), modelo, Enum.PartType.Ball))
	elseif tipo == 2 then
		columna("Deposito", 6, 10, cima + Vector3.new(ancho * 0.2, 0, 0), Color3.fromRGB(200, 160, 120), modelo)
		bloque("TapaDeposito", Vector3.new(2, 13, 13), CFrame.new(cima + Vector3.new(ancho * 0.2, 11, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(160, 110, 80), modelo, Enum.PartType.Cylinder)
	elseif tipo == 3 then
		bloque("Aguja", Vector3.new(ancho * 0.3, 14, fondo * 0.3), CFrame.new(cima + Vector3.new(0, 7, 0)), acento:Lerp(color, 0.5), modelo)
		columna("Punta", 1, 18, cima + Vector3.new(0, 14, 0), acento, modelo, Enum.Material.SmoothPlastic)
	else
		bloque("Cupula", Vector3.one * math.min(ancho, fondo) * 0.6, CFrame.new(cima), acento:Lerp(color, 0.5), modelo, Enum.PartType.Ball)
	end

	-- Letrero neón en una cara (no todos)
	if aleatorio:NextNumber() < 0.35 then
		local alturaLetrero = suelo + math.min(alto * 0.45, 40)
		local letrero = decorado(detalle("Letrero", Vector3.new(ancho * 0.8, 8, 1), CFrame.new(centro.X, alturaLetrero, centro.Z - fondo / 2 - 0.6), acento, modelo))
		letreroTexto(letrero, LETREROS[aleatorio:NextInteger(1, #LETREROS)], Enum.NormalId.Front)
	end

	modelo.Parent = padre
	return modelo
end

local function puente(a: Vector3, b: Vector3, altura: number, padre: Instance)
	local inicio = Vector3.new(a.X, altura, a.Z)
	local fin = Vector3.new(b.X, altura, b.Z)
	local largo = (fin - inicio).Magnitude
	local cframe = CFrame.lookAt((inicio + fin) / 2, fin)
	bloque("Puente", Vector3.new(10, 6, largo), cframe, Color3.fromRGB(200, 230, 255), padre, nil, Enum.Material.Glass).Transparency = 0.3
	decorado(detalle("BordePuente", Vector3.new(10.4, 0.8, largo), cframe * CFrame.new(0, -3, 0), Color3.fromRGB(0, 210, 255), padre))
end

local function construirManzanas(padre: Instance, principales: { [string]: boolean })
	local ciudad = Juego.Ciudad
	local aleatorio = Random.new(ciudad.Semilla)
	local lado = ciudad.SeparacionCalles - ciudad.AnchoCalle
	local esParque: { [string]: boolean } = {}
	for _, p in PARQUES do
		esParque[`{p.X},{p.Y}`] = true
	end

	local carpeta = Instance.new("Folder")
	carpeta.Name = "Manzanas"
	carpeta.Parent = padre

	local k = math.floor(ciudad.Tamano / 2 / ciudad.SeparacionCalles)
	for ix = -k, k - 1 do
		for iz = -k, k - 1 do
			local rel = Vector2.new((ix + 0.5) * ciudad.SeparacionCalles, (iz + 0.5) * ciudad.SeparacionCalles)
			local centro = aMundo(rel, 0)
			local clave = `{rel.X},{rel.Y}`
			bloque("Acera", Vector3.new(lado, ALTURA_ACERA, lado), CFrame.new(centro + Vector3.new(0, ALTURA_ACERA / 2, 0)), COLOR_ACERA, carpeta, nil, Enum.Material.Concrete)

			if principales[clave] then
				-- Edificio defendible + árboles alrededor
				for _, esquina in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
					arbol(centro + Vector3.new(esquina.X * (lado / 2 - 14), ALTURA_ACERA, esquina.Y * (lado / 2 - 14)), aleatorio, carpeta)
				end
			elseif esParque[clave] then
				construirParque(centro, lado, aleatorio, carpeta)
			else
				-- 3×3 rascacielos por manzana
				local paso = lado / 3
				local torres: { [string]: { centro: Vector3, alto: number } } = {}
				for gx = -1, 1 do
					for gz = -1, 1 do
						local c = centro + Vector3.new(gx * paso, 0, gz * paso)
						local ancho = aleatorio:NextNumber(34, paso - 18)
						local fondo = aleatorio:NextNumber(34, paso - 18)
						local alto = aleatorio:NextNumber(ciudad.AlturaMinRascacielos, ciudad.AlturaMaxRascacielos)
						rascacielos(c, ancho, fondo, alto, aleatorio, carpeta)
						torres[`{gx},{gz}`] = { centro = c, alto = alto }
					end
				end
				-- Puentes aéreos entre algunas torres vecinas
				for _, par in { { "-1,0", "0,0" }, { "0,1", "1,1" } } do
					local a, b = torres[par[1]], torres[par[2]]
					if a and b and aleatorio:NextNumber() < 0.7 then
						puente(a.centro, b.centro, centro.Y + math.min(a.alto, b.alto) * 0.55, carpeta)
					end
				end
			end
		end
	end
end

-- ─── Fondo: rascacielos lejanos y colinas ────────────────────────────────────

local function construirFondo(padre: Instance)
	local ciudad = Juego.Ciudad
	local aleatorio = Random.new(ciudad.Semilla + 1)
	local carpeta = Instance.new("Folder")
	carpeta.Name = "Fondo"
	carpeta.Parent = padre

	local torres = 44
	for i = 1, torres do
		local angulo = (i / torres) * math.pi * 2 + aleatorio:NextNumber(-0.04, 0.04)
		local radio = ciudad.RadioAnilloFondo + aleatorio:NextNumber(-30, 60)
		local base = ciudad.Centro + Vector3.new(math.cos(angulo) * radio, 0, math.sin(angulo) * radio)
		local ancho = aleatorio:NextNumber(50, 90)
		local alto = aleatorio:NextNumber(130, 280)
		local color = PASTELES[aleatorio:NextInteger(1, #PASTELES)]:Lerp(Color3.fromRGB(180, 190, 230), 0.35)
		bloque("TorreFondo", Vector3.new(ancho, alto, ancho), CFrame.new(base + Vector3.new(0, alto / 2, 0)) * CFrame.Angles(0, angulo, 0), color, carpeta)
		for f = 1, 2 do
			ventana("BandaFondo", Vector3.new(ancho + 0.6, 6, ancho + 0.6), CFrame.new(base + Vector3.new(0, alto * f / 3, 0)) * CFrame.Angles(0, angulo, 0), carpeta)
		end
	end

	local colinas = 32
	for i = 1, colinas do
		local angulo = (i / colinas) * math.pi * 2
		local radio = ciudad.RadioColinas + aleatorio:NextNumber(-40, 80)
		local tamano = aleatorio:NextNumber(330, 560)
		local centro = ciudad.Centro + Vector3.new(math.cos(angulo) * radio, -tamano * 0.22, math.sin(angulo) * radio)
		bloque("Colina", Vector3.one * tamano, CFrame.new(centro), COLORES_COLINA[aleatorio:NextInteger(1, #COLORES_COLINA)], carpeta, Enum.PartType.Ball)
	end
end

local function construirPlazaCentral(padre: Instance)
	local ciudad = Juego.Ciudad
	local centro = ciudad.Centro
	local radio = ciudad.RadioPlazaCentral
	disco("BordePlazaCentral", radio + 3, 0.8, centro + Vector3.new(0, 0.6, 0), Color3.fromRGB(255, 60, 170), padre, Enum.Material.SmoothPlastic)
	disco("PlazaCentral", radio, 1, centro + Vector3.new(0, 0.75, 0), Color3.fromRGB(255, 205, 230), padre)
	columna("Monumento", 8, 26, centro + Vector3.new(0, 1.2, 0), Color3.fromRGB(255, 255, 255), padre)
	decorado(detalle("Estrella", Vector3.one * 10, CFrame.new(centro + Vector3.new(0, 33, 0)), Color3.fromRGB(255, 230, 90), padre, Enum.PartType.Ball))

	-- Punto de llegada desde el Lobby (las plataformas teletransportan aquí)
	puntoAparicion = CFrame.lookAt(centro + Vector3.new(0, 5, 34), centro + Vector3.new(0, 5, 0))
end

-- ─── Edificios principales ───────────────────────────────────────────────────

local function crearBarraVida(config: EdificioConfig, cuerpo: BasePart): (Frame, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BarraVida"
	gui.Adornee = cuerpo
	-- Tamaño en studs (escala con la distancia), sin AlwaysOnTop y visible solo de cerca
	gui.Size = UDim2.fromScale(46, 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, cuerpo.Size.Y / 2 + 18, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Parent = cuerpo

	local nombre = Instance.new("TextLabel")
	nombre.BackgroundTransparency = 1
	nombre.Size = UDim2.fromScale(1, 0.5)
	nombre.Font = FUENTE
	nombre.Text = config.Nombre
	nombre.TextScaled = true
	nombre.TextColor3 = Color3.new(1, 1, 1)
	nombre.TextStrokeTransparency = 0
	nombre.TextStrokeColor3 = COLOR_CONTORNO
	nombre.Parent = gui

	local fondo = Instance.new("Frame")
	fondo.Position = UDim2.fromScale(0, 0.55)
	fondo.Size = UDim2.fromScale(1, 0.42)
	fondo.BackgroundColor3 = COLOR_CONTORNO
	fondo.Parent = gui
	local esquina = Instance.new("UICorner")
	esquina.CornerRadius = UDim.new(0.5, 0)
	esquina.Parent = fondo
	local trazo = Instance.new("UIStroke")
	trazo.Thickness = 3
	trazo.Color = Color3.new(0, 0, 0)
	trazo.Parent = fondo

	local barra = Instance.new("Frame")
	barra.Size = UDim2.fromScale(1, 1)
	barra.BackgroundColor3 = config.ColorAcento
	barra.Parent = fondo
	local esquinaBarra = Instance.new("UICorner")
	esquinaBarra.CornerRadius = UDim.new(0.5, 0)
	esquinaBarra.Parent = barra

	local texto = Instance.new("TextLabel")
	texto.BackgroundTransparency = 1
	texto.Size = UDim2.fromScale(1, 1)
	texto.Font = FUENTE
	texto.TextScaled = true
	texto.TextColor3 = Color3.new(1, 1, 1)
	texto.TextStrokeTransparency = 0
	texto.ZIndex = 2
	texto.Parent = fondo

	return barra, texto
end

local function actualizarBarra(estado: EstadoEdificio)
	local proporcion = math.clamp(estado.vida / estado.config.VidaMaxima, 0, 1)
	estado.barra.Size = UDim2.fromScale(proporcion, 1)
	estado.barra.BackgroundColor3 = if proporcion > 0.5
		then estado.config.ColorAcento
		elseif proporcion > 0.25 then Color3.fromRGB(255, 190, 40)
		else Color3.fromRGB(255, 50, 70)
	estado.textoVida.Text = if estado.destruido then "¡DESTRUIDO!" else `{math.ceil(estado.vida)} / {estado.config.VidaMaxima}`
	estado.modelo:SetAttribute("Vida", estado.vida)
end

local function construirEdificioPrincipal(config: EdificioConfig, padre: Instance): EstadoEdificio
	local posicion = aMundo(config.Posicion, ALTURA_ACERA)
	local mirarA = Vector3.new(Juego.Ciudad.Centro.X, posicion.Y, Juego.Ciudad.Centro.Z)
	local base = if (mirarA - posicion).Magnitude > 1 then CFrame.lookAt(posicion, mirarA) else CFrame.new(posicion)
	local t = config.Tamano

	local modelo = Instance.new("Model")
	modelo.Name = config.Id

	local cuerpo = bloque("Cuerpo", t, base * CFrame.new(0, t.Y / 2, 0), config.Color, modelo, nil, Enum.Material.Concrete)

	-- Ventanas encendidas y franjas neón alternas
	local nivel = 0
	local y = 16
	while y < t.Y - 6 do
		nivel += 1
		if nivel % 3 == 0 then
			decorado(detalle("Franja", Vector3.new(t.X + 0.6, 2, t.Z + 0.6), base * CFrame.new(0, y, 0), config.ColorAcento, modelo))
		else
			ventana("Ventanas", Vector3.new(t.X + 0.4, 4, t.Z + 0.4), base * CFrame.new(0, y, 0), modelo)
		end
		y += 10
	end
	bloque("Cornisa", Vector3.new(t.X + 4, 3, t.Z + 4), base * CFrame.new(0, t.Y + 1.5, 0), config.ColorAcento:Lerp(config.Color, 0.35), modelo)

	-- Puerta y letrero hacia el centro de la ciudad (frente = -Z de "base")
	bloque("Puerta", Vector3.new(16, 22, 1), base * CFrame.new(0, 11, -t.Z / 2 - 0.4), config.ColorAcento:Lerp(COLOR_CONTORNO, 0.4), modelo)
	local letrero = decorado(detalle("Letrero", Vector3.new(math.min(t.X * 0.85, 56), 11, 1), base * CFrame.new(0, 30, -t.Z / 2 - 0.7), config.ColorAcento, modelo))
	letreroTexto(letrero, config.Nombre, Enum.NormalId.Front)

	-- Techo
	local cima = t.Y + 3
	if config.Techo == "Cupula" then
		bloque("Cupula", Vector3.one * math.min(t.X, t.Z) * 0.8, base * CFrame.new(0, cima, 0), config.ColorAcento:Lerp(config.Color, 0.5), modelo, Enum.PartType.Ball)
		decorado(detalle("Punta", Vector3.one * 6, base * CFrame.new(0, cima + math.min(t.X, t.Z) * 0.4 + 2, 0), config.ColorAcento, modelo, Enum.PartType.Ball))
	elseif config.Techo == "Piramide" then
		local alto = math.min(t.X, t.Z) * 0.35
		local delante = Instance.new("WedgePart")
		delante.Name = "Tejado"
		delante.Size = Vector3.new(t.X + 2, alto, t.Z / 2 + 1)
		delante.CFrame = base * CFrame.new(0, cima + alto / 2, -t.Z / 4)
		delante.Color = config.ColorAcento:Lerp(config.Color, 0.35)
		delante.Material = Enum.Material.SmoothPlastic
		delante.Anchored = true
		delante.Parent = modelo
		local detras = delante:Clone()
		detras.CFrame = base * CFrame.new(0, cima + alto / 2, t.Z / 4) * CFrame.Angles(0, math.rad(180), 0)
		detras.Parent = modelo
	elseif config.Techo == "Antena" then
		bloque("Antena", Vector3.new(50, 2.4, 2.4), base * CFrame.new(0, cima + 25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 240, 255), modelo, Enum.PartType.Cylinder)
		decorado(detalle("Luz", Vector3.one * 7, base * CFrame.new(0, cima + 51, 0), config.ColorAcento, modelo, Enum.PartType.Ball))
	else
		bloque("Azotea", Vector3.new(t.X + 2, 2, t.Z + 2), base * CFrame.new(0, cima, 0), config.ColorAcento:Lerp(config.Color, 0.4), modelo)
		disco("Helipuerto", math.min(t.X, t.Z) * 0.3, 0.4, (base * CFrame.new(0, cima + 1.2, 0)).Position, Color3.new(1, 1, 1), modelo, Enum.Material.SmoothPlastic)
	end

	modelo.PrimaryPart = cuerpo
	modelo:SetAttribute("VidaMaxima", config.VidaMaxima)
	modelo:SetAttribute("Destruido", false)
	CollectionService:AddTag(modelo, ETIQUETA_EDIFICIO)
	modelo.Parent = padre

	local originales = {}
	for _, d in modelo:GetDescendants() do
		if d:IsA("BasePart") then
			originales[d] = { cframe = d.CFrame, color = d.Color }
		end
	end

	local barra, textoVida = crearBarraVida(config, cuerpo)
	local estado: EstadoEdificio = {
		config = config,
		modelo = modelo,
		cuerpo = cuerpo,
		base = base,
		vida = config.VidaMaxima,
		destruido = false,
		parpadeando = false,
		originales = originales,
		tweens = {},
		barra = barra,
		textoVida = textoVida,
	}
	actualizarBarra(estado)
	return estado
end

local function contarEnPie(): number
	local n = 0
	for _, estado in edificios do
		if not estado.destruido then
			n += 1
		end
	end
	ReplicatedStorage:SetAttribute("EdificiosEnPie", n)
	return n
end

local function destruir(estado: EstadoEdificio)
	estado.destruido = true
	estado.modelo:SetAttribute("Destruido", true)
	actualizarBarra(estado)

	-- Derrumbe: todo se hunde y se oscurece
	local hundir = Vector3.new(0, -estado.config.Tamano.Y * 0.6, 0)
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	for parte, original in estado.originales do
		local tween = TweenService:Create(parte, info, {
			CFrame = original.cframe + hundir,
			Color = original.color:Lerp(COLOR_RUINAS, 0.75),
		})
		table.insert(estado.tweens, tween)
		tween:Play()
	end
	local humo = Instance.new("Smoke")
	humo.Name = "Humo"
	humo.Size = 40
	humo.RiseVelocity = 16
	humo.Color = Color3.fromRGB(90, 80, 100)
	humo.Parent = estado.cuerpo
	local fuego = Instance.new("Fire")
	fuego.Name = "Fuego"
	fuego.Size = 30
	fuego.Parent = estado.cuerpo

	if contarEnPie() == 0 then
		local callback = alCaerTodos
		if callback then
			task.spawn(callback)
		end
	end
end

-- ─── API pública ─────────────────────────────────────────────────────────────

function EdificioService.Danar(edificio: Model, cantidad: number)
	local estado = porModelo[edificio]
	if not estado or estado.destruido or cantidad <= 0 then
		return
	end
	estado.vida = math.max(0, estado.vida - cantidad)
	actualizarBarra(estado)

	if not estado.parpadeando then
		estado.parpadeando = true
		local original = estado.originales[estado.cuerpo].color
		estado.cuerpo.Color = Color3.new(1, 1, 1)
		task.delay(0.08, function()
			if not estado.destruido then
				estado.cuerpo.Color = original
			end
			estado.parpadeando = false
		end)
	end

	if estado.vida <= 0 then
		destruir(estado)
	end
end

-- Edificio en pie más cercano: (modelo, punto más cercano de su planta a nivel del suelo, distancia horizontal)
function EdificioService.MasCercano(posicion: Vector3): (Model?, Vector3, number)
	local mejor: EstadoEdificio? = nil
	local mejorPunto = posicion
	local mejorDistancia = math.huge
	for _, estado in edificios do
		if not estado.destruido then
			local t = estado.config.Tamano
			local relativo = estado.base:PointToObjectSpace(posicion)
			local enPlanta = Vector3.new(math.clamp(relativo.X, -t.X / 2, t.X / 2), 0, math.clamp(relativo.Z, -t.Z / 2, t.Z / 2))
			local punto = estado.base:PointToWorldSpace(enPlanta)
			local distancia = Vector3.new(posicion.X - punto.X, 0, posicion.Z - punto.Z).Magnitude
			if distancia < mejorDistancia then
				mejor, mejorPunto, mejorDistancia = estado, punto, distancia
			end
		end
	end
	return if mejor then mejor.modelo else nil, mejorPunto, mejorDistancia
end

function EdificioService.CantidadEnPie(): number
	return contarEnPie()
end

function EdificioService.AlCaerTodos(callback: () -> ())
	alCaerTodos = callback
end

function EdificioService.PuntosAparicionMonstruos(): { Vector3 }
	local puntos = {}
	for _, rel in Juego.PuntosAparicionMonstruos do
		table.insert(puntos, aMundo(rel, 0))
	end
	return puntos
end

-- CFrame de llegada en la Plaza Central (lo usa LobbyService al teletransportar).
function EdificioService.PuntoAparicionHeroinas(): CFrame
	return puntoAparicion
end

-- Levanta un edificio (deshace el derrumbe) y le pone la vida indicada.
local function levantar(estado: EstadoEdificio, vida: number)
	for _, tween in estado.tweens do
		tween:Cancel()
	end
	table.clear(estado.tweens)
	for parte, original in estado.originales do
		parte.CFrame = original.cframe
		parte.Color = original.color
	end
	for _, nombre in { "Humo", "Fuego" } do
		local efecto = estado.cuerpo:FindFirstChild(nombre)
		if efecto then
			efecto:Destroy()
		end
	end
	estado.vida = math.clamp(vida, 1, estado.config.VidaMaxima)
	estado.destruido = false
	estado.modelo:SetAttribute("Destruido", false)
	actualizarBarra(estado)
end

-- Reconstruye todos los edificios con la vida llena.
function EdificioService.Restaurar()
	for _, estado in edificios do
		levantar(estado, estado.config.VidaMaxima)
	end
	contarEnPie()
end

-- Cura los edificios EN PIE una fracción de su vida máxima (p. ej. 0.25 = +25 %).
function EdificioService.Reparar(fraccion: number)
	for _, estado in edificios do
		if not estado.destruido then
			estado.vida = math.min(estado.config.VidaMaxima, estado.vida + estado.config.VidaMaxima * fraccion)
			actualizarBarra(estado)
		end
	end
end

-- Reconstruye los edificios CAÍDOS con una fracción de su vida máxima. Devuelve cuántos se levantaron.
function EdificioService.Reconstruir(fraccion: number): number
	local n = 0
	for _, estado in edificios do
		if estado.destruido then
			levantar(estado, estado.config.VidaMaxima * fraccion)
			n += 1
		end
	end
	contarEnPie()
	return n
end

function EdificioService.Init()
	configurarIluminacion()

	local ciudad = Instance.new("Folder")
	ciudad.Name = "SugarTown"

	local principales: { [string]: boolean } = {}
	for _, config in Juego.Edificios do
		principales[`{config.Posicion.X},{config.Posicion.Y}`] = true
	end

	construirSuelo(ciudad)
	construirCalles(ciudad)
	construirManzanas(ciudad, principales)
	construirFondo(ciudad)
	construirPlazaCentral(ciudad)

	local carpetaPrincipales = Instance.new("Folder")
	carpetaPrincipales.Name = "EdificiosDefendibles"
	carpetaPrincipales.Parent = ciudad
	for _, config in Juego.Edificios do
		local estado = construirEdificioPrincipal(config, carpetaPrincipales)
		table.insert(edificios, estado)
		porModelo[estado.modelo] = estado
	end

	ciudad.Parent = Workspace
	ReplicatedStorage:SetAttribute("EdificiosTotales", #edificios)
	contarEnPie()
end

return EdificioService
