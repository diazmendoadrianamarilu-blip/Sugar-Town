--!strict
-- MonstruoService: crea monstruos gigantes geométricos y controla su IA.
--   • Cuerpo de piezas soldadas a un HumanoidRootPart invisible (Humanoid R15 con HipHeight: camina solo).
--   • Ojos neón con luz, cuernos, brazos, piernas y barra de vida (BillboardGui).
--   • IA (cada 0.2 s): si hay una heroína cerca y al alcance vertical → la persigue y golpea;
--     si no → camina al edificio en pie más cercano y lo golpea.
--   • Llevan la etiqueta "Enemigo" → CombateService les aplica el daño de los poderes.
-- Atributo en ReplicatedStorage: MonstruosVivos.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Juego = require(Shared.Config.Juego)
local Monstruos = require(Shared.Config.Monstruos)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local AtaquesMonstruo = require(script.Parent.AtaquesMonstruo)
local CombateService = require(script.Parent.CombateService)
local EdificioService = require(script.Parent.EdificioService)
local RescateService = require(script.Parent.RescateService)

type MonstruoConfig = Types.MonstruoConfig

type Brazo = { motor: Motor6D, base: CFrame }

type EstadoMonstruo = {
	modelo: Model,
	humanoid: Humanoid,
	raiz: BasePart,
	cuerpo: BasePart,
	tamanoCuerpo: Vector3,
	dano: number,
	alcance: number, -- distancia horizontal de golpe (incluye el tamaño del cuerpo)
	alcanceVertical: number,
	cadencia: number,
	radioPersecucion: number,
	proximoAtaque: number,
	brazos: { Brazo },
	-- Ataque especial con aviso (AtaquesMonstruo)
	atacante: AtaquesMonstruo.Atacante,
	proximoEspecial: number,
	ocupado: boolean, -- avisando / ejecutando el especial: no camina ni da golpes normales
}

local INTERVALO_IA = 0.2
local COLOR_DANO_HEROINA = Color3.fromRGB(255, 70, 70)
local COLOR_CONTORNO = Color3.fromRGB(30, 10, 50)

local monstruos: { [Model]: EstadoMonstruo } = {}
local vivos = 0
local carpeta: Folder
local eventoDerrotado: RemoteEvent
local aleatorio = Random.new()

local MonstruoService = {}

local function actualizarContador()
	ReplicatedStorage:SetAttribute("MonstruosVivos", vivos)
end

-- ─── Construcción ────────────────────────────────────────────────────────────

