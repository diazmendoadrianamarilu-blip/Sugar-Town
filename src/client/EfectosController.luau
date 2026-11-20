--!strict
-- EfectosController: visuales de los poderes (solo estético, nunca decide daño).
-- La jugadora local los ve al instante (PoderesController llama a Reproducir);
-- los de otras jugadoras llegan por el RemoteEvent "EfectoPoder".

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Poderes = require(Shared.Config.Poderes)
local Remotes = require(Shared.Remotes)
local Sonidos = require(Shared.Config.Sonidos)
local Types = require(Shared.Types)
local PoseVueloController = require(script.Parent.PoseVueloController)

type PoderConfig = Types.PoderConfig

local jugadorLocal = Players.LocalPlayer
local TRANSPARENCIA_EFECTO = 0.65
local carpeta: Folder
local sonidoViento: Sound? = nil
local trauma = 0 -- intensidad actual de la sacudida de cámara (0..1)
local aleatorioSonido = Random.new()

-- Sacudida de cámara por tipo de poder (se atenúa con la distancia a la cámara)
local SACUDIDA: { [Types.TipoPoder]: number } = {
	Rayo = 0.15,
	Rafaga = 0.06,
	Onda = 0.6,
	Impulso = 0.3,
	Escudo = 0.1,
	Pulso = 0.45,
	Laser = 0, -- la aplica efectoLaser al disparar
	Dulce = 0.05,
	Martillo = 0, -- la aplica efectoMartillo al caer
	Estrellas = 0.08,
}
local DISTANCIA_SACUDIDA = 90
-- Notas de las fanfarrias (multiplicadores de tono: acorde mayor)
local FANFARRIA_SUBE = { 1, 1.26, 1.5, 2 }
local FANFARRIA_BAJA = { 1, 0.84, 0.67, 0.5 }

local EfectosController = {}

-- ─── Utilidades ──────────────────────────────────────────────────────────────

local function parteEfecto(forma: Enum.PartType, tamano: Vector3, cframe: CFrame, color: Color3): Part
	local parte = Instance.new("Part")
	parte.Shape = forma
	parte.Size = tamano
	parte.CFrame = cframe
	parte.Color = color
	-- ForceField translúcido (nunca Neon opaco): los efectos no queman la cámara en blanco
	parte.Material = Enum.Material.ForceField
	parte.Transparency = TRANSPARENCIA_EFECTO
	parte.Anchored = true
	parte.CanCollide = false
	parte.CanQuery = false
	parte.CanTouch = false
	parte.CastShadow = false
	parte.Parent = carpeta
	return parte
end

