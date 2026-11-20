--!strict
-- HeroinaService: asigna el arquetipo de cada jugador y crea su estela de vuelo.
-- El arquetipo se guarda en el atributo del jugador "Arquetipo" (replicado a los clientes).
-- El estado de vuelo se guarda en el atributo del personaje "Volando".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Heroinas = require(Shared.Config.Heroinas)
local Juego = require(Shared.Config.Juego)
local Poderes = require(Shared.Config.Poderes)
local Remotes = require(Shared.Remotes)
local TiendaRobux = require(Shared.Config.TiendaRobux)
local Types = require(Shared.Types)

local ATRIBUTO_ARQUETIPO = "Arquetipo"
local ATRIBUTO_VOLANDO = "Volando"
local ATRIBUTO_MONEDAS = "Monedas"
local ATRIBUTO_NIVEL = "Nivel"
local ATRIBUTO_EXPERIENCIA = "Experiencia" -- XP dentro del nivel actual
local ATRIBUTO_DERROTADOS = "Derrotados"
local ATRIBUTO_CORRIENDO = "Corriendo"
local ATRIBUTO_EN_CIUDAD = "EnCiudad"
local ATRIBUTO_ELEGIDA = "HeroinaElegida" -- eligió heroína en esta sesión
local NOMBRE_CONTORNO = "ContornoHeroina"
local NOMBRE_NUCLEO = "EstelaNucleo"
local NOMBRE_AURA = "AuraVIP"
local MULTIPLICADOR_VIP = 1.5
local ENFRIAMIENTO_CAMBIO = 2 -- segundos mínimos entre cambios de heroína

local ultimoCambio: { [Player]: number } = {}
-- Amistades entre jugadoras del servidor (IsFriendsWith es una llamada web: se consulta una vez y se cachea)
local amigos: { [Player]: { [Player]: boolean } } = {}
-- Conexiones por jugador / por personaje actual: se desconectan al salir o reaparecer (sin fugas).
local conexionesJugador: { [Player]: { RBXScriptConnection } } = {}
local conexionesPersonaje: { [Player]: { RBXScriptConnection } } = {}
-- Avatar de cada jugadora: descripción original del personaje actual y qué traje lleva aplicado
-- ("Original" o el id del arquetipo).
type RegistroCuerpo = {
	personaje: Model,
	original: HumanoidDescription,
	aplicada: string,
}
local cuerpos: { [Player]: RegistroCuerpo } = {}
-- Cada transformación incrementa la versión; si llega otra mientras se espera, la anterior se cancela.
local versionTransformacion: { [Player]: number } = {}
-- Retrato de la tarjeta del HUD: modelo de la heroína (cara del jugador + traje de su clase) en
-- ReplicatedStorage.Retratos.<UserId>. Se regenera solo al cambiar de clase.
local carpetaRetratos: Folder
local retratoClase: { [Player]: string } = {}
local versionRetrato: { [Player]: number } = {}
-- Regeneración propia: momento (os.clock) del último daño recibido por cada jugadora.
local ultimoDano: { [Player]: number } = {}
local eventoCuracion: RemoteEvent

local function desconectar(lista: { RBXScriptConnection }?)
	if lista then
		for _, conexion in lista do
			conexion:Disconnect()
		end
		table.clear(lista)
	end
end
local NOMBRE_ESTELA = "EstelaHeroina"
local NOMBRE_ATT_SUPERIOR = "EstelaSuperior"
local NOMBRE_ATT_INFERIOR = "EstelaInferior"

local HeroinaService = {}

local function obtenerTorso(character: Model): BasePart?
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return nil
	end
	local nombreTorso = if humanoid.RigType == Enum.HumanoidRigType.R15 then "UpperTorso" else "Torso"
	local torso = character:WaitForChild(nombreTorso, 10)
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return nil
end

-- Ajusta la vida máxima al arquetipo conservando el porcentaje de vida actual
-- (cambiar de heroína no sirve para curarse).
local function aplicarEstadisticas(character: Model, config: Types.HeroinaConfig)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local proporcion = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = config.VidaMaxima
	humanoid.Health = config.VidaMaxima * math.clamp(proporcion, 0, 1)
end

