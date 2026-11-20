--!strict
-- RondaService: ciclo de la partida con oleadas infinitas de dificultad creciente.
--   Preparación → Oleada N (aparecen monstruos poco a poco) → todos derrotados → bono + reparación → descanso → Oleada N+1…
--   Cada "CadaCuantasJefe" oleadas aparece además un jefe; al vencerlo se reconstruyen los edificios caídos.
--   Si caen los 5 edificios: derrota → recompensa según la oleada alcanzada (+ bono si es récord personal)
--   → a los TiempoReinicio s se restaura la ciudad y se REANUDA desde el último punto de control (6, 11, 16…).
--   La dificultad (cantidad, vida y daño de monstruos) se ajusta a cuántas heroínas hay en la ciudad.
-- Atributos en ReplicatedStorage: Oleada, EstadoPartida, CuentaAtras, PuntoControl.
-- Atributo del jugador: MejorOleada (récord personal, lo guarda DatosService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Juego = require(Shared.Config.Juego)
local Monstruos = require(Shared.Config.Monstruos)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local EdificioService = require(script.Parent.EdificioService)
local HeroinaService = require(script.Parent.HeroinaService)
local MonstruoService = require(script.Parent.MonstruoService)

type EstadoPartida = "Preparacion" | "Oleada" | "Descanso" | "Derrota"
type Ajuste = Types.AjusteDificultad

local COLOR_OLEADA = Color3.fromRGB(255, 110, 199)
local COLOR_JEFE = Color3.fromRGB(255, 60, 60)
local COLOR_EXITO = Color3.fromRGB(80, 255, 140)
local COLOR_RECORD = Color3.fromRGB(255, 215, 60)
local COLOR_CONTROL = Color3.fromRGB(120, 200, 255)

-- Cada partida tiene un id; al perder se incrementa y el ciclo anterior se detiene solo.
local partidaActual = 0
local aleatorio = Random.new()
local eventoAnuncio: RemoteEvent
-- Jugadoras que superaron su récord durante la partida actual (para el bono al final).
local recordEnPartida: { [Player]: boolean } = {}

local RondaService = {}

local function anunciar(titulo: string, subtitulo: string, color: Color3)
	eventoAnuncio:FireAllClients(titulo, subtitulo, color)
end

local function establecerEstado(estado: EstadoPartida)
	ReplicatedStorage:SetAttribute("EstadoPartida", estado)
end

-- Heroínas que están jugando en la ciudad (no en el lobby).
local function jugadorasEnCiudad(): { Player }
	local lista = {}
	for _, jugador in Players:GetPlayers() do
		if jugador:GetAttribute("EnCiudad") == true then
			table.insert(lista, jugador)
		end
	end
	return lista
end

-- Ajuste de dificultad según cuántas heroínas hay en la ciudad (mínimo 1).
local function ajusteActual(): Ajuste
	local tabla = Juego.Oleadas.AjusteJugadoras
	local n = math.clamp(#jugadorasEnCiudad(), 1, #tabla)
	return tabla[n]
end

local function mejorOleada(jugador: Player): number
	local valor = jugador:GetAttribute("MejorOleada")
	return if typeof(valor) == "number" then valor else 0
end

-- Primera oleada desde la que se reanuda tras perder, según las oleadas ya superadas.
local function puntoDeControl(oleadasSuperadas: number): number
	local cada = Juego.Oleadas.CadaCuantasPuntoControl
	return math.floor(math.max(oleadasSuperadas, 0) / cada) * cada + 1
end

-- Espera mostrando la cuenta atrás. Devuelve false si la partida terminó mientras tanto.
local function cuentaAtras(segundos: number, id: number): boolean
	for restante = segundos, 1, -1 do
		if id ~= partidaActual then
			return false
		end
		ReplicatedStorage:SetAttribute("CuentaAtras", restante)
		task.wait(1)
	end
	ReplicatedStorage:SetAttribute("CuentaAtras", 0)
	return id == partidaActual
end

local function elegirTipo(oleada: number): Types.MonstruoConfig
	local disponibles: { Types.MonstruoConfig } = {}
	local pesoTotal = 0
	for _, config in Monstruos.Lista do
		if oleada >= config.AparecenDesdeOleada then
			table.insert(disponibles, config)
			pesoTotal += config.Peso
		end
	end
	local tirada = aleatorio:NextNumber(0, pesoTotal)
	for _, config in disponibles do
		tirada -= config.Peso
		if tirada <= 0 then
			return config
		end
	end
	return disponibles[#disponibles]
end

local function puntoAparicion(): Vector3
	local puntos = EdificioService.PuntosAparicionMonstruos()
	local base = puntos[aleatorio:NextInteger(1, #puntos)]
	return base + Vector3.new(aleatorio:NextNumber(-8, 8), 0, aleatorio:NextNumber(-8, 8))
end

-- Actualiza el récord de quien está en la ciudad tras superar `oleada`.
local function registrarRecords(oleada: number)
	for _, jugador in jugadorasEnCiudad() do
		if oleada > mejorOleada(jugador) then
			jugador:SetAttribute("MejorOleada", oleada)
			recordEnPartida[jugador] = true
		end
	end
end

local function jugarOleada(oleada: number, id: number): boolean
	local ajustes = Juego.Oleadas
	local hayJefe = oleada % ajustes.CadaCuantasJefe == 0
	local ajuste = ajusteActual()
	local base = ajustes.MonstruosBase + ajustes.MonstruosPorOleada * (oleada - 1)
	local total = math.max(2, math.round(base * ajuste.Cantidad))

	ReplicatedStorage:SetAttribute("Oleada", oleada)
	establecerEstado("Oleada")
	if hayJefe then
		anunciar(`OLEADA {oleada}`, "¡Se acerca un JEFE gigante! Si lo vencen, la ciudad se reconstruye.", COLOR_JEFE)
	else
		anunciar(`OLEADA {oleada}`, `¡{total} monstruos atacan Sugar Town!`, COLOR_OLEADA)
	end

	local aparecidos = 0
	while aparecidos < total do
		if id ~= partidaActual then
			return false
		end
		if MonstruoService.CantidadVivos() < ajustes.MaxVivosALaVez then
			MonstruoService.Aparecer(elegirTipo(oleada), oleada, false, puntoAparicion(), ajuste)
			aparecidos += 1
		end
		task.wait(ajustes.IntervaloAparicion)
	end

	if hayJefe and id == partidaActual then
		local configJefe = Monstruos.PorId(Monstruos.JefeBase) or Monstruos.Lista[1]
		MonstruoService.Aparecer(configJefe, oleada, true, puntoAparicion(), ajuste)
	end

	while MonstruoService.CantidadVivos() > 0 do
		if id ~= partidaActual then
			return false
		end
		task.wait(0.5)
	end
	return id == partidaActual
end

-- Premios y reparaciones al superar una oleada.
local function alSuperarOleada(oleada: number)
	local ajustes = Juego.Oleadas
	local bono = ajustes.BonoMonedasOleada
	for _, jugador in Players:GetPlayers() do
		HeroinaService.SumarMonedasGanadas(jugador, bono)
	end
	registrarRecords(oleada)

	local esJefe = oleada % ajustes.CadaCuantasJefe == 0
	EdificioService.Reparar(ajustes.ReparacionPorOleada)
	local reconstruidos = if esJefe then EdificioService.Reconstruir(ajustes.ReconstruccionTrasJefe) else 0

	if oleada % ajustes.CadaCuantasPuntoControl == 0 then
		ReplicatedStorage:SetAttribute("PuntoControl", oleada + 1)
	end

	if esJefe then
		local extra = if reconstruidos > 0 then ` · {reconstruidos} edificio(s) reconstruidos` else ""
		anunciar("¡JEFE DERROTADO!", `+{bono} monedas · ✅ Punto de control: oleada {oleada + 1}{extra}`, COLOR_RECORD)
	else
		anunciar("¡OLEADA SUPERADA!", `+{bono} monedas · 🔧 Edificios reparados +{math.round(ajustes.ReparacionPorOleada * 100)} %`, COLOR_EXITO)
	end
end

local function cicloPartida(id: number, desde: number)
	ReplicatedStorage:SetAttribute("Oleada", desde - 1)
	ReplicatedStorage:SetAttribute("PuntoControl", desde)
	establecerEstado("Preparacion")
	if desde > 1 then
		anunciar("¡DE VUELTA AL COMBATE!", `Reanudan desde la oleada {desde} (punto de control)`, COLOR_CONTROL)
	else
		anunciar("SUGAR TOWN", "¡Protejan los 5 edificios de los monstruos!", COLOR_OLEADA)
	end
	if not cuentaAtras(Juego.Oleadas.TiempoPreparacionInicial, id) then
		return
	end

	local oleada = desde - 1
	while id == partidaActual do
		oleada += 1
		if not jugarOleada(oleada, id) then
			return
		end
		alSuperarOleada(oleada)
		establecerEstado("Descanso")
		if not cuentaAtras(Juego.Oleadas.TiempoEntreOleadas, id) then
			return
		end
	end
end

local function iniciarPartida(desde: number)
	partidaActual += 1
	table.clear(recordEnPartida)
	task.spawn(cicloPartida, partidaActual, desde)
end

-- Recompensa al perder: nunca te vas con las manos vacías.
local function recompensarDerrota(oleadaAlcanzada: number)
	local ajustes = Juego.Oleadas
	local superadas = math.max(oleadaAlcanzada - 1, 0)
	for _, jugador in jugadorasEnCiudad() do
		local premio = superadas * ajustes.RecompensaDerrotaPorOleada
		local esRecord = recordEnPartida[jugador] == true
		if esRecord then
			premio += ajustes.BonoNuevoRecord
		end
		if premio > 0 then
			HeroinaService.SumarMonedasGanadas(jugador, premio)
		end
		if esRecord then
			eventoAnuncio:FireClient(
				jugador,
				"🏆 ¡NUEVO RÉCORD!",
				`Llegaste a la oleada {mejorOleada(jugador)} · +{premio} monedas`,
				COLOR_RECORD
			)
		elseif premio > 0 then
			eventoAnuncio:FireClient(
				jugador,
				"Recompensa de resistencia",
				`Superaste {superadas} oleada(s) · +{premio} monedas · Récord: {mejorOleada(jugador)}`,
				COLOR_CONTROL
			)
		end
	end
end

local function alCaerLaCiudad()
	local valor = ReplicatedStorage:GetAttribute("Oleada")
	local oleadaAlcanzada = if typeof(valor) == "number" then valor else 1
	local desde = puntoDeControl(oleadaAlcanzada - 1)
	partidaActual += 1 -- detiene el ciclo en curso
	establecerEstado("Derrota")
	anunciar(
		"¡LA CIUDAD HA CAÍDO!",
		`Resistieron hasta la oleada {oleadaAlcanzada}. En {Juego.TiempoReinicio} s vuelven desde la oleada {desde}…`,
		COLOR_JEFE
	)

	local id = partidaActual
	task.delay(2.5, recompensarDerrota, oleadaAlcanzada) -- tras el anuncio de derrota
	task.spawn(function()
		cuentaAtras(Juego.TiempoReinicio, id)
		if id ~= partidaActual then
			return
		end
		MonstruoService.EliminarTodos()
		EdificioService.Restaurar()
		for _, jugador in Players:GetPlayers() do
			jugador:LoadCharacter() -- todas vuelven a la plaza central
		end
		iniciarPartida(desde)
	end)
end

function RondaService.Init()
	eventoAnuncio = Remotes.Evento("Anuncio")
	EdificioService.AlCaerTodos(alCaerLaCiudad)
	ReplicatedStorage:SetAttribute("Oleada", 0)
	ReplicatedStorage:SetAttribute("CuentaAtras", 0)
	ReplicatedStorage:SetAttribute("PuntoControl", 1)
	establecerEstado("Preparacion")
	Players.PlayerRemoving:Connect(function(jugador)
		recordEnPartida[jugador] = nil
	end)
end

function RondaService.Start()
	iniciarPartida(1)
end

return RondaService