local function animar(instancia: Instance, duracion: number, propiedades: { [string]: any }, estilo: Enum.EasingStyle?)
	local info = TweenInfo.new(duracion, estilo or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(instancia, info, propiedades):Play()
end

local function raizDe(jugador: Player): BasePart?
	local character = jugador.Character
	local raiz = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if raiz and raiz:IsA("BasePart") then
		return raiz
	end
	return nil
end

-- Punto final visual de un disparo (choca con el escenario, atraviesa a las jugadoras).
local function puntoDeImpacto(origen: Vector3, direccion: Vector3, alcance: number): Vector3
	local excluir: { Instance } = { carpeta }
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(excluir, jugador.Character)
		end
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	local resultado = Workspace:Raycast(origen, direccion * alcance, parametros)
	return if resultado then resultado.Position else origen + direccion * alcance
end

local function destello(posicion: Vector3, color: Color3, tamano: number, duracion: number)
	local bola = parteEfecto(Enum.PartType.Ball, Vector3.one * (tamano * 0.4), CFrame.new(posicion), color)
	animar(bola, duracion, { Size = Vector3.one * tamano, Transparency = 1 })
	Debris:AddItem(bola, duracion + 0.05)
end

-- Cilindro neón entre dos puntos (eje X del cilindro alineado con el segmento).
local function haz(desde: Vector3, hasta: Vector3, grosor: number, color: Color3): Part
	local largo = (hasta - desde).Magnitude
	local cframe = CFrame.lookAt((desde + hasta) / 2, hasta) * CFrame.Angles(0, math.rad(90), 0)
	return parteEfecto(Enum.PartType.Cylinder, Vector3.new(largo, grosor, grosor), cframe, color)
end

local function anillo(centro: Vector3, radio: number, color: Color3, duracion: number)
	local cframe = CFrame.new(centro) * CFrame.Angles(0, 0, math.rad(90)) -- cilindro plano (disco horizontal)
	local disco = parteEfecto(Enum.PartType.Cylinder, Vector3.new(0.4, 2, 2), cframe, color)
	disco.Transparency = TRANSPARENCIA_EFECTO
	animar(disco, duracion, { Size = Vector3.new(0.2, radio * 2, radio * 2), Transparency = 1 })
	Debris:AddItem(disco, duracion + 0.05)
end

-- ─── Sonido ──────────────────────────────────────────────────────────────────

-- Reproduce un sonido de Config/Sonidos. Con posición → 3D en el mundo; sin posición → 2D.
-- Se destruye solo al terminar (y Debris como red de seguridad: sin fugas).
-- Devuelve la instancia contenedora (destruirla corta el sonido antes de tiempo).
local function reproducirSonido(nombre: string, posicion: Vector3?, tono: number?, volumen: number?): Instance?
	local config = Sonidos[nombre]
	if not config then
		return nil
	end
	local sonido = Instance.new("Sound")
	sonido.SoundId = config.Id
	sonido.Volume = config.Volumen * (volumen or 1)
	sonido.PlaybackSpeed = config.Tono * (tono or 1) * aleatorioSonido:NextNumber(0.95, 1.05)

	local contenedor: Instance
	if posicion then
		local ancla = Instance.new("Attachment")
		ancla.Parent = Workspace.Terrain
		ancla.Position = posicion
		sonido.RollOffMinDistance = 25
		sonido.RollOffMaxDistance = 350
		sonido.Parent = ancla
		contenedor = ancla
	else
		sonido.Parent = SoundService
		contenedor = sonido
	end
	sonido.Ended:Once(function()
		contenedor:Destroy()
	end)
	Debris:AddItem(contenedor, 8)
	sonido:Play()
	return contenedor
end

local function fanfarria(notas: { number }, pausa: number)
	for i, tono in notas do
		task.delay((i - 1) * pausa, reproducirSonido, "Nota", nil, tono)
	end
end

-- ─── Sacudida de cámara ──────────────────────────────────────────────────────

local function aplicarSacudida(dt: number)
	if trauma <= 0 then
		return
	end
	local camara = Workspace.CurrentCamera
	if camara then
		-- La cámara por defecto recalcula su CFrame cada frame, así que el desplazamiento no se acumula.
		local t = os.clock() * 22
		local fuerza = trauma * trauma
		camara.CFrame *= CFrame.Angles(
			math.noise(t, 0.3) * fuerza * 0.05,
			math.noise(0.7, t) * fuerza * 0.05,
			math.noise(t, t * 0.5) * fuerza * 0.03
		)
	end
	trauma = math.max(0, trauma - dt * 1.8)
end

-- ─── Efectos por tipo ────────────────────────────────────────────────────────

local function efectoRayo(origen: Vector3, direccion: Vector3, poder: PoderConfig)
	local fin = puntoDeImpacto(origen, direccion, poder.Alcance)
	local nucleo = haz(origen, fin, 0.5, Color3.new(1, 1, 1))
	local aura = haz(origen, fin, 1.4, poder.Color)
	aura.Transparency = TRANSPARENCIA_EFECTO
	animar(nucleo, poder.Duracion, { Size = Vector3.new(nucleo.Size.X, 0.05, 0.05), Transparency = 1 })
	animar(aura, poder.Duracion, { Size = Vector3.new(aura.Size.X, 3, 3), Transparency = 1 })
	Debris:AddItem(nucleo, poder.Duracion + 0.05)
	Debris:AddItem(aura, poder.Duracion + 0.05)
	destello(fin, poder.Color, 6, 0.3)
	destello(origen, poder.Color, 3, 0.2)
	reproducirSonido("Laser", origen)
end

local function efectoOnda(origen: Vector3, poder: PoderConfig)
	local bola = parteEfecto(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(origen), poder.Color)
	bola.Transparency = TRANSPARENCIA_EFECTO
	animar(bola, poder.Duracion, { Size = Vector3.one * poder.Radio * 2, Transparency = 1 })
	Debris:AddItem(bola, poder.Duracion + 0.05)
	anillo(origen - Vector3.new(0, 2.5, 0), poder.Radio * 1.1, Color3.new(1, 1, 1), poder.Duracion * 1.2)
	reproducirSonido("Explosion", origen)
end

local function efectoRafaga(origen: Vector3, direccion: Vector3, poder: PoderConfig)
	local aleatorio = Random.new()
	local dispersion = math.rad(poder.Dispersion)
	for i = 1, poder.Cantidad do
		task.delay((i - 1) * 0.06, function()
			local giro = CFrame.Angles(
				aleatorio:NextNumber(-dispersion, dispersion),
				aleatorio:NextNumber(-dispersion, dispersion),
				0
			)
			local dir = (CFrame.lookAt(Vector3.zero, direccion) * giro).LookVector
			local fin = puntoDeImpacto(origen, dir, poder.Alcance)
			reproducirSonido("Rafaga", origen)
			local bala = parteEfecto(Enum.PartType.Ball, Vector3.new(1.2, 1.2, 1.2), CFrame.new(origen), poder.Color)
			local cola = Instance.new("Trail")
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.5, 0)
			a0.Parent = bala
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.5, 0)
			a1.Parent = bala
			cola.Attachment0 = a0
			cola.Attachment1 = a1
			cola.Color = ColorSequence.new(poder.Color, Color3.new(1, 1, 1))
			cola.Transparency = NumberSequence.new(0, 1)
			cola.LightEmission = 0.4
			cola.FaceCamera = true
			cola.Lifetime = 0.15
			cola.Parent = bala
			animar(bala, poder.Duracion, { CFrame = CFrame.new(fin) }, Enum.EasingStyle.Linear)
			task.delay(poder.Duracion, function()
				destello(fin, poder.Color, 3, 0.15)
				bala:Destroy()
			end)
		end)
	end
end

local function efectoImpulso(origen: Vector3, direccion: Vector3, poder: PoderConfig)
	local fin = origen + direccion * poder.Alcance
	-- Relámpago en zigzag a lo largo de la trayectoria
	local segmentos = 6
	local aleatorio = Random.new()
	local anterior = origen
	local lateral = direccion:Cross(Vector3.yAxis)
	lateral = if lateral.Magnitude > 0.01 then lateral.Unit else Vector3.xAxis
	for i = 1, segmentos do
		local t = i / segmentos
		local punto = origen:Lerp(fin, t)
		if i < segmentos then
			punto += lateral * aleatorio:NextNumber(-2, 2) + Vector3.yAxis * aleatorio:NextNumber(-1.5, 1.5)
		end
		local tramo = haz(anterior, punto, 0.6, poder.Color)
		animar(tramo, poder.Duracion * 1.5, { Transparency = 1, Size = Vector3.new(tramo.Size.X, 0.1, 0.1) })
		Debris:AddItem(tramo, poder.Duracion * 1.5 + 0.05)
		anterior = punto
	end
	destello(origen, Color3.new(1, 1, 1), 6, 0.25)
	reproducirSonido("Impulso", origen)
end

local function efectoEscudo(origen: Vector3, poder: PoderConfig)
	-- La esfera persistente la crea el servidor; aquí solo el "pop" de activación.
	destello(origen, poder.Color, 11, 0.35)
	anillo(origen - Vector3.new(0, 2.5, 0), poder.Radio, poder.Color, 0.6)
	reproducirSonido("Escudo", origen)
	reproducirSonido("Escudo", origen, 1.5)
