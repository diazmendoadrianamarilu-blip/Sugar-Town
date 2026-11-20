--!strict
-- AtaquesMonstruo: ataques especiales de los monstruos, siempre con AVISO previo para poder esquivarlos.
--   • Gelatina (Gomiloso): círculo rojo donde está la heroína; ~1 s después cae una bola de gelatina
--     que hace daño y la ralentiza.
--   • Embestida (Zumbón): franja roja en línea recta; después sale disparado por ella y empuja.
--   • GolpeSuelo (Brutón y jefe): círculo rojo alrededor; después golpe al suelo con onda expansiva y piedras.
-- Todo lo decide el servidor (daño, a quién alcanza). Los avisos y efectos son piezas del servidor
-- (se replican solas); los sonidos se reproducen en el servidor y también se replican.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Sonidos = require(Shared.Config.Sonidos)
local Types = require(Shared.Types)
local CombateService = require(script.Parent.CombateService)
local RescateService = require(script.Parent.RescateService)

type Brazo = { motor: Motor6D, base: CFrame }

-- Lo que el ataque necesita saber del monstruo (lo rellena MonstruoService).
export type Atacante = {
	modelo: Model,
	humanoid: Humanoid,
	raiz: BasePart,
	cuerpo: BasePart,
	tamanoCuerpo: Vector3,
	brazos: { Brazo },
	especial: Types.AtaqueEspecialConfig,
	escalaEspecial: number, -- 1 normal, 1.5 jefe (radios y alcances)
	multDano: number, -- oleada × nº de jugadoras
	color: Color3,
}

local COLOR_AVISO = Color3.fromRGB(255, 25, 25)
local COLOR_DANO_HEROINA = Color3.fromRGB(255, 70, 70)
local DURACION_EMBESTIDA = 0.35

local carpeta: Folder
local eventoEmpujon: RemoteEvent

local AtaquesMonstruo = {}

-- ─── Utilidades ──────────────────────────────────────────────────────────────

local function parametrosEscenario(): RaycastParams
	local excluir: { Instance } = { carpeta }
	local monstruos = Workspace:FindFirstChild("Monstruos")
	if monstruos then
		table.insert(excluir, monstruos)
	end
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(excluir, jugador.Character)
		end
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	return parametros
end

-- Punto del suelo bajo una posición (para dibujar el aviso aunque la heroína vuele).
local function sueloBajo(posicion: Vector3): Vector3
	local resultado = Workspace:Raycast(posicion + Vector3.new(0, 4, 0), Vector3.new(0, -400, 0), parametrosEscenario())
	return if resultado then resultado.Position else Vector3.new(posicion.X, posicion.Y - 3, posicion.Z)
end

local function parteEfecto(nombre: string, forma: Enum.PartType, tamano: Vector3, cframe: CFrame, color: Color3, transparencia: number): Part
	local parte = Instance.new("Part")
	parte.Name = nombre
	parte.Shape = forma
	parte.Size = tamano
	parte.CFrame = cframe
	parte.Color = color
	parte.Material = Enum.Material.SmoothPlastic
	parte.Transparency = transparencia
	parte.Anchored = true
	parte.CanCollide = false
	parte.CanQuery = false
	parte.CanTouch = false
	parte.CastShadow = false
	parte.Parent = carpeta
	return parte
end

local function sonido(nombre: string, posicion: Vector3, tono: number?)
	local config = Sonidos[nombre]
	if not config then
		return
	end
	local ancla = Instance.new("Attachment")
	ancla.Position = posicion
	ancla.Parent = Workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = config.Id
	s.Volume = config.Volumen
	s.PlaybackSpeed = config.Tono * (tono or 1)
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 400
	s.Parent = ancla
	s:Play()
	Debris:AddItem(ancla, 6)
end