local function crearTrail(nombre: string, a0: Attachment, a1: Attachment, color: ColorSequence, vida: number): Trail
	local trail = Instance.new("Trail")
	trail.Name = nombre
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = color
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.55)
	trail.LightEmission = 0.5
	trail.LightInfluence = 0.3
	trail.FaceCamera = true
	trail.Lifetime = vida
	trail.MinLength = 0.05
	return trail
end

-- Estela ancha y sólida: los Attachment van a los lados (eje X del torso), así cubre todo el ancho
-- del cuerpo tanto de pie como volando en horizontal. Un núcleo blanco más fino la hace brillar.
local function crearEstela(character: Model, config: Types.HeroinaConfig)
	local torso = obtenerTorso(character)
	if not torso then
		warn(`[HeroinaService] No se encontró el torso de {character.Name}; no se crea la estela`)
		return
	end

	for _, nombre in { NOMBRE_ESTELA, NOMBRE_NUCLEO, NOMBRE_ATT_SUPERIOR, NOMBRE_ATT_INFERIOR, "NucleoA", "NucleoB" } do
		local anterior = torso:FindFirstChild(nombre)
		if anterior then
			anterior:Destroy()
		end
	end

	local mitad = config.Estela.Ancho / 2
	local espalda = torso.Size.Z / 2 + 0.1 -- +Z local = espalda
	local function adjunto(nombre: string, x: number): Attachment
		local a = Instance.new("Attachment")
		a.Name = nombre
		a.Position = Vector3.new(x, 0, espalda)
		a.Parent = torso
		return a
	end

	local activa = character:GetAttribute(ATRIBUTO_VOLANDO) == true or character:GetAttribute(ATRIBUTO_CORRIENDO) == true
	local principal = crearTrail(
		NOMBRE_ESTELA,
		adjunto(NOMBRE_ATT_SUPERIOR, -mitad),
		adjunto(NOMBRE_ATT_INFERIOR, mitad),
		ColorSequence.new(config.Estela.ColorInicio, config.Estela.ColorFin),
		config.Estela.Duracion
	)
	principal.Enabled = activa
	principal.Parent = torso

	local nucleo = crearTrail(
		NOMBRE_NUCLEO,
		adjunto("NucleoA", -mitad * 0.35),
		adjunto("NucleoB", mitad * 0.35),
		ColorSequence.new(Color3.new(1, 1, 1)),
		config.Estela.Duracion * 0.5
	)
	nucleo.Enabled = activa
	nucleo.Parent = torso
end

local DORADO = Color3.fromRGB(255, 215, 70)

-- ─── Traje de heroína (catálogo de avatares + HumanoidDescription) ───────────
-- La jugadora lleva el traje en la ciudad (atributo EnCiudad). En el lobby vuelve a su avatar
-- original, y al morir o reaparecer Roblox carga de nuevo su avatar real (si reaparece en la
-- ciudad, se vuelve a transformar). Los ids están en Config/Heroinas.luau → Atuendo.Catalogo.

type Pieza = {
	AccessoryType: Enum.AccessoryType,
	AssetId: number,
	IsLayered: boolean,
	Order: number?,
}

-- Ropa en capas: campo del catálogo, tipo y orden (de dentro hacia fuera).
local CAPAS: { { campo: string, tipo: Enum.AccessoryType, orden: number } } = {
	{ campo = "BotaIzquierda", tipo = Enum.AccessoryType.LeftShoe, orden = 1 },
	{ campo = "BotaDerecha", tipo = Enum.AccessoryType.RightShoe, orden = 1 },
	{ campo = "Body", tipo = Enum.AccessoryType.TShirt, orden = 3 },
	{ campo = "Guantes", tipo = Enum.AccessoryType.Jacket, orden = 7 },
}