end

local function efectoPulso(origen: Vector3, poder: PoderConfig)
	-- Implosión: una esfera grande que se encoge hacia la heroína (gravedad)
	local esfera = parteEfecto(Enum.PartType.Ball, Vector3.one * poder.Radio * 2, CFrame.new(origen), poder.Color)
	esfera.Material = Enum.Material.ForceField
	esfera.Transparency = TRANSPARENCIA_EFECTO
	animar(esfera, 0.45, { Size = Vector3.one * 2, Transparency = 0.9 }, Enum.EasingStyle.Back)
	Debris:AddItem(esfera, 0.5)
	reproducirSonido("Pulso", origen)
	task.delay(0.4, function()
		destello(origen, poder.Color, 8, 0.3)
		reproducirSonido("Explosion", origen, 0.8, 0.6)
	end)
	anillo(origen - Vector3.new(0, 2.5, 0), poder.Radio, poder.Color, 0.7)
end

-- Rayo láser: esfera de energía que crece en la mano derecha durante la carga (con su sonido)
-- y luego un haz recto con brillo que atraviesa a los monstruos hasta chocar con el escenario.
local function manoDerecha(character: Model): Vector3?
	local mano = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if mano and mano:IsA("BasePart") then
		return (mano.CFrame * CFrame.new(0, -mano.Size.Y / 2, 0)).Position
	end
	local raiz = character:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz.Position else nil
end

local function finLaser(origen: Vector3, direccion: Vector3, alcance: number): Vector3
	local excluir: { Instance } = { carpeta }
	for _, enemigo in CollectionService:GetTagged("Enemigo") do
		table.insert(excluir, enemigo)
	end
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(excluir, jugador.Character)
		end
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	local resultado = Workspace:Raycast(origen, direccion * alcance, parametros)
	return if resultado then resultado.Position else origen + direccion * alcance
end

-- Haz con Beam (brilla con LightEmission) entre dos puntos; se desvanece en "duracion".
local function hazBrillante(desde: Vector3, hasta: Vector3, ancho: number, color: Color3, transparencia: number, duracion: number, brillo: number)
	local a0 = Instance.new("Attachment")
	a0.WorldPosition = desde
	a0.Parent = Workspace.Terrain
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = hasta
	a1.Parent = Workspace.Terrain
	local rayo = Instance.new("Beam")
	rayo.Attachment0 = a0
	rayo.Attachment1 = a1
	rayo.Color = ColorSequence.new(color)
	rayo.LightEmission = brillo
	rayo.LightInfluence = 0
	rayo.FaceCamera = true
	rayo.Segments = 1
	rayo.Width0 = ancho
	rayo.Width1 = ancho
	rayo.Transparency = NumberSequence.new(transparencia)
	rayo.Parent = a0
	local inicio = os.clock()
	local conexion: RBXScriptConnection
	conexion = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - inicio) / duracion, 0, 1)
		rayo.Transparency = NumberSequence.new(transparencia + (1 - transparencia) * t * t)
		rayo.Width0 = ancho * (1 - 0.6 * t)
		rayo.Width1 = rayo.Width0
		if t >= 1 then
			conexion:Disconnect()
			a0:Destroy()
			a1:Destroy()
		end
	end)
	Debris:AddItem(a0, duracion + 1)
	Debris:AddItem(a1, duracion + 1)
end

local function efectoLaser(lanzador: Player, objetivo: Vector3, poder: PoderConfig)
	local character = lanzador.Character
	if not character then
		return
	end
	PoseVueloController.ReproducirGolpe(character, "Disparo")
	local inicioMano = manoDerecha(character)
	if not inicioMano then
		return
	end

	-- 1) Carga: esfera que crece y sigue a la mano, con luz del color de la heroína
	local esfera = parteEfecto(Enum.PartType.Ball, Vector3.one * 0.4, CFrame.new(inicioMano), poder.Color)
	local luz = Instance.new("PointLight")
	luz.Color = poder.Color
	luz.Range = 10
	luz.Brightness = 2
	luz.Parent = esfera
	-- Núcleo pequeño y casi opaco (es un detalle pequeño: no tapa la cámara)
	local nucleo = parteEfecto(Enum.PartType.Ball, Vector3.one * 0.2, CFrame.new(inicioMano), poder.Color:Lerp(Color3.new(1, 1, 1), 0.6))
	nucleo.Material = Enum.Material.SmoothPlastic
	nucleo.Transparency = 0.1
	local sonidoCarga = reproducirSonido("LaserCarga", inicioMano)
	local inicio = os.clock()
	local seguir = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - inicio) / math.max(poder.Carga, 0.01), 0, 1)
		local mano = manoDerecha(character) or inicioMano
		esfera.CFrame = CFrame.new(mano)
		nucleo.CFrame = esfera.CFrame
		esfera.Size = Vector3.one * (0.4 + 2.4 * t)
		nucleo.Size = Vector3.one * (0.2 + 1.1 * t)
		luz.Brightness = 1 + 4 * t
	end)

	-- 2) Disparo al terminar la carga
	task.delay(poder.Carga, function()
		seguir:Disconnect()
		esfera:Destroy()
		nucleo:Destroy()
		if sonidoCarga then
			sonidoCarga:Destroy() -- la carga termina justo cuando sale el disparo
		end
		if not character.Parent then
			return
		end
		local origen = manoDerecha(character) or inicioMano
		local hacia = objetivo - origen
		local direccion = if hacia.Magnitude > 0.1 then hacia.Unit else Vector3.zAxis
		local fin = finLaser(origen, direccion, poder.Alcance)
		hazBrillante(origen, fin, 3.4, poder.Color, 0.1, poder.Duracion, 0.35) -- color saturado
		hazBrillante(origen, fin, 1, Color3.new(1, 1, 1), 0, poder.Duracion * 0.8, 1) -- núcleo brillante
		local aura = haz(origen, fin, 2.4, poder.Color)
		animar(aura, poder.Duracion, { Size = Vector3.new(aura.Size.X, 4, 4), Transparency = 1 })
		Debris:AddItem(aura, poder.Duracion + 0.05)
		destello(origen, poder.Color, 4, 0.25)
		destello(fin, poder.Color, 8, 0.35)
		reproducirSonido("LaserDisparo", origen)
		local camara = Workspace.CurrentCamera
		if camara then
			local distancia = (camara.CFrame.Position - origen).Magnitude
			EfectosController.Sacudir(0.25 * math.clamp(1 - distancia / DISTANCIA_SACUDIDA, 0, 1))
		end
	end)