local function pieza(
	modelo: Model,
	raiz: BasePart,
	nombre: string,
	forma: Enum.PartType,
	tamano: Vector3,
	desplazamiento: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local parte = Instance.new("Part")
	parte.Name = nombre
	parte.Shape = forma
	parte.Size = tamano
	parte.Color = color
	parte.Material = material or Enum.Material.SmoothPlastic
	parte.CanCollide = false
	parte.CanTouch = false
	parte.Massless = true
	parte.TopSurface = Enum.SurfaceType.Smooth
	parte.BottomSurface = Enum.SurfaceType.Smooth
	parte.CFrame = raiz.CFrame * desplazamiento -- "raiz" puede ser cualquier pieza soporte
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = raiz
	soldadura.Part1 = parte
	soldadura.Parent = parte
	parte.Parent = modelo
	return parte
end

local function crearBarraVida(raiz: BasePart, humanoid: Humanoid, nombre: string, escala: number, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BarraVida"
	gui.Adornee = raiz
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 8 * escala, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.LightInfluence = 0
	gui.Parent = raiz

	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Size = UDim2.fromScale(1, 0.5)
	etiqueta.Font = Enum.Font.FredokaOne
	etiqueta.Text = nombre
	etiqueta.TextScaled = true
	etiqueta.TextColor3 = Color3.new(1, 1, 1)
	etiqueta.TextStrokeTransparency = 0
	etiqueta.TextStrokeColor3 = COLOR_CONTORNO
	etiqueta.Parent = gui

	local fondo = Instance.new("Frame")
	fondo.Position = UDim2.fromScale(0.1, 0.58)
	fondo.Size = UDim2.fromScale(0.8, 0.36)
	fondo.BackgroundColor3 = COLOR_CONTORNO
	fondo.Parent = gui
	local esquina = Instance.new("UICorner")
	esquina.CornerRadius = UDim.new(0.5, 0)
	esquina.Parent = fondo

	local barra = Instance.new("Frame")
	barra.Size = UDim2.fromScale(1, 1)
	barra.BackgroundColor3 = color
	barra.Parent = fondo
	local esquinaBarra = esquina:Clone()
	esquinaBarra.Parent = barra

	humanoid.HealthChanged:Connect(function(vida)
		barra.Size = UDim2.fromScale(math.clamp(vida / math.max(humanoid.MaxHealth, 1), 0, 1), 1)
	end)
end

local COLOR_COLMILLO = Color3.fromRGB(255, 250, 235)
local COLOR_GARRA = Color3.fromRGB(255, 225, 120)

local function cuna(modelo: Model, raiz: BasePart, nombre: string, tamano: Vector3, desplazamiento: CFrame, color: Color3, soporte: BasePart?): WedgePart
	local parte = Instance.new("WedgePart")
	parte.Name = nombre
	parte.Size = tamano
	parte.Color = color
	parte.Material = Enum.Material.SmoothPlastic
	parte.CanCollide = false
	parte.CanTouch = false
	parte.Massless = true
	local ancla = soporte or raiz
	parte.CFrame = ancla.CFrame * desplazamiento
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = ancla
	soldadura.Part1 = parte
	soldadura.Parent = parte
	parte.Parent = modelo
	return parte
end

-- Monstruo musculoso estilo caricatura: ~19 studs de alto con escala 1.
local function construirModelo(config: MonstruoConfig, e: number, posicionSuelo: Vector3, nombre: string): (Model, BasePart, BasePart, Humanoid, { Brazo })
	local modelo = Instance.new("Model")
	modelo.Name = config.Id

	local alturaRaiz = 12 * e -- centro de la raíz sobre el suelo
	local raiz = Instance.new("Part")
	raiz.Name = "HumanoidRootPart"
	raiz.Size = Vector3.new(9, 10, 7) * e
	raiz.Transparency = 1
	raiz.CanCollide = false
	raiz.CanTouch = false
	raiz.CFrame = CFrame.new(posicionSuelo + Vector3.new(0, alturaRaiz, 0))
	raiz.Parent = modelo

	local color = config.Color
	local claro = color:Lerp(Color3.new(1, 1, 1), 0.4)
	local oscuro = color:Lerp(COLOR_CONTORNO, 0.5)
	local ball = Enum.PartType.Ball
	local block = Enum.PartType.Block
	local cyl = Enum.PartType.Cylinder

	-- Torso musculoso
	local cuerpo = pieza(modelo, raiz, "Pecho", block, Vector3.new(10, 8, 6.5) * e, CFrame.new(0, 1.5 * e, 0), color)
	for _, lado in { -1, 1 } do
		pieza(modelo, raiz, "Pectoral", ball, Vector3.one * 4.6 * e, CFrame.new(lado * 2.3 * e, 2.6 * e, -2.6 * e), claro)
		pieza(modelo, raiz, "Hombro", ball, Vector3.one * 5.2 * e, CFrame.new(lado * 6 * e, 4 * e, 0), oscuro)
	end
	pieza(modelo, raiz, "Panza", ball, Vector3.one * 7 * e, CFrame.new(0, -2 * e, -1.2 * e), claro)

	-- Cabeza adelantada (encorvado y amenazante)
	pieza(modelo, raiz, "Cabeza", ball, Vector3.one * 6.5 * e, CFrame.new(0, 7.6 * e, -1.6 * e), color)
	pieza(modelo, raiz, "Mandibula", block, Vector3.new(5.6, 2.4, 4) * e, CFrame.new(0, 5.4 * e, -3.3 * e), oscuro)
	pieza(modelo, raiz, "Boca", block, Vector3.new(4.4, 0.9, 0.5) * e, CFrame.new(0, 6.1 * e, -5.3 * e), Color3.fromRGB(50, 10, 40))

	for _, lado in { -1, 1 } do
		-- Ojos brillantes con pupila
		local ojo = pieza(modelo, raiz, "Ojo", ball, Vector3.one * 1.9 * e, CFrame.new(lado * 1.35 * e, 8.2 * e, -4.4 * e), config.ColorOjos, Enum.Material.Neon)
		pieza(modelo, raiz, "Pupila", ball, Vector3.one * 0.8 * e, CFrame.new(lado * 1.35 * e, 8.1 * e, -5.2 * e), Color3.new(0, 0, 0))
		if lado == 1 then
			local luz = Instance.new("PointLight")
			luz.Color = config.ColorOjos
			luz.Range = 12 * e
			luz.Brightness = 2.5
			luz.Parent = ojo
		end
		-- Cejas fruncidas: el extremo interior más bajo
		pieza(modelo, raiz, "Ceja", block, Vector3.new(2.6, 0.7, 0.9) * e, CFrame.new(lado * 1.4 * e, 9.3 * e, -4.5 * e) * CFrame.Angles(0, 0, math.rad(lado * 25)), COLOR_CONTORNO)
		-- Colmillos grandes (cuñas con la punta hacia abajo)
		cuna(modelo, raiz, "Colmillo", Vector3.new(0.9, 2.4, 1.1) * e, CFrame.new(lado * 1.7 * e, 4.9 * e, -5.2 * e) * CFrame.Angles(math.rad(180), 0, 0), COLOR_COLMILLO)
		-- Cuernos con punta neón
		local giro = CFrame.new(lado * 2.3 * e, 10.4 * e, -1.6 * e) * CFrame.Angles(0, 0, math.rad(90 - lado * 28))
		pieza(modelo, raiz, "Cuerno", cyl, Vector3.new(4.2, 1.3, 1.3) * e, giro, oscuro)
		pieza(modelo, raiz, "PuntaCuerno", ball, Vector3.one * 1.5 * e, giro * CFrame.new(2.1 * e, 0, 0), config.ColorOjos, Enum.Material.Neon)
	end

	-- Púas dorsales
	for i = 0, 3 do
		cuna(modelo, raiz, "Pua", Vector3.new(0.9, 3.2 - i * 0.4, 3) * e, CFrame.new(0, (7 - i * 2.8) * e, (3.6 + i * 0.1) * e) * CFrame.Angles(0, math.rad(180), 0), config.ColorOjos:Lerp(oscuro, 0.3))
	end

	-- Brazos articulados (Motor6D) con puño y garras
	local brazos: { Brazo } = {}
	for _, lado in { -1, 1 } do
		local brazo = Instance.new("Part")
		brazo.Name = "Brazo"
		brazo.Size = Vector3.new(3.2, 9, 3.2) * e
		brazo.Color = color
		brazo.Material = Enum.Material.SmoothPlastic
		brazo.CanCollide = false
		brazo.CanTouch = false
		brazo.Massless = true
		local base = CFrame.new(lado * 6.4 * e, 4 * e, 0) * CFrame.Angles(math.rad(-12), 0, math.rad(lado * 12))
		local c1 = CFrame.new(0, 4.3 * e, 0)
		brazo.CFrame = raiz.CFrame * base * c1:Inverse()
		brazo.Parent = modelo
		local motor = Instance.new("Motor6D")
		motor.Name = "Hombro"
		motor.Part0 = raiz
		motor.Part1 = brazo
		motor.C0 = base
		motor.C1 = c1
		motor.Parent = raiz
		table.insert(brazos, { motor = motor, base = base })

		local puno = pieza(modelo, brazo, "Puno", ball, Vector3.one * 4.4 * e, CFrame.new(0, -5 * e, 0), oscuro)
		for g = -1, 1 do
			cuna(modelo, raiz, "Garra", Vector3.new(0.6, 1.8, 1) * e, CFrame.new(g * 1.2 * e, -1.4 * e, -2 * e) * CFrame.Angles(math.rad(-110), 0, 0), COLOR_GARRA, puno)
		end
	end

	-- Piernas y pies (llegan exactamente al suelo: -12 * e)
	for _, lado in { -1, 1 } do
		pieza(modelo, raiz, "Pierna", block, Vector3.new(3.8, 7, 3.8) * e, CFrame.new(lado * 2.9 * e, -8.5 * e, 0), oscuro)
		pieza(modelo, raiz, "Pie", block, Vector3.new(4.6, 1.6, 5.6) * e, CFrame.new(lado * 2.9 * e, -11.2 * e, -0.9 * e), color)
		for g = -1, 1 do
			cuna(modelo, raiz, "GarraPie", Vector3.new(0.7, 1, 1.2) * e, CFrame.new(lado * 2.9 * e + g * 1.3 * e, -11.6 * e, -4 * e), COLOR_GARRA)
		end
	end

	-- Contorno negro de caricatura (cel-shading)
	local contorno = Instance.new("Highlight")
	contorno.Name = "Contorno"
	contorno.FillTransparency = 1
	contorno.OutlineColor = Color3.new(0, 0, 0)
	contorno.OutlineTransparency = 0
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Parent = modelo

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = alturaRaiz - raiz.Size.Y / 2 -- de la base de la raíz al suelo
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoJumpEnabled = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	for _, estadoHumanoid in {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Jumping,
	} do
		humanoid:SetStateEnabled(estadoHumanoid, false)
	end
	humanoid.Parent = modelo

	modelo.PrimaryPart = raiz
	crearBarraVida(raiz, humanoid, nombre, e * 1.75, config.ColorOjos)
	return modelo, raiz, cuerpo, humanoid, brazos
end

-- ─── IA ──────────────────────────────────────────────────────────────────────

local function eliminar(modelo: Model)
	if monstruos[modelo] then
		monstruos[modelo] = nil
		vivos -= 1
		actualizarContador()
	end
	modelo:Destroy()
end

local function golpeVisual(estado: EstadoMonstruo, punto: Vector3)
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(estado.cuerpo, info, { Size = estado.tamanoCuerpo * Vector3.new(1.12, 0.9, 1.12) }):Play()
	-- Brazos: se levantan y golpean hacia delante (uno tras otro)
	local golpe = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true)
	for i, brazo in estado.brazos do
		task.delay((i - 1) * 0.08, function()
			if brazo.motor.Parent then
				TweenService:Create(brazo.motor, golpe, { C0 = brazo.base * CFrame.Angles(math.rad(115), 0, 0) }):Play()
			end
		end)
	end

	local anillo = Instance.new("Part")
	anillo.Shape = Enum.PartType.Cylinder
	anillo.Size = Vector3.new(0.4, 2, 2)
	anillo.CFrame = CFrame.new(punto) * CFrame.Angles(0, 0, math.rad(90))
	anillo.Color = Color3.fromRGB(255, 80, 80)
	anillo.Material = Enum.Material.ForceField
	anillo.Transparency = 0.65
	anillo.Anchored = true
	anillo.CanCollide = false
	anillo.CanQuery = false
	anillo.CanTouch = false
	anillo.Parent = carpeta
	TweenService:Create(anillo, TweenInfo.new(0.4), { Size = Vector3.new(0.2, 14, 14), Transparency = 1 }):Play()
	Debris:AddItem(anillo, 0.45)
end

local function heroinaObjetivo(estado: EstadoMonstruo, posicion: Vector3): (Model?, BasePart?, number)
	local mejor: Model? = nil
	local mejorRaiz: BasePart? = nil
	local mejorDistancia = math.huge
	for _, jugador in Players:GetPlayers() do
		local character = jugador.Character
		local raiz = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		-- Las heroínas derribadas no son objetivo (esperan a que las salven)
		if character and raiz and raiz:IsA("BasePart") and humanoid and humanoid.Health > 0 and not RescateService.EstaDerribada(character) then
			local d = raiz.Position - posicion
			local horizontal = Vector3.new(d.X, 0, d.Z).Magnitude
			if horizontal <= estado.radioPersecucion and math.abs(d.Y) <= estado.alcanceVertical and horizontal < mejorDistancia then
				mejor, mejorRaiz, mejorDistancia = character, raiz, horizontal
			end
		end
	end
	return mejor, mejorRaiz, mejorDistancia
end

local function lanzarEspecial(estado: EstadoMonstruo, objetivo: Vector3, ahora: number)
	estado.ocupado = true
	estado.proximoEspecial = ahora + estado.atacante.especial.Enfriamiento
	task.spawn(function()
		AtaquesMonstruo.Ejecutar(estado.atacante, objetivo)
		estado.ocupado = false
		estado.proximoAtaque = math.max(estado.proximoAtaque, os.clock() + 0.6)
	end)
end

local function pensar(estado: EstadoMonstruo, ahora: number)
	if estado.ocupado then
		return -- en pleno ataque especial
	end
	local posicion = estado.raiz.Position
	if posicion.Y < Juego.Ciudad.Centro.Y - 60 then
		eliminar(estado.modelo) -- se cayó del mapa
		return
	end

	local heroina, raizHeroina, distanciaHeroina = heroinaObjetivo(estado, posicion)
	if heroina and raizHeroina and ahora >= estado.proximoEspecial and AtaquesMonstruo.EnAlcance(estado.atacante, distanciaHeroina) then
		lanzarEspecial(estado, raizHeroina.Position, ahora)
		return
	end
	if heroina and raizHeroina then
		if distanciaHeroina <= estado.alcance then
			estado.humanoid:MoveTo(posicion) -- detenerse
			if ahora >= estado.proximoAtaque then
				estado.proximoAtaque = ahora + estado.cadencia
				local humanoidHeroina = heroina:FindFirstChildOfClass("Humanoid")
				if humanoidHeroina then
					-- RescateService: el escudo lo anula y un golpe mortal la deja DERRIBADA
					local hecho = RescateService.Danar(heroina, humanoidHeroina, estado.dano)
					if hecho > 0 then
						CombateService.MostrarNumero(raizHeroina.Position, hecho, COLOR_DANO_HEROINA, false)
					end
				end
				golpeVisual(estado, raizHeroina.Position - Vector3.new(0, 2.5, 0))
			end
		else
			estado.humanoid:MoveTo(raizHeroina.Position)
		end
		return
	end

	local edificio, punto, distancia = EdificioService.MasCercano(posicion)
	if not edificio then
		estado.humanoid:MoveTo(posicion) -- no queda nada en pie
		return
	end
	if distancia <= estado.alcance then
		estado.humanoid:MoveTo(posicion)
		if ahora >= estado.proximoAtaque then
			estado.proximoAtaque = ahora + estado.cadencia
			EdificioService.Danar(edificio, estado.dano)
			golpeVisual(estado, punto + Vector3.new(0, 1, 0))
		end
	else
		estado.humanoid:MoveTo(punto)
	end
end

-- ─── API pública ─────────────────────────────────────────────────────────────

-- Crea un monstruo con estadísticas escaladas según la oleada.
-- `ajuste` (opcional) escala vida y daño según cuántas heroínas hay en la ciudad (lo calcula RondaService).
function MonstruoService.Aparecer(
	config: MonstruoConfig,
	oleada: number,
	esJefe: boolean,
	posicion: Vector3,
	ajuste: Types.AjusteDificultad?
): Model
	local ajustes = Juego.Oleadas
	local jefe = Monstruos.Jefe
	local ajusteVida = if ajuste then ajuste.Vida else 1
	local ajusteDano = if ajuste then ajuste.Dano else 1
	local multVida = (1 + ajustes.AumentoVidaPorOleada * (oleada - 1)) * (if esJefe then jefe.MultiplicadorVida else 1) * ajusteVida
	local multDano = (1 + ajustes.AumentoDanoPorOleada * (oleada - 1)) * (if esJefe then jefe.MultiplicadorDano else 1) * ajusteDano
	local escala = config.Escala * (if esJefe then jefe.MultiplicadorEscala else 1)
	local multPremio = if esJefe then jefe.MultiplicadorRecompensa else 1
	local nombre = if esJefe then `👑 {config.Nombre} Jefe` else config.Nombre

	local modelo, raiz, cuerpo, humanoid, brazos = construirModelo(config, escala, posicion, nombre)
	local vida = math.floor(config.Vida * multVida)
	humanoid.MaxHealth = vida
	humanoid.Health = vida
	humanoid.WalkSpeed = config.Velocidad

	modelo:SetAttribute("Recompensa", config.Recompensa * multPremio)
	modelo:SetAttribute("Experiencia", config.Experiencia * multPremio)
	CollectionService:AddTag(modelo, "Enemigo")
	modelo.Parent = carpeta
	raiz:SetNetworkOwner(nil) -- el servidor controla su física

	local estado: EstadoMonstruo = {
		modelo = modelo,
		humanoid = humanoid,
		raiz = raiz,
		cuerpo = cuerpo,
		tamanoCuerpo = cuerpo.Size,
		dano = config.Dano * multDano,
		alcance = config.RangoAtaque * escala + 6 * escala,
		alcanceVertical = 16 * escala,
		cadencia = config.CadenciaAtaque,
		radioPersecucion = config.RadioPersecucion * math.max(escala, 1),
		proximoAtaque = 0,
		brazos = brazos,
		atacante = {
			modelo = modelo,
			humanoid = humanoid,
			raiz = raiz,
			cuerpo = cuerpo,
			tamanoCuerpo = cuerpo.Size,
			brazos = brazos,
			especial = config.Especial,
			escalaEspecial = if esJefe then jefe.MultiplicadorEscala else 1,
			multDano = multDano,
			color = config.Color,
		},
		-- El primer especial llega tras unos segundos (no todos a la vez al aparecer)
		proximoEspecial = os.clock() + aleatorio:NextNumber(2, config.Especial.Enfriamiento),
		ocupado = false,
	}
	monstruos[modelo] = estado
	vivos += 1
	actualizarContador()

	humanoid.Died:Connect(function()
		if not monstruos[modelo] then
			return
		end
		monstruos[modelo] = nil
		vivos -= 1
		actualizarContador()
		-- ¡Poof!: cada cliente dibuja el humo de colores, las estrellas y las monedas que vuelan
		-- hacia quien lo derrotó (atributo que pone CombateService justo antes del golpe final).
		local idAsesino = modelo:GetAttribute("UltimoAtacante")
		local asesino = if typeof(idAsesino) == "number" then Players:GetPlayerByUserId(idAsesino) else nil
		local monedas = modelo:GetAttribute("Recompensa")
		eventoDerrotado:FireAllClients(
			cuerpo.Position,
			config.Color,
			modelo:GetExtentsSize().Y,
			asesino,
			if typeof(monedas) == "number" and asesino then monedas else 0
		)
		-- Desaparece rápido dentro de la nube de humo
		for _, d in modelo:GetDescendants() do
			if d:IsA("BasePart") and d ~= raiz then
				TweenService:Create(d, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			elseif d:IsA("BillboardGui") then
				d.Enabled = false
			end
		end
		Debris:AddItem(modelo, 0.3)
	end)

	return modelo
end

function MonstruoService.CantidadVivos(): number
	return vivos
end

-- Derrota a todos los monstruos vivos (Bomba de Esencia Estelar). No da recompensas.
function MonstruoService.DerrotarTodos()
	for modelo, estado in monstruos do
		modelo:SetAttribute("Recompensado", true)
		modelo:SetAttribute("UltimoAtacante", nil) -- sin recompensa: no vuelan monedas
		estado.humanoid.Health = 0
	end
end

function MonstruoService.EliminarTodos()
	local lista = {}
	for modelo in monstruos do
		table.insert(lista, modelo)
	end
	for _, modelo in lista do
		eliminar(modelo)
	end
end

function MonstruoService.Init()
	AtaquesMonstruo.Init()
	eventoDerrotado = Remotes.Evento("MonstruoDerrotado")
	carpeta = Instance.new("Folder")
	carpeta.Name = "Monstruos"
	carpeta.Parent = Workspace
	actualizarContador()
end

function MonstruoService.Start()
	task.spawn(function()
		while true do
			task.wait(INTERVALO_IA)
			local ahora = os.clock()
			-- Copia de la lista: "pensar" puede eliminar monstruos
			local lista = {}
			for _, estado in monstruos do
				table.insert(lista, estado)
			end
			for _, estado in lista do
				if estado.humanoid.Health > 0 and estado.modelo.Parent then
					pensar(estado, ahora)
				end
			end
		end
	end)
end

return MonstruoService