-- Accesorios del avatar que forman parte de la cara (cabezas dinámicas): se conservan.
local PARTES_CARA: { [Enum.AccessoryType]: boolean } = {
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

-- Artículos que fallaron al cargar en este servidor: se omiten en las transformaciones siguientes.
local articulosFallidos: { [number]: boolean } = {}

local function piezasTraje(catalogo: Types.CatalogoAtuendo): { Pieza }
	local piezas: { Pieza } = {}
	local function agregar(id: number, tipo: Enum.AccessoryType, orden: number?)
		if id > 0 and not articulosFallidos[id] then
			table.insert(piezas, { AccessoryType = tipo, AssetId = id, IsLayered = orden ~= nil, Order = orden })
		end
	end
	agregar(catalogo.Pelo, Enum.AccessoryType.Hair, nil)
	agregar(catalogo.Accesorio, Enum.AccessoryType.Hat, nil)
	for _, capa in CAPAS do
		local id = (catalogo :: any)[capa.campo]
		if typeof(id) == "number" then
			agregar(id, capa.tipo, capa.orden)
		end
	end
	return piezas
end

-- Descripción de heroína: conserva cabeza, cara, tono de piel y animaciones del jugador; quita su
-- ropa y accesorios y pone el cuerpo estándar (si conCuerpo) y las piezas del catálogo.
local function descripcionHeroina(
	original: HumanoidDescription,
	catalogo: Types.CatalogoAtuendo,
	piezas: { Pieza },
	conCuerpo: boolean
): HumanoidDescription
	local descripcion = original:Clone()
	descripcion.Shirt = 0
	descripcion.Pants = 0
	descripcion.GraphicTShirt = 0
	if conCuerpo then
		local cuerpo = catalogo.Cuerpo
		descripcion.Torso = cuerpo.Torso
		descripcion.LeftArm = cuerpo.BrazoIzquierdo
		descripcion.RightArm = cuerpo.BrazoDerecho
		descripcion.LeftLeg = cuerpo.PiernaIzquierda
		descripcion.RightLeg = cuerpo.PiernaDerecha
		-- Escalas estándar del editor de avatares: el traje se ve igual con cualquier avatar.
		descripcion.BodyTypeScale = 0
		descripcion.ProportionScale = 0
		descripcion.HeightScale = 1
		descripcion.WidthScale = 1
		descripcion.DepthScale = 1
		descripcion.HeadScale = 1
	end
	-- Sustituye todos los accesorios (rígidos y en capas) salvo los que forman parte de la cara.
	local accesorios = table.clone(piezas)
	for _, accesorio in original:GetAccessories(true) do
		if PARTES_CARA[accesorio.AccessoryType] then
			table.insert(accesorios, accesorio)
		end
	end
	descripcion:SetAccessories(accesorios, true)
	return descripcion
end

local function aplicarDescripcion(humanoid: Humanoid, descripcion: HumanoidDescription): (boolean, string?)
	local ok, err = pcall(humanoid.ApplyDescription, humanoid, descripcion)
	return ok, if ok then nil else tostring(err)
end

-- Si la descripción completa falla, se prueba pieza a pieza y se descartan las que no cargan,
-- para que la transformación siga con el resto. Devuelve false si se canceló.
local function aplicarPorPiezas(
	jugador: Player,
	humanoid: Humanoid,
	registro: RegistroCuerpo,
	catalogo: Types.CatalogoAtuendo,
	vigente: () -> boolean
): boolean
	local conCuerpo = aplicarDescripcion(humanoid, descripcionHeroina(registro.original, catalogo, {}, true))
	if not vigente() then
		return false
	end
	if not conCuerpo then
		warn(`[HeroinaService] El cuerpo del traje no cargó para {jugador.Name}; se usa su cuerpo`)
	end
	local aceptadas: { Pieza } = {}
	for _, pieza in piezasTraje(catalogo) do
		table.insert(aceptadas, pieza)
		local ok, err = aplicarDescripcion(humanoid, descripcionHeroina(registro.original, catalogo, aceptadas, conCuerpo))
		if not vigente() then
			return false
		end
		if not ok then
			table.remove(aceptadas)
			articulosFallidos[pieza.AssetId] = true
			warn(`[HeroinaService] El artículo {pieza.AssetId} ({pieza.AccessoryType.Name}) no cargó y se omite: {err}`)
		end
	end
	return true
end

-- Pone el traje del arquetipo (conTraje) o restaura el avatar original. Cede (ApplyDescription).
local function aplicarTraje(
	jugador: Player,
	character: Model,
	config: Types.HeroinaConfig,
	conTraje: boolean,
	vigente: () -> boolean
)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 or humanoid.Health <= 0 then
		return
	end
	local registro = cuerpos[jugador]
	if not registro or registro.personaje ~= character then
		-- Personaje recién aparecido: lleva el avatar real del jugador.
		local ok, original = pcall(humanoid.GetAppliedDescription, humanoid)
		if not ok then
			warn(`[HeroinaService] No se pudo leer el avatar de {jugador.Name}: {original}`)
			return
		end
		registro = { personaje = character, original = original, aplicada = "Original" }
		cuerpos[jugador] = registro
	end
	local deseada: string = if conTraje then config.Id else "Original"
	if registro.aplicada == deseada then
		return
	end
	-- ApplyDescription exige que el personaje esté en Workspace
	local limite = os.clock() + 5
	while not character:IsDescendantOf(workspace) do
		if os.clock() > limite or not vigente() then
			return
		end
		task.wait()
	end

	if not conTraje then
		local ok, err = aplicarDescripcion(humanoid, registro.original)
		if not vigente() then
			return
		end
		if ok then
			registro.aplicada = deseada
		else
			warn(`[HeroinaService] No se pudo restaurar el avatar de {jugador.Name}: {err}`)
		end
		return
	end

	local catalogo = config.Atuendo.Catalogo
	local ok, err = aplicarDescripcion(humanoid, descripcionHeroina(registro.original, catalogo, piezasTraje(catalogo), true))
	if not vigente() then
		return
	end
	if not ok then
		warn(`[HeroinaService] El traje de {config.Id} falló para {jugador.Name} ({err}); se aplica pieza a pieza`)
		if not aplicarPorPiezas(jugador, humanoid, registro, catalogo, vigente) then
			return
		end
	end
	registro.aplicada = deseada
end

local function contornoCaricatura(character: Model)
	if character:FindFirstChild(NOMBRE_CONTORNO) then
		return
	end
	local contorno = Instance.new("Highlight")
	contorno.Name = NOMBRE_CONTORNO
	contorno.FillTransparency = 1
	contorno.OutlineColor = Color3.new(0, 0, 0)
	contorno.OutlineTransparency = 0.15
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Parent = character
end

local function actualizarAuraVIP(jugador: Player, character: Model)
	local torso = obtenerTorso(character)
	if not torso then
		return
	end
	local aura = torso:FindFirstChild(NOMBRE_AURA)
	if TiendaRobux.TienePase(jugador, "HeroinaVIP") then
		if not aura then
			local particulas = Instance.new("ParticleEmitter")
			particulas.Name = NOMBRE_AURA
			particulas.Color = ColorSequence.new(DORADO, Color3.fromRGB(255, 250, 200))
			particulas.LightEmission = 1
			particulas.Rate = 14
			particulas.Lifetime = NumberRange.new(0.6, 1.1)
			particulas.Speed = NumberRange.new(1, 3)
			particulas.SpreadAngle = Vector2.new(180, 180)
			particulas.Size = NumberSequence.new(0.35, 0)
			particulas.Parent = torso
		end
	elseif aura then
		aura:Destroy()
	end
end

-- Crea el modelo del retrato con la descripción de heroína (cede: carga los artículos).
local function generarRetrato(jugador: Player, config: Types.HeroinaConfig)
	local registro = cuerpos[jugador]
	if not registro or retratoClase[jugador] == config.Id then
		return
	end
	retratoClase[jugador] = config.Id
	local version = (versionRetrato[jugador] or 0) + 1
	versionRetrato[jugador] = version
	local catalogo = config.Atuendo.Catalogo
	local ok, modelo = pcall(
		Players.CreateHumanoidModelFromDescription,
		Players,
		descripcionHeroina(registro.original, catalogo, piezasTraje(catalogo), true),
		Enum.HumanoidRigType.R15
	)
	if not ok then
		-- Sin las piezas que fallen: al menos la cara con el cuerpo del traje
		ok, modelo = pcall(Players.CreateHumanoidModelFromDescription, Players, descripcionHeroina(registro.original, catalogo, {}, true), Enum.HumanoidRigType.R15)
	end
	if not ok or typeof(modelo) ~= "Instance" or not modelo:IsA("Model") then
		retratoClase[jugador] = nil
		warn(`[HeroinaService] No se pudo crear el retrato de {jugador.Name}: {modelo}`)
		return
	end
	if versionRetrato[jugador] ~= version or jugador.Parent == nil then
		modelo:Destroy()
		return
	end
	for _, d in modelo:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	modelo.Name = tostring(jugador.UserId)
	modelo:SetAttribute("Arquetipo", config.Id)
	local anterior = carpetaRetratos:FindFirstChild(modelo.Name)
	if anterior then
		anterior:Destroy()
	end
	modelo.Parent = carpetaRetratos
end

-- Transformación completa: traje (solo en la ciudad), estadísticas, contorno, estela y aura.
-- Cede (ApplyDescription): si llega otra transformación o reaparece mientras tanto, esta se abandona.
-- La estela y el aura se recrean siempre: ApplyDescription puede sustituir el torso.
local function transformar(jugador: Player, character: Model, config: Types.HeroinaConfig)
	local version = (versionTransformacion[jugador] or 0) + 1
	versionTransformacion[jugador] = version
	local function vigente(): boolean
		return versionTransformacion[jugador] == version and jugador.Character == character
	end
	-- Traje de heroína en la ciudad y también en el lobby en cuanto la elige; antes, su avatar
	local conTraje = jugador:GetAttribute(ATRIBUTO_EN_CIUDAD) == true or jugador:GetAttribute(ATRIBUTO_ELEGIDA) == true
	aplicarTraje(jugador, character, config, conTraje, vigente)
	task.spawn(generarRetrato, jugador, config)
	if not vigente() then
		return
	end
	aplicarEstadisticas(character, config)
	contornoCaricatura(character)
	crearEstela(character, config)
	actualizarAuraVIP(jugador, character)
end

local function actualizarEstela(character: Model)
	local activa = character:GetAttribute(ATRIBUTO_VOLANDO) == true or character:GetAttribute(ATRIBUTO_CORRIENDO) == true
	for _, d in character:GetDescendants() do
		if d:IsA("Trail") and (d.Name == NOMBRE_ESTELA or d.Name == NOMBRE_NUCLEO) then
			d.Enabled = activa
		end
	end
end

local function establecerVuelo(character: Model, volando: boolean)
	character:SetAttribute(ATRIBUTO_VOLANDO, volando)
	actualizarEstela(character)
end

local function establecerCarrera(character: Model, corriendo: boolean)
	character:SetAttribute(ATRIBUTO_CORRIENDO, corriendo)
	actualizarEstela(character)
end

local function alAparecerPersonaje(jugador: Player, character: Model)
	character:SetAttribute(ATRIBUTO_VOLANDO, false)
	character:SetAttribute(ATRIBUTO_CORRIENDO, false)

	local lista = conexionesPersonaje[jugador]
	if not lista then
		lista = {}
		conexionesPersonaje[jugador] = lista
	end
	desconectar(lista)

	-- Sin la regeneración por defecto de Roblox (script "Health" del personaje): se usa la propia.
	local function quitarRegeneracionRoblox(hijo: Instance)
		if hijo.Name == "Health" and hijo:IsA("Script") then
			hijo:Destroy()
		end
	end
	for _, hijo in character:GetChildren() do
		quitarRegeneracionRoblox(hijo)
	end
	table.insert(lista, character.ChildAdded:Connect(quitarRegeneracionRoblox))

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(lista, humanoid.Died:Connect(function()
			establecerVuelo(character, false)
			establecerCarrera(character, false)
		end))
		local vidaPrevia = humanoid.Health
		table.insert(lista, humanoid.HealthChanged:Connect(function(vida: number)
			if vida < vidaPrevia then
				ultimoDano[jugador] = os.clock()
			end
			vidaPrevia = vida
		end))
	end
	ultimoDano[jugador] = os.clock()

	transformar(jugador, character, Heroinas.Obtener(jugador:GetAttribute(ATRIBUTO_ARQUETIPO)))
end

local function alEntrarJugador(jugador: Player)
	if not Heroinas.EsValido(jugador:GetAttribute(ATRIBUTO_ARQUETIPO)) then
		jugador:SetAttribute(ATRIBUTO_ARQUETIPO, Heroinas.PorDefecto)
	end
	for _, atributo in { ATRIBUTO_MONEDAS, ATRIBUTO_EXPERIENCIA, ATRIBUTO_DERROTADOS, "Energia" } do
		if typeof(jugador:GetAttribute(atributo)) ~= "number" then
			jugador:SetAttribute(atributo, 0)
		end
	end
	if typeof(jugador:GetAttribute(ATRIBUTO_NIVEL)) ~= "number" then
		jugador:SetAttribute(ATRIBUTO_NIVEL, 1)
	end

	local conexiones: { RBXScriptConnection } = {}
	conexionesJugador[jugador] = conexiones

	-- Al cambiar de arquetipo o al entrar/salir de la ciudad se rehace la transformación
	-- (traje en la ciudad, avatar original en el lobby).
	local function retransformar()
		local character = jugador.Character
		if character then
			transformar(jugador, character, Heroinas.Obtener(jugador:GetAttribute(ATRIBUTO_ARQUETIPO)))
		end
	end
	table.insert(conexiones, jugador:GetAttributeChangedSignal(ATRIBUTO_ARQUETIPO):Connect(retransformar))
	table.insert(conexiones, jugador:GetAttributeChangedSignal(ATRIBUTO_EN_CIUDAD):Connect(retransformar))
	-- Al elegir heroína por primera vez (aunque sea la misma clase guardada): ponerle el traje ya
	table.insert(conexiones, jugador:GetAttributeChangedSignal(ATRIBUTO_ELEGIDA):Connect(retransformar))
	-- Si entra en la ciudad sin elegir, juega con su clase guardada: cuenta como elegida
	table.insert(conexiones, jugador:GetAttributeChangedSignal(ATRIBUTO_EN_CIUDAD):Connect(function()
		if jugador:GetAttribute(ATRIBUTO_EN_CIUDAD) == true then
			jugador:SetAttribute(ATRIBUTO_ELEGIDA, true)
		end
	end))

	-- Aura dorada al obtener el pase VIP
	table.insert(conexiones, jugador:GetAttributeChangedSignal(TiendaRobux.AtributoPase("HeroinaVIP")):Connect(function()
		if jugador.Character then
			actualizarAuraVIP(jugador, jugador.Character)
		end
	end))

	table.insert(conexiones, jugador.CharacterAdded:Connect(function(character)
		alAparecerPersonaje(jugador, character)
	end))
	if jugador.Character then
		task.spawn(alAparecerPersonaje, jugador, jugador.Character)
	end
end

-- API pública: cambia el arquetipo de un jugador (validado en el servidor).
function HeroinaService.AsignarArquetipo(jugador: Player, id: unknown): boolean
	if not Heroinas.EsValido(id) then
		return false
	end
	-- Elegida EN ESTA SESIÓN (no se guarda): hasta entonces la tarjeta del HUD pide elegir.
	-- Se marca ANTES del arquetipo para que la transformación ya ponga el traje.
	jugador:SetAttribute(ATRIBUTO_ELEGIDA, true)
	jugador:SetAttribute(ATRIBUTO_ARQUETIPO, id)
	return true
end

function HeroinaService.ObtenerArquetipo(jugador: Player): Types.HeroinaConfig
	return Heroinas.Obtener(jugador:GetAttribute(ATRIBUTO_ARQUETIPO))
end

function HeroinaService.ObtenerMonedas(jugador: Player): number
	local monedas = jugador:GetAttribute(ATRIBUTO_MONEDAS)
	return if typeof(monedas) == "number" then monedas else 0
end

function HeroinaService.SumarMonedas(jugador: Player, cantidad: number)
	jugador:SetAttribute(ATRIBUTO_MONEDAS, HeroinaService.ObtenerMonedas(jugador) + cantidad)
end

-- Multiplicador de monedas GANADAS jugando:
--   impulso de amigos × min(4, 1 + amigos conectados) · VIP ×1.5 · impulsos permanentes +5% c/u.
function HeroinaService.MultiplicadorMonedas(jugador: Player): number
	local conectados = jugador:GetAttribute("AmigosConectados")
	local nAmigos = if typeof(conectados) == "number" then conectados else 0
	local multiplicador = math.min(Juego.MaxMultiplicadorAmigos, 1 + nAmigos)
	if TiendaRobux.TienePase(jugador, "HeroinaVIP") then
		multiplicador *= MULTIPLICADOR_VIP
	end
	local impulsos = jugador:GetAttribute("Impulsos")
	if typeof(impulsos) == "number" then
		multiplicador *= 1 + Juego.Lobby.BonoPorImpulso * math.clamp(impulsos, 0, Juego.Lobby.MaxImpulsos)
	end
	return multiplicador
end

-- Monedas ganadas jugando (recompensas y bonos). Las COMPRADAS usan SumarMonedas sin multiplicar.
function HeroinaService.SumarMonedasGanadas(jugador: Player, cantidad: number)
	HeroinaService.SumarMonedas(jugador, math.floor(cantidad * HeroinaService.MultiplicadorMonedas(jugador) + 0.5))
end

local function actualizarAmigos(jugador: Player)
	local n = 0
	for otro in amigos[jugador] or {} do
		if otro.Parent then
			n += 1
		end
	end
	jugador:SetAttribute("AmigosConectados", n)
end

local function registrarAmistades(jugador: Player)
	amigos[jugador] = amigos[jugador] or {}
	actualizarAmigos(jugador)
	for _, otro in Players:GetPlayers() do
		if otro ~= jugador then
			task.spawn(function()
				local ok, sonAmigos = pcall(function()
					return jugador:IsFriendsWith(otro.UserId)
				end)
				if ok and sonAmigos and jugador.Parent and otro.Parent then
					amigos[jugador] = amigos[jugador] or {}
					amigos[otro] = amigos[otro] or {}
					amigos[jugador][otro] = true
					amigos[otro][jugador] = true
					actualizarAmigos(jugador)
					actualizarAmigos(otro)
				end
			end)
		end
	end
end

-- Resta monedas solo si alcanzan. Devuelve si se pudo pagar.
function HeroinaService.GastarMonedas(jugador: Player, cantidad: number): boolean
	local monedas = HeroinaService.ObtenerMonedas(jugador)
	if cantidad < 0 or monedas < cantidad then
		return false
	end
	jugador:SetAttribute(ATRIBUTO_MONEDAS, monedas - cantidad)
	return true
end

function HeroinaService.SumarDerrotado(jugador: Player)
	local actual = jugador:GetAttribute(ATRIBUTO_DERROTADOS)
	jugador:SetAttribute(ATRIBUTO_DERROTADOS, (if typeof(actual) == "number" then actual else 0) + 1)
end

-- Suma XP; cada nivel N requiere N * ExperienciaPorNivel. Anuncia al jugador si sube de nivel.
function HeroinaService.SumarExperiencia(jugador: Player, cantidad: number)
	local nivel = jugador:GetAttribute(ATRIBUTO_NIVEL)
	local experiencia = jugador:GetAttribute(ATRIBUTO_EXPERIENCIA)
	local n: number = if typeof(nivel) == "number" then nivel else 1
	local xp: number = (if typeof(experiencia) == "number" then experiencia else 0) + cantidad
	local subio = false
	local nuevoPoder: Types.PoderConfig? = nil
	local nuevaRanura: Types.Ranura? = nil
	local nuevoTemporal = false
	local arquetipo = jugador:GetAttribute("Arquetipo")
	while xp >= n * Juego.ExperienciaPorNivel do
		xp -= n * Juego.ExperienciaPorNivel
		n += 1
		subio = true
		local poder, ranura, temporal = Poderes.DesbloqueadoEn(arquetipo, n)
		if poder then
			nuevoPoder, nuevaRanura, nuevoTemporal = poder, ranura, temporal
		end
	end
	jugador:SetAttribute(ATRIBUTO_EXPERIENCIA, xp)
	jugador:SetAttribute(ATRIBUTO_NIVEL, n)
	if subio then
		local subtitulo = "¡Sigue defendiendo Sugar Town!"
		if nuevoPoder then
			local tecla = if nuevaRanura == "Primario" then "E" else "Q"
			local minutos = math.floor(Poderes.LaserTemporal.Activo / 60 + 0.5)
			subtitulo = if nuevoTemporal
				then `¡NUEVO PODER: {nuevoPoder.Icono} {nuevoPoder.Nombre} [{tecla}] durante {minutos} min!`
				elseif nuevoPoder.Tipo == "Laser" and Poderes.NivelMinimo(nuevoPoder) < nuevoPoder.NivelRequerido
				then `¡{nuevoPoder.Icono} {nuevoPoder.Nombre} [{tecla}] ya sin límite de tiempo!`
				else `¡NUEVO PODER: {nuevoPoder.Icono} {nuevoPoder.Nombre} [{tecla}]!`
		else
			local proximo = Poderes.ProximoDesbloqueo(arquetipo, n)
			if proximo then
				subtitulo = `Próximo poder en Nv. {Poderes.NivelMinimo(proximo)}: {proximo.Icono} {proximo.Nombre}`
			end
		end
		Remotes.Evento("Anuncio"):FireClient(jugador, `¡NIVEL {n}!`, subtitulo, Color3.fromRGB(255, 225, 80))
	end
end

function HeroinaService.Init()
	eventoCuracion = Remotes.Evento("Curacion")
	carpetaRetratos = Instance.new("Folder")
	carpetaRetratos.Name = "Retratos"
	carpetaRetratos.Parent = ReplicatedStorage
	Remotes.Evento("ElegirHeroina").OnServerEvent:Connect(function(jugador: Player, arquetipo: unknown)
		local ahora = os.clock()
		if ahora - (ultimoCambio[jugador] or -math.huge) < ENFRIAMIENTO_CAMBIO then
			return
		end
		if HeroinaService.AsignarArquetipo(jugador, arquetipo) then
			ultimoCambio[jugador] = ahora
		end
	end)
	Players.PlayerRemoving:Connect(function(jugador)
		ultimoCambio[jugador] = nil
		cuerpos[jugador] = nil
		versionTransformacion[jugador] = nil
		ultimoDano[jugador] = nil
		retratoClase[jugador] = nil
		versionRetrato[jugador] = nil
		local retrato = carpetaRetratos:FindFirstChild(tostring(jugador.UserId))
		if retrato then
			retrato:Destroy()
		end
		for otro in amigos[jugador] or {} do
			local deOtro = amigos[otro]
			if deOtro then
				deOtro[jugador] = nil
				actualizarAmigos(otro)
			end
		end
		amigos[jugador] = nil
		desconectar(conexionesJugador[jugador])
		desconectar(conexionesPersonaje[jugador])
		conexionesJugador[jugador] = nil
		conexionesPersonaje[jugador] = nil
	end)

	Remotes.Evento("EstadoCarrera").OnServerEvent:Connect(function(jugador: Player, corriendo: unknown)
		if typeof(corriendo) ~= "boolean" then
			return
		end
		local character = jugador.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if character and humanoid then
			establecerCarrera(character, (corriendo :: boolean) and humanoid.Health > 0)
		end
	end)

	Remotes.Evento("EstadoVuelo").OnServerEvent:Connect(function(jugador: Player, volando: unknown)
		if typeof(volando) ~= "boolean" then
			return
		end
		local character = jugador.Character
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		-- Derribada no puede volar (aunque un cliente modificado lo pida)
		local vivo = humanoid ~= nil and humanoid.Health > 0 and character:GetAttribute("Derribada") ~= true
		establecerVuelo(character, (volando :: boolean) and vivo)
	end)
end

-- Regeneración: tras EsperaTrasDano s sin recibir daño, cura un % de la vida máxima por segundo.
local function regenerar()
	local config = Juego.Regeneracion
	local ahora = os.clock()
	for _, jugador in Players:GetPlayers() do
		local character = jugador.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not character or not humanoid or humanoid.Health <= 0 or humanoid.Health >= humanoid.MaxHealth then
			continue
		end
		if character:GetAttribute("Derribada") == true then
			continue -- derribada: solo se levanta si la salvan o revive
		end
		if ahora - (ultimoDano[jugador] or 0) < config.EsperaTrasDano then
			continue
		end
		local cura = math.min(
			humanoid.MaxHealth - humanoid.Health,
			math.max(1, math.floor(humanoid.MaxHealth * config.PorcentajePorSegundo * config.Intervalo + 0.5))
		)
		humanoid.Health += cura
		eventoCuracion:FireAllClients(character, cura)
	end
end

function HeroinaService.Start()
	task.spawn(function()
		while true do
			task.wait(Juego.Regeneracion.Intervalo)
			regenerar()
		end
	end)
	Players.PlayerAdded:Connect(registrarAmistades)
	Players.PlayerAdded:Connect(alEntrarJugador)
	for _, jugador in Players:GetPlayers() do
		task.spawn(registrarAmistades, jugador)
		task.spawn(alEntrarJugador, jugador)
	end
end

return HeroinaService