end

-- ─── Armas ───────────────────────────────────────────────────────────────────

-- Pieza sólida pequeña (caramelos, estrellas, martillo): opaca, sin sombra ni colisión.
local function pieza(forma: Enum.PartType, tamano: Vector3, cframe: CFrame, color: Color3): Part
	local p = parteEfecto(forma, tamano, cframe, color)
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 0
	return p
end

local function sinPersonajes(extra: Instance?): RaycastParams
	local excluir: { Instance } = { carpeta }
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(excluir, jugador.Character)
		end
	end
	if extra then
		table.insert(excluir, extra)
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	return parametros
end

-- Lanzador de Dulces: caramelo de dos colores que vuela hasta el impacto y estalla en confeti.
local function efectoDulce(lanzador: Player, origen: Vector3, direccion: Vector3, poder: PoderConfig)
	local character = lanzador.Character
	if character then
		PoseVueloController.ReproducirGolpe(character, "PunoDerecho")
	end
	local salida = (if character then manoDerecha(character) else nil) or origen
	-- Igual que el servidor: el caramelo solo se detiene en un monstruo
	local soloEnemigos = RaycastParams.new()
	soloEnemigos.FilterType = Enum.RaycastFilterType.Include
	soloEnemigos.FilterDescendantsInstances = CollectionService:GetTagged("Enemigo")
	local golpe = Workspace:Spherecast(salida, poder.Radio, direccion * poder.Alcance, soloEnemigos)
	local fin = if golpe then golpe.Position else salida + direccion * poder.Alcance
	local caramelo = pieza(Enum.PartType.Ball, Vector3.one * 1.8, CFrame.new(salida), poder.Color)
	local franja = pieza(Enum.PartType.Cylinder, Vector3.new(0.5, 1.9, 1.9), CFrame.new(salida), Color3.new(1, 1, 1))
	reproducirSonido("Dulce", salida)
	local inicio = os.clock()
	local conexion: RBXScriptConnection
	conexion = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - inicio) / poder.Duracion, 0, 1)
		caramelo.CFrame = CFrame.new(salida:Lerp(fin, t)) * CFrame.Angles(0, 0, t * 12)
		franja.CFrame = caramelo.CFrame
		if t >= 1 then
			conexion:Disconnect()
			caramelo:Destroy()
			franja:Destroy()
			destello(fin, poder.Color, 6, 0.25)
			local colores = { poder.Color, Color3.fromRGB(120, 230, 255), Color3.fromRGB(255, 230, 90), Color3.new(1, 1, 1) }
			for i = 1, 10 do
				local trozo = pieza(Enum.PartType.Block, Vector3.one * 0.5, CFrame.new(fin), colores[(i % #colores) + 1])
				local salto = fin + Vector3.new(math.random(-6, 6), math.random(2, 7), math.random(-6, 6))
				animar(trozo, 0.45, { CFrame = CFrame.new(salto) * CFrame.Angles(math.random(), math.random(), math.random()), Size = Vector3.one * 0.1 })
				Debris:AddItem(trozo, 0.5)
			end
		end
	end)
	Debris:AddItem(caramelo, poder.Duracion + 1)
	Debris:AddItem(franja, poder.Duracion + 1)
end

-- Martillo de Caramelo: un martillo gigante de rayas aparece arriba y golpea el suelo delante.
local function efectoMartillo(lanzador: Player, origen: Vector3, direccion: Vector3, poder: PoderConfig)
	local character = lanzador.Character
	if character then
		PoseVueloController.ReproducirGolpe(character, "PunoDerecho")
	end
	local plano = Vector3.new(direccion.X, 0, direccion.Z)
	plano = if plano.Magnitude > 0.01 then plano.Unit else Vector3.new(0, 0, -1)
	local centro = origen + plano * poder.Alcance
	local suelo = Workspace:Raycast(centro + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), sinPersonajes())
	local impacto = if suelo then suelo.Position else centro - Vector3.new(0, 3, 0)

	-- Martillo: mango claro + cabeza del color del arma con franjas blancas; gira desde arriba
	local bisagra = CFrame.lookAt(origen, origen + plano)
	local piezas: { [Part]: CFrame } = {}
	local function trozo(tam: Vector3, rel: CFrame, color: Color3, forma: Enum.PartType)
		local p = pieza(forma, tam, bisagra * rel, color)
		piezas[p] = rel
	end
	local largo = poder.Alcance + 2
	trozo(Vector3.new(1, 1, largo), CFrame.new(0, 0, -largo / 2), Color3.fromRGB(255, 240, 245), Enum.PartType.Block)
	local cabeza = CFrame.new(0, 0, -largo) * CFrame.Angles(0, 0, math.rad(90))
	trozo(Vector3.new(6, 5, 5), cabeza, poder.Color, Enum.PartType.Cylinder)
	trozo(Vector3.new(1.2, 5.2, 5.2), cabeza * CFrame.new(-1.6, 0, 0), Color3.new(1, 1, 1), Enum.PartType.Cylinder)
	trozo(Vector3.new(1.2, 5.2, 5.2), cabeza * CFrame.new(1.6, 0, 0), Color3.new(1, 1, 1), Enum.PartType.Cylinder)

	local inicio = os.clock()
	local conexion: RBXScriptConnection
	conexion = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - inicio) / poder.Duracion, 0, 1)
		-- de 110° (alzado) a -35° (contra el suelo), acelerando
		local giro = bisagra * CFrame.Angles(math.rad(110 - 145 * t * t), 0, 0)
		for p, rel in piezas do
			p.CFrame = giro * rel
		end
		if t >= 1 then
			conexion:Disconnect()
			reproducirSonido("Martillo", impacto)
			anillo(impacto + Vector3.new(0, 0.3, 0), poder.Radio, poder.Color, 0.5)
			anillo(impacto + Vector3.new(0, 0.3, 0), poder.Radio * 0.6, Color3.new(1, 1, 1), 0.35)
			destello(impacto, poder.Color, 10, 0.3)
			local camara = Workspace.CurrentCamera
			if camara then
				local distancia = (camara.CFrame.Position - impacto).Magnitude
				EfectosController.Sacudir(0.55 * math.clamp(1 - distancia / DISTANCIA_SACUDIDA, 0, 1))
			end
			task.delay(0.25, function()
				for p in piezas do
					p:Destroy()
				end
			end)
		end
	end)
	for p in piezas do
		Debris:AddItem(p, poder.Duracion + 1)
	end