-- Aviso circular: anillo rojo + relleno que crece hasta el borde justo cuando llega el golpe.
local function avisoCirculo(centroSuelo: Vector3, radio: number, duracion: number)
	local plano = CFrame.new(centroSuelo + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local borde = parteEfecto("AvisoBorde", Enum.PartType.Cylinder, Vector3.new(0.2, radio * 2, radio * 2), plano, COLOR_AVISO, 0.5)
	local relleno = parteEfecto("AvisoRelleno", Enum.PartType.Cylinder, Vector3.new(0.3, 0.5, 0.5), plano, COLOR_AVISO, 0.15)
	TweenService:Create(relleno, TweenInfo.new(duracion, Enum.EasingStyle.Linear), { Size = Vector3.new(0.3, radio * 2, radio * 2) }):Play()
	Debris:AddItem(borde, duracion + 0.05)
	Debris:AddItem(relleno, duracion + 0.05)
end

-- Aviso en franja (embestida): rectángulo rojo desde el monstruo en la dirección del ataque.
local function avisoFranja(inicioSuelo: Vector3, direccion: Vector3, largo: number, ancho: number, duracion: number)
	local base = CFrame.lookAt(inicioSuelo + Vector3.new(0, 0.3, 0), inicioSuelo + Vector3.new(0, 0.3, 0) + direccion)
	local borde = parteEfecto("AvisoFranja", Enum.PartType.Block, Vector3.new(ancho, 0.2, largo), base * CFrame.new(0, 0, -largo / 2), COLOR_AVISO, 0.5)
	local relleno = parteEfecto("AvisoRelleno", Enum.PartType.Block, Vector3.new(ancho, 0.3, 0.5), base * CFrame.new(0, 0, -0.25), COLOR_AVISO, 0.15)
	TweenService:Create(relleno, TweenInfo.new(duracion, Enum.EasingStyle.Linear), {
		Size = Vector3.new(ancho, 0.3, largo),
		CFrame = base * CFrame.new(0, 0, -largo / 2),
	}):Play()
	Debris:AddItem(borde, duracion + 0.05)
	Debris:AddItem(relleno, duracion + 0.05)
end

-- Brazos arriba (preparando el golpe) o abajo de golpe.
local function moverBrazos(atacante: Atacante, angulo: number, duracion: number, estilo: Enum.EasingStyle)
	local info = TweenInfo.new(duracion, estilo, Enum.EasingDirection.Out)
	for _, brazo in atacante.brazos do
		if brazo.motor.Parent then
			TweenService:Create(brazo.motor, info, { C0 = brazo.base * CFrame.Angles(math.rad(angulo), 0, 0) }):Play()
		end
	end
end

local function inflar(atacante: Atacante, factor: Vector3, duracion: number)
	if atacante.cuerpo.Parent then
		TweenService:Create(atacante.cuerpo, TweenInfo.new(duracion, Enum.EasingStyle.Quad), { Size = atacante.tamanoCuerpo * factor }):Play()
	end
end

local function vivo(atacante: Atacante): boolean
	return atacante.modelo.Parent ~= nil and atacante.humanoid.Health > 0
end

-- Heroínas vivas con su raíz.
local function heroinas(): { { jugador: Player, character: Model, raiz: BasePart, humanoid: Humanoid } }
	local lista = {}
	for _, jugador in Players:GetPlayers() do
		local character = jugador.Character
		local raiz = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if character and raiz and raiz:IsA("BasePart") and humanoid and humanoid.Health > 0 and not RescateService.EstaDerribada(character) then
			table.insert(lista, { jugador = jugador, character = character, raiz = raiz, humanoid = humanoid })
		end
	end
	return lista
end

-- Daño + efectos a una heroína. El escudo de Estrategia la protege de todo.
local function alcanzar(
	atacante: Atacante,
	objetivo: { jugador: Player, character: Model, raiz: BasePart, humanoid: Humanoid },
	desde: Vector3
)
	if CombateService.TieneEscudo(objetivo.character) then
		return
	end
	local especial = atacante.especial
	local dano = RescateService.Danar(objetivo.character, objetivo.humanoid, especial.Dano * atacante.multDano)
	if dano > 0 then
		CombateService.MostrarNumero(objetivo.raiz.Position, dano, COLOR_DANO_HEROINA, false)
	end

	if especial.Ralentizacion < 1 and especial.DuracionEfecto > 0 then
		-- La velocidad la aplica su cliente (es dueña de su física); el servidor solo marca el estado.
		objetivo.character:SetAttribute("LentaFactor", especial.Ralentizacion)
		objetivo.character:SetAttribute("LentaHasta", Workspace:GetServerTimeNow() + especial.DuracionEfecto)
	end
	if especial.Empuje > 0 then
		local hacia = objetivo.raiz.Position - desde
		local plano = Vector3.new(hacia.X, 0, hacia.Z)
		local direccion = if plano.Magnitude > 0.1 then plano.Unit else Vector3.xAxis
		eventoEmpujon:FireClient(objetivo.jugador, (direccion + Vector3.new(0, 0.6, 0)).Unit * especial.Empuje)
	end
end

-- ─── Ataques ─────────────────────────────────────────────────────────────────

local function gelatina(atacante: Atacante, objetivo: Vector3)
	local especial = atacante.especial
	local radio = especial.Radio * atacante.escalaEspecial
	local suelo = sueloBajo(objetivo)
	local aviso = especial.Aviso
	avisoCirculo(suelo, radio, aviso)
	sonido("Rugido", atacante.raiz.Position, 1.3)
	inflar(atacante, Vector3.new(1.18, 1.1, 1.18), aviso * 0.6)

	-- La bola sale de la boca a mitad del aviso y cae en parábola justo al acabar
	local vuelo = math.min(0.55, aviso * 0.6)
	task.wait(aviso - vuelo)
	if not vivo(atacante) then
		return
	end
	inflar(atacante, Vector3.one, 0.12)
	local boca = atacante.raiz.Position + atacante.raiz.CFrame.LookVector * (atacante.tamanoCuerpo.Z * 0.8) + Vector3.new(0, atacante.tamanoCuerpo.Y * 0.7, 0)
	sonido("Escupitajo", boca)
	local bola = parteEfecto("Gelatina", Enum.PartType.Ball, Vector3.one * 3.2, CFrame.new(boca), atacante.color:Lerp(Color3.new(1, 1, 1), 0.25), 0.25)
	bola.Material = Enum.Material.Glass
	local altura = math.max(10, (objetivo - boca).Magnitude * 0.35)
	local inicio = os.clock()
	while true do
		local t = math.clamp((os.clock() - inicio) / vuelo, 0, 1)
		local punto = boca:Lerp(objetivo, t) + Vector3.new(0, math.sin(t * math.pi) * altura, 0)
		bola.CFrame = CFrame.new(punto)
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end

	-- Impacto: salpicadura y daño a quien siga dentro
	sonido("Gelatina", objetivo)
	TweenService:Create(bola, TweenInfo.new(0.35), { Size = Vector3.one * radio * 2, Transparency = 1 }):Play()
	Debris:AddItem(bola, 0.4)
	local charco = parteEfecto("Charco", Enum.PartType.Cylinder, Vector3.new(0.3, radio * 1.6, radio * 1.6), CFrame.new(suelo + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), bola.Color, 0.4)
	TweenService:Create(charco, TweenInfo.new(especial.DuracionEfecto, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(charco, especial.DuracionEfecto + 0.1)
	for _, heroina in heroinas() do
		local d = heroina.raiz.Position - objetivo
		if Vector3.new(d.X, 0, d.Z).Magnitude <= radio and math.abs(d.Y) <= radio + 4 then
			alcanzar(atacante, heroina, objetivo)
		end
	end
end

local function embestida(atacante: Atacante, objetivo: Vector3)
	local especial = atacante.especial
	local raiz = atacante.raiz
	local origen = raiz.Position
	local hacia = Vector3.new(objetivo.X - origen.X, 0, objetivo.Z - origen.Z)
	if hacia.Magnitude < 1 then
		return
	end
	local direccion = hacia.Unit
	local largo = math.min(hacia.Magnitude + 15, especial.AlcanceMax * atacante.escalaEspecial + 15)
	-- No atraviesa edificios: la franja se corta antes del obstáculo
	local choque = Workspace:Raycast(origen, direccion * largo, parametrosEscenario())
	if choque then
		largo = math.max(0, (choque.Position - origen).Magnitude - atacante.tamanoCuerpo.Z)
	end
	if largo < 8 then
		return
	end
	local ancho = especial.Radio * 2 * atacante.escalaEspecial
	local inicioSuelo = sueloBajo(origen)
	avisoFranja(inicioSuelo, direccion, largo, ancho, especial.Aviso)
	sonido("Rugido", origen, 1.5)
	raiz.CFrame = CFrame.lookAt(origen, origen + direccion)
	inflar(atacante, Vector3.new(1.05, 0.85, 1.15), especial.Aviso * 0.8) -- se agazapa
	moverBrazos(atacante, -40, especial.Aviso * 0.8, Enum.EasingStyle.Quad)

	task.wait(especial.Aviso)
	if not vivo(atacante) then
		return
	end
	sonido("Embestida", raiz.Position)
	inflar(atacante, Vector3.one, 0.1)
	moverBrazos(atacante, 0, 0.2, Enum.EasingStyle.Back)
	local alcanzadas: { [Player]: boolean } = {}
	local alto = atacante.tamanoCuerpo.Y * 2
	local inicioPivote = atacante.modelo:GetPivot()
	local inicio = os.clock()
	while vivo(atacante) do
		local t = math.clamp((os.clock() - inicio) / DURACION_EMBESTIDA, 0, 1)
		local avance = direccion * largo * t
		atacante.modelo:PivotTo(inicioPivote + avance)
		local actual = raiz.Position
		for _, heroina in heroinas() do
			if not alcanzadas[heroina.jugador] then
				local d = heroina.raiz.Position - actual
				local horizontal = Vector3.new(d.X, 0, d.Z).Magnitude
				if horizontal <= ancho / 2 + atacante.tamanoCuerpo.X / 2 and math.abs(d.Y) <= alto then
					alcanzadas[heroina.jugador] = true
					alcanzar(atacante, heroina, actual)
				end
			end
		end
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	atacante.humanoid:MoveTo(raiz.Position)
end

local function golpeSuelo(atacante: Atacante)
	local especial = atacante.especial
	local raiz = atacante.raiz
	local radio = especial.Radio * atacante.escalaEspecial
	local centro = sueloBajo(raiz.Position)
	avisoCirculo(centro, radio, especial.Aviso)
	sonido("Rugido", raiz.Position, 0.8)
	moverBrazos(atacante, 160, especial.Aviso * 0.8, Enum.EasingStyle.Quad) -- brazos arriba
	inflar(atacante, Vector3.new(1.08, 1.12, 1.08), especial.Aviso * 0.8)

	task.wait(especial.Aviso)
	if not vivo(atacante) then
		return
	end
	-- ¡Golpe!
	moverBrazos(atacante, -20, 0.12, Enum.EasingStyle.Quad)
	inflar(atacante, Vector3.new(1.15, 0.85, 1.15), 0.1)
	task.delay(0.3, function()
		if vivo(atacante) then
			moverBrazos(atacante, 0, 0.35, Enum.EasingStyle.Quad)
			inflar(atacante, Vector3.one, 0.3)
		end
	end)
	sonido("GolpeSuelo", centro)

	-- Onda expansiva
	local onda = parteEfecto("Onda", Enum.PartType.Cylinder, Vector3.new(1.5, 4, 4), CFrame.new(centro + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 230, 190), 0.4)
	onda.Material = Enum.Material.ForceField
	TweenService:Create(onda, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = Vector3.new(0.6, radio * 2.2, radio * 2.2), Transparency = 1 }):Play()
	Debris:AddItem(onda, 0.5)

	-- Piedras que saltan
	local aleatorio = Random.new()
	for _ = 1, 10 do
		local angulo = aleatorio:NextNumber(0, math.pi * 2)
		local distancia = aleatorio:NextNumber(radio * 0.2, radio * 0.8)
		local piedra = Instance.new("Part")
		piedra.Name = "Piedra"
		piedra.Size = Vector3.one * aleatorio:NextNumber(1.2, 2.6)
		piedra.Color = Color3.fromRGB(120, 105, 95):Lerp(Color3.fromRGB(170, 150, 130), aleatorio:NextNumber())
		piedra.Material = Enum.Material.Slate
		piedra.CFrame = CFrame.new(centro + Vector3.new(math.cos(angulo) * distancia, 1.5, math.sin(angulo) * distancia))
			* CFrame.Angles(aleatorio:NextNumber(0, 6), aleatorio:NextNumber(0, 6), 0)
		piedra.CanCollide = false
		piedra.CanQuery = false
		piedra.CanTouch = false
		piedra.Massless = true
		piedra.AssemblyLinearVelocity = Vector3.new(math.cos(angulo) * 18, aleatorio:NextNumber(35, 60), math.sin(angulo) * 18)
		piedra.AssemblyAngularVelocity = Vector3.new(aleatorio:NextNumber(-8, 8), aleatorio:NextNumber(-8, 8), 0)
		piedra.Parent = carpeta
		Debris:AddItem(piedra, 1.6)
	end

	local alturaMax = 10 * atacante.escalaEspecial + atacante.tamanoCuerpo.Y
	for _, heroina in heroinas() do
		local d = heroina.raiz.Position - centro
		if Vector3.new(d.X, 0, d.Z).Magnitude <= radio and d.Y <= alturaMax then
			alcanzar(atacante, heroina, centro)
		end
	end
end

-- ─── API pública ─────────────────────────────────────────────────────────────

-- ¿Puede usar ahora su ataque especial contra una heroína a esta distancia horizontal?
function AtaquesMonstruo.EnAlcance(atacante: Atacante, distanciaHorizontal: number): boolean
	local especial = atacante.especial
	local maximo = especial.AlcanceMax * atacante.escalaEspecial
	return distanciaHorizontal >= especial.AlcanceMin and distanciaHorizontal <= maximo
end

-- Lanza el ataque (cede: dura el aviso + la ejecución). Devuelve cuando termina.
function AtaquesMonstruo.Ejecutar(atacante: Atacante, objetivo: Vector3)
	local tipo = atacante.especial.Tipo
	atacante.humanoid:MoveTo(atacante.raiz.Position) -- quieto mientras avisa
	if tipo == "Gelatina" then
		gelatina(atacante, objetivo)
	elseif tipo == "Embestida" then
		embestida(atacante, objetivo)
	else
		golpeSuelo(atacante)
	end
end

function AtaquesMonstruo.Init()
	carpeta = Instance.new("Folder")
	carpeta.Name = "EfectosMonstruos"
	carpeta.Parent = Workspace
	eventoEmpujon = Remotes.Evento("Empujon")
end

return AtaquesMonstruo