end

-- Monstruos vivos más cercanos (misma regla que el servidor) para las estrellas.
local function monstruosCercanos(origen: Vector3, alcance: number, cantidad: number): { Vector3 }
	local lista = {}
	for _, instancia in CollectionService:GetTagged("Enemigo") do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) then
			local humanoid = instancia:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local centro = instancia:GetPivot().Position
				local medio = instancia:GetExtentsSize().Magnitude / 2
				local distancia = (centro - origen).Magnitude
				if distancia <= alcance + medio then
					table.insert(lista, { posicion = centro, distancia = distancia })
				end
			end
		end
	end
	table.sort(lista, function(a, b)
		return a.distancia < b.distancia
	end)
	local resultado = {}
	for i = 1, math.min(cantidad, #lista) do
		table.insert(resultado, lista[i].posicion)
	end
	return resultado
end

-- Varita de Estrellas: estrellas doradas que salen en curva y caen sobre los monstruos.
local function efectoEstrellas(lanzador: Player, origen: Vector3, poder: PoderConfig)
	local character = lanzador.Character
	if character then
		PoseVueloController.ReproducirGolpe(character, "PunoIzquierdo")
	end
	reproducirSonido("Estrellas", origen)
	local objetivos = monstruosCercanos(origen, poder.Alcance, poder.Cantidad)
	if #objetivos == 0 then
		destello(origen + Vector3.new(0, 3, 0), poder.Color, 5, 0.3) -- no hay a quién: solo la chispa
		return
	end
	for i, destino in objetivos do
		task.delay((i - 1) * 0.08, function()
			local estrella = pieza(Enum.PartType.Ball, Vector3.one * 1.6, CFrame.new(origen), poder.Color)
			local luz = Instance.new("PointLight")
			luz.Color = poder.Color
			luz.Range = 8
			luz.Brightness = 2
			luz.Parent = estrella
			local lateral = Vector3.new(math.random(-12, 12), math.random(6, 12), math.random(-12, 12))
			local control = origen:Lerp(destino, 0.5) + lateral
			local inicio = os.clock()
			local conexion: RBXScriptConnection
			conexion = RunService.Heartbeat:Connect(function()
				local t = math.clamp((os.clock() - inicio) / poder.Duracion, 0, 1)
				-- curva de Bézier: sale hacia un lado y cae sobre el monstruo
				estrella.CFrame = CFrame.new(origen:Lerp(control, t):Lerp(control:Lerp(destino, t), t))
				if t >= 1 then
					conexion:Disconnect()
					estrella:Destroy()
					destello(destino, poder.Color, 7, 0.3)
				end
			end)
			Debris:AddItem(estrella, poder.Duracion + 1)
		end)
	end
end


-- ─── Números de daño flotantes ───────────────────────────────────────────────

local function numeroDano(posicion: Vector3, cantidad: number, color: Color3, grande: boolean, texto: string?)
	local aleatorio = Random.new()
	local ancla = Instance.new("Attachment")
	ancla.Parent = Workspace.Terrain -- el Terrain está en el origen: Position = posición en el mundo
	ancla.Position = posicion + Vector3.new(aleatorio:NextNumber(-2, 2), aleatorio:NextNumber(0, 2), aleatorio:NextNumber(-2, 2))

	local gui = Instance.new("BillboardGui")
	gui.Adornee = ancla
	gui.Size = if grande then UDim2.fromOffset(150, 64) else UDim2.fromOffset(96, 42)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	gui.Parent = ancla

	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.Font = Enum.Font.FredokaOne
	etiqueta.Text = texto or (if grande then `¡{cantidad}!` else tostring(cantidad))
	etiqueta.TextScaled = true
	etiqueta.TextColor3 = color
	etiqueta.Parent = gui
	local trazo = Instance.new("UIStroke")
	trazo.Thickness = 3
	trazo.Color = Color3.fromRGB(30, 10, 50)
	trazo.Parent = etiqueta
	local escala = Instance.new("UIScale")
	escala.Scale = 0.3
	escala.Parent = etiqueta

	-- Aparece con rebote, sube y se desvanece
	animar(escala, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	animar(gui, 0.9, { StudsOffset = Vector3.new(0, 5, 0) })
	local desvanecer = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55)
	TweenService:Create(etiqueta, desvanecer, { TextTransparency = 1 }):Play()
	TweenService:Create(trazo, desvanecer, { Transparency = 1 }):Play()
	Debris:AddItem(ancla, 1)
	-- (el sonido del golpe final es el "¡poof!" de MonstruoDerrotado)
end

-- ─── API pública ─────────────────────────────────────────────────────────────

function EfectosController.Reproducir(lanzador: Player, poder: PoderConfig, objetivo: Vector3)
	local raiz = raizDe(lanzador)
	if not raiz then
		return
	end
	local origen = raiz.Position
	local hacia = objetivo - origen
	local direccion = if hacia.Magnitude > 0.1 then hacia.Unit else raiz.CFrame.LookVector

	if poder.Tipo == "Rayo" then
		efectoRayo(origen, direccion, poder)
	elseif poder.Tipo == "Onda" then
		efectoOnda(origen, poder)
	elseif poder.Tipo == "Rafaga" then
		efectoRafaga(origen, direccion, poder)
	elseif poder.Tipo == "Impulso" then
		efectoImpulso(origen, direccion, poder)
	elseif poder.Tipo == "Escudo" then
		efectoEscudo(origen, poder)
	elseif poder.Tipo == "Pulso" then
		efectoPulso(origen, poder)
	elseif poder.Tipo == "Dulce" then
		efectoDulce(lanzador, origen, direccion, poder)
	elseif poder.Tipo == "Martillo" then
		efectoMartillo(lanzador, origen, direccion, poder)
	elseif poder.Tipo == "Estrellas" then
		efectoEstrellas(lanzador, origen, poder)
	elseif poder.Tipo == "Laser" then
		efectoLaser(lanzador, objetivo, poder)
		return -- la sacudida llega con el disparo, no con la carga
	end

	-- Sacudida de cámara para ataques fuertes, atenuada con la distancia
	local camara = Workspace.CurrentCamera
	local intensidad = SACUDIDA[poder.Tipo] or 0
	if camara and intensidad > 0 then
		local distancia = (camara.CFrame.Position - origen).Magnitude
		EfectosController.Sacudir(intensidad * math.clamp(1 - distancia / DISTANCIA_SACUDIDA, 0, 1))
	end
end

function EfectosController.Sonido(nombre: string, posicion: Vector3?, tono: number?, volumen: number?)
	reproducirSonido(nombre, posicion, tono, volumen)
end

local PALABRAS_GOLPE = { "¡PAM!", "¡ZAS!", "¡POW!" }

-- Impacto de un golpe cuerpo a cuerpo: chispas y estrellitas del color de la heroína, destello
-- y una palabra de cómic. "paso" = 1, 2 o 3 (la patada es más grande).
function EfectosController.ImpactoGolpe(posicion: Vector3, color: Color3, paso: number)
	local fuerte = paso >= 3
	local ancla = Instance.new("Attachment")
	ancla.Parent = Workspace.Terrain
	ancla.Position = posicion

	local chispas = Instance.new("ParticleEmitter")
	chispas.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chispas.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	chispas.LightEmission = 0.6
	chispas.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if fuerte then 1.6 else 1.1), NumberSequenceKeypoint.new(1, 0) })
	chispas.Transparency = NumberSequence.new(0, 1)
	chispas.Lifetime = NumberRange.new(0.25, 0.45)
	chispas.Speed = NumberRange.new(14, if fuerte then 30 else 22)
	chispas.SpreadAngle = Vector2.new(180, 180)
	chispas.Drag = 6
	chispas.Rate = 0
	chispas.Parent = ancla
	chispas:Emit(if fuerte then 28 else 16)

	-- Estrellitas que giran y caen (de dibujo animado)
	local estrellas = Instance.new("ParticleEmitter")
	estrellas.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	estrellas.Color = ColorSequence.new(Color3.fromRGB(255, 235, 120))
	estrellas.LightEmission = 0.3
	estrellas.Size = NumberSequence.new(0.7, 0)
	estrellas.Lifetime = NumberRange.new(0.5, 0.8)
	estrellas.Speed = NumberRange.new(8, 14)
	estrellas.SpreadAngle = Vector2.new(70, 70)
	estrellas.EmissionDirection = Enum.NormalId.Top
	estrellas.Acceleration = Vector3.new(0, -40, 0)
	estrellas.RotSpeed = NumberRange.new(-360, 360)
	estrellas.Rate = 0
	estrellas.Parent = ancla
	estrellas:Emit(if fuerte then 8 else 4)

	destello(posicion, color, if fuerte then 7 else 4.5, 0.18)
	destello(posicion, Color3.new(1, 1, 1), if fuerte then 3.5 else 2.2, 0.1)

	-- Palabra de cómic
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if fuerte then 150 else 110, if fuerte then 70 else 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = ancla
	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.Font = Enum.Font.FredokaOne
	etiqueta.Text = PALABRAS_GOLPE[math.clamp(paso, 1, #PALABRAS_GOLPE)]
	etiqueta.TextScaled = true
	etiqueta.TextColor3 = Color3.fromRGB(255, 240, 90)
	etiqueta.Rotation = aleatorioSonido:NextNumber(-14, 14)
	etiqueta.Parent = gui
	local trazo = Instance.new("UIStroke")
	trazo.Thickness = 3
	trazo.Color = color:Lerp(Color3.new(0, 0, 0), 0.5)
	trazo.Parent = etiqueta
	local escala = Instance.new("UIScale")
	escala.Scale = 0.4
	escala.Parent = etiqueta
	animar(escala, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	local desvanecer = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25)
	TweenService:Create(etiqueta, desvanecer, { TextTransparency = 1 }):Play()
	TweenService:Create(trazo, desvanecer, { Transparency = 1 }):Play()

	Debris:AddItem(ancla, 1)
end

-- Parpadeo blanco del monstruo golpeado: tiñe su Highlight de contorno (no se crea otro:
-- Roblox dibuja como máximo 31 a la vez) y luego vuelve a como estaba (p. ej. verde si está ralentizado).
local parpadeos: { [Highlight]: { color: Color3, transparencia: number, id: number } } = {}
function EfectosController.ParpadeoBlanco(modelo: Model)
	local resaltado = modelo:FindFirstChildOfClass("Highlight")
	if not resaltado then
		return
	end
	local previo = parpadeos[resaltado]
	local id = if previo then previo.id + 1 else 1
	parpadeos[resaltado] = {
		color = if previo then previo.color else resaltado.FillColor,
		transparencia = if previo then previo.transparencia else resaltado.FillTransparency,
		id = id,
	}
	resaltado.FillColor = Color3.new(1, 1, 1)
	resaltado.FillTransparency = 0.15
	task.delay(0.09, function()
		local datos = parpadeos[resaltado]
		if not datos or datos.id ~= id then
			return -- llegó otro golpe: lo restaura el último
		end
		parpadeos[resaltado] = nil
		if resaltado.Parent then
			resaltado.FillColor = datos.color
			resaltado.FillTransparency = datos.transparencia
		end
	end)
end

-- ─── Monstruo derrotado ──────────────────────────────────────────────────────

local COLORES_HUMO = {
	Color3.fromRGB(255, 150, 210),
	Color3.fromRGB(150, 220, 255),
	Color3.fromRGB(190, 255, 170),
	Color3.fromRGB(255, 235, 140),
	Color3.fromRGB(215, 175, 255),
}
local COLOR_MONEDA = Color3.fromRGB(255, 205, 50)
local COLOR_CURACION = Color3.fromRGB(90, 255, 120)

-- Monedas que saltan del monstruo y vuelan hasta la heroína que lo derrotó.
local function monedasVolando(desde: Vector3, destino: Player, cantidad: number)
	local aleatorio = Random.new()
	for i = 1, math.clamp(cantidad, 1, 8) do
		task.delay((i - 1) * 0.05, function()
			local moneda = Instance.new("Part")
			moneda.Shape = Enum.PartType.Cylinder
			moneda.Size = Vector3.new(0.35, 1.6, 1.6)
			moneda.Color = COLOR_MONEDA
			moneda.Material = Enum.Material.Metal
			moneda.Reflectance = 0.3
			moneda.Anchored = true
			moneda.CanCollide = false
			moneda.CanQuery = false
			moneda.CanTouch = false
			moneda.CastShadow = false
			moneda.CFrame = CFrame.new(desde)
			moneda.Parent = carpeta
			-- Fase 1: salta hacia fuera; fase 2: vuela a la heroína (que puede estar moviéndose)
			local salto = desde + Vector3.new(aleatorio:NextNumber(-7, 7), aleatorio:NextNumber(5, 10), aleatorio:NextNumber(-7, 7))
			local inicio = os.clock()
			local conexion: RBXScriptConnection
			conexion = RunService.RenderStepped:Connect(function()
				local t = os.clock() - inicio
				local giro = CFrame.Angles(0, t * 12, math.rad(90))
				if t < 0.35 then
					moneda.CFrame = CFrame.new(desde:Lerp(salto, 1 - (1 - t / 0.35) ^ 2)) * giro
					return
				end
				local raiz = raizDe(destino)
				local u = math.clamp((t - 0.35) / 0.45, 0, 1)
				if not raiz or u >= 1 then
					conexion:Disconnect()
					moneda:Destroy()
					if raiz and destino == jugadorLocal then
						reproducirSonido("Moneda", nil, 1 + i * 0.04)
					end
					return
				end
				moneda.CFrame = CFrame.new(salto:Lerp(raiz.Position, u * u)) * giro
			end)
			Debris:AddItem(moneda, 2)
		end)
	end
end

function EfectosController.MonstruoDerrotado(posicion: Vector3, color: Color3, tamano: number, asesino: Player?, monedas: number)
	local escala = math.clamp(tamano / 20, 0.8, 3)
	-- Humo de colores: bolas que se hinchan y se desvanecen
	local aleatorio = Random.new()
	for i = 1, 9 do
		local tono = COLORES_HUMO[(i - 1) % #COLORES_HUMO + 1]:Lerp(color, 0.25)
		local desplazamiento = Vector3.new(aleatorio:NextNumber(-1, 1), aleatorio:NextNumber(-0.6, 1), aleatorio:NextNumber(-1, 1)) * 5 * escala
		local bola = parteEfecto(Enum.PartType.Ball, Vector3.one * 3 * escala, CFrame.new(posicion + desplazamiento), tono)
		bola.Material = Enum.Material.SmoothPlastic
		bola.Transparency = 0.35
		local duracion = aleatorio:NextNumber(0.55, 0.85)
		animar(bola, duracion, {
			Size = Vector3.one * aleatorio:NextNumber(8, 12) * escala,
			Transparency = 1,
			CFrame = CFrame.new(posicion + desplazamiento * 1.8 + Vector3.new(0, 3 * escala, 0)),
		})
		Debris:AddItem(bola, duracion + 0.05)
	end
	destello(posicion, Color3.new(1, 1, 1), 14 * escala, 0.25)

	-- Estrellas que salen disparadas
	local ancla = Instance.new("Attachment")
	ancla.Parent = Workspace.Terrain
	ancla.Position = posicion
	local estrellas = Instance.new("ParticleEmitter")
	estrellas.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	estrellas.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 160, 220))
	estrellas.LightEmission = 0.5
	estrellas.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2 * escala), NumberSequenceKeypoint.new(1, 0) })
	estrellas.Lifetime = NumberRange.new(0.6, 1.1)
	estrellas.Speed = NumberRange.new(20 * escala, 40 * escala)
	estrellas.SpreadAngle = Vector2.new(180, 180)
	estrellas.Drag = 3
	estrellas.RotSpeed = NumberRange.new(-300, 300)
	estrellas.Rate = 0
	estrellas.Parent = ancla
	estrellas:Emit(30)

	-- Texto "¡DERROTADO!"
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4 * escala, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = ancla
	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.Font = Enum.Font.FredokaOne
	etiqueta.Text = "¡DERROTADO!"
	etiqueta.TextScaled = true
	etiqueta.TextColor3 = Color3.fromRGB(255, 240, 90)
	etiqueta.Parent = gui
	local trazo = Instance.new("UIStroke")
	trazo.Thickness = 4
	trazo.Color = Color3.fromRGB(120, 20, 90)
	trazo.Parent = etiqueta
	local escalaTexto = Instance.new("UIScale")
	escalaTexto.Scale = 0.3
	escalaTexto.Parent = etiqueta
	animar(escalaTexto, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	animar(gui, 1.4, { StudsOffsetWorldSpace = Vector3.new(0, 7 * escala, 0) })
	local desvanecer = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1)
	TweenService:Create(etiqueta, desvanecer, { TextTransparency = 1 }):Play()
	TweenService:Create(trazo, desvanecer, { Transparency = 1 }):Play()
	Debris:AddItem(ancla, 1.6)

	reproducirSonido("Poof", posicion)
	if asesino and monedas > 0 then
		monedasVolando(posicion, asesino, monedas)
	end
	-- Sacudida si está cerca de la cámara
	local camara = Workspace.CurrentCamera
	if camara then
		local distancia = (camara.CFrame.Position - posicion).Magnitude
		EfectosController.Sacudir(0.35 * math.clamp(1 - distancia / 140, 0, 1))
	end
end

function EfectosController.Sacudir(intensidad: number)
	trauma = math.min(1, trauma + intensidad)
end

-- Bucle de viento mientras la heroína local vuela. intensidad 0..1 (según velocidad).
function EfectosController.SonidoVuelo(activo: boolean, intensidad: number)
	if not activo then
		if sonidoViento then
			sonidoViento:Stop()
		end
		return
	end
	local config = Sonidos.Viento
	local sonido = sonidoViento
	if sonido == nil then
		local nuevo = Instance.new("Sound")
		nuevo.Name = "VientoVuelo"
		nuevo.SoundId = config.Id
		nuevo.Looped = true
		nuevo.Volume = 0
		nuevo.Parent = SoundService
		sonidoViento = nuevo
		sonido = nuevo
	end
	if sonido then
		sonido.Volume = config.Volumen * (0.25 + 0.75 * intensidad)
		sonido.PlaybackSpeed = config.Tono * (0.8 + 0.6 * intensidad)
		if not sonido.IsPlaying then
			sonido:Play()
		end
	end
end

function EfectosController.SonidoBoton()
	reproducirSonido("Boton")
end

function EfectosController.Init()
	carpeta = Instance.new("Folder")
	carpeta.Name = "EfectosLocales"
	carpeta.Parent = Workspace

	Remotes.Evento("EfectoPoder").OnClientEvent:Connect(function(lanzador: unknown, poderId: unknown, objetivo: unknown)
		if typeof(lanzador) ~= "Instance" or not (lanzador :: Instance):IsA("Player") then
			return
		end
		if lanzador == jugadorLocal then
			return -- la jugadora local ya vio su efecto al instante
		end
		local poder = Poderes.PorId(poderId)
		if poder and typeof(objetivo) == "Vector3" then
			EfectosController.Reproducir(lanzador :: Player, poder, objetivo :: Vector3)
		end
	end)

	-- Fanfarria procedural para anuncios (oleada, nivel, derrota)
	Remotes.Evento("Anuncio").OnClientEvent:Connect(function(titulo: unknown)
		local esDerrota = typeof(titulo) == "string" and string.find(titulo :: string, "CAÍDO", 1, true) ~= nil
		fanfarria(if esDerrota then FANFARRIA_BAJA else FANFARRIA_SUBE, if esDerrota then 0.22 else 0.11)
	end)

	RunService:BindToRenderStep("SacudidaCamara", Enum.RenderPriority.Camera.Value + 1, aplicarSacudida)

	-- Regeneración: "+N" verde sobre la cabeza y un brillo verde suave en el contorno de la heroína
	Remotes.Evento("Curacion").OnClientEvent:Connect(function(character: unknown, cantidad: unknown)
		if typeof(character) ~= "Instance" or not (character :: Instance):IsA("Model") or typeof(cantidad) ~= "number" then
			return
		end
		local modelo = character :: Model
		local cabeza = modelo:FindFirstChild("Head")
		if cabeza and cabeza:IsA("BasePart") then
			numeroDano(cabeza.Position + Vector3.new(0, 1.5, 0), cantidad :: number, COLOR_CURACION, false, `+{cantidad}`)
		end
		local contorno = modelo:FindFirstChild("ContornoHeroina")
		if contorno and contorno:IsA("Highlight") and contorno.FillTransparency >= 0.99 then
			contorno.FillColor = COLOR_CURACION
			contorno.FillTransparency = 0.8
			animar(contorno, 0.6, { FillTransparency = 1 })
		end
	end)

	Remotes.Evento("MonstruoDerrotado").OnClientEvent:Connect(
		function(posicion: unknown, color: unknown, tamano: unknown, asesino: unknown, monedas: unknown)
			if typeof(posicion) ~= "Vector3" then
				return
			end
			local quien: Player? = if typeof(asesino) == "Instance" and (asesino :: Instance):IsA("Player") then asesino :: Player else nil
			EfectosController.MonstruoDerrotado(
				posicion :: Vector3,
				if typeof(color) == "Color3" then color :: Color3 else Color3.new(1, 1, 1),
				if typeof(tamano) == "number" then tamano :: number else 20,
				quien,
				if typeof(monedas) == "number" then monedas :: number else 0
			)
		end
	)

	Remotes.Evento("NumeroDano").OnClientEvent:Connect(function(posicion: unknown, cantidad: unknown, color: unknown, grande: unknown)
		if typeof(posicion) == "Vector3" and typeof(cantidad) == "number" then
			numeroDano(
				posicion :: Vector3,
				cantidad :: number,
				if typeof(color) == "Color3" then color :: Color3 else Color3.new(1, 1, 1),
				grande == true
			)
		end
	end)
end

return EfectosController
