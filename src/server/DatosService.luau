--!strict
-- DatosService: guarda y carga el progreso con DataStoreService + leaderstats.
-- Guarda: Monedas, Derrotados, Nivel, Experiencia, Impulsos, MejorOleada, Arquetipo, Mejoras ("Mejora_*") y Armas desbloqueadas con monedas ("Arma_*").
-- Seguridad:
--   • Todas las llamadas van en pcall con reintentos.
--   • Si la CARGA falla, ese jugador NO se guarda (así nunca se sobrescriben datos buenos con 0).
--   • Lo leído se sanea (tipos, NaN, negativos) antes de aplicarlo.
--   • En Studio sin publicar o sin "Enable Studio Access to API Services" se desactiva con un aviso
--     informativo (print), sin errores en el Output; el juego funciona igual, solo no persiste.
-- Fuente de verdad durante la partida: los atributos del jugador (los modifican los demás servicios).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Armas = require(Shared.Config.Armas)
local Heroinas = require(Shared.Config.Heroinas)
local Mejoras = require(Shared.Config.Mejoras)

local NOMBRE_ALMACEN = "SugarTown_Progreso_v1"
local VERSION_DATOS = 1
local INTERVALO_AUTOGUARDADO = 120 -- segundos
local REINTENTOS = 3
local ESPERA_MAXIMA_CIERRE = 25 -- segundos (BindToClose permite 30)

type Datos = {
	Version: number,
	Monedas: number,
	Derrotados: number,
	Nivel: number,
	Experiencia: number,
	Impulsos: number,
	MejorOleada: number,
	Arquetipo: string,
	Mejoras: { [string]: number },
	Armas: { string }, -- claves de armas desbloqueadas con monedas
}

local almacen: DataStore? = nil
local cargados: { [Player]: boolean } = {} -- true solo si la carga terminó bien
local conexiones: { [Player]: { RBXScriptConnection } } = {}

local DatosService = {}

local function clave(jugador: Player): string
	return `jugador_{jugador.UserId}`
end

local function desactivarGuardado(motivo: string)
	if almacen then
		almacen = nil
		print(`[DatosService] Guardado desactivado: {motivo}. El juego funciona, pero el progreso no persiste.`)
	end
end

-- Errores que no se arreglan reintentando (Studio sin acceso a la API, lugar sin publicar…)
local function esErrorDeAcceso(mensaje: string): boolean
	return string.find(mensaje, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(mensaje, "Studio access to APIs is not allowed", 1, true) ~= nil
		or string.find(mensaje, "403", 1, true) ~= nil
		or string.find(mensaje, "must publish", 1, true) ~= nil
end

local function conReintentos(descripcion: string, funcion: () -> any): (boolean, any)
	for intento = 1, REINTENTOS do
		local ok, resultado = pcall(funcion)
		if ok then
			return true, resultado
		end
		local mensaje = tostring(resultado)
		if esErrorDeAcceso(mensaje) then
			desactivarGuardado("sin acceso a DataStore (en Studio: Configuración del juego → Seguridad → Enable Studio Access to API Services)")
			return false, nil
		end
		if intento == REINTENTOS then
			warn(`[DatosService] {descripcion} falló tras {REINTENTOS} intentos: {mensaje}`)
			return false, nil
		end
		task.wait(intento * 2)
	end
	return false, nil
end

local function entero(valor: unknown, porDefecto: number, minimo: number): number
	if typeof(valor) == "number" and valor == valor and math.abs(valor :: number) ~= math.huge then
		return math.max(minimo, math.floor(valor :: number))
	end
	return porDefecto
end

local function sanear(bruto: unknown): Datos
	local t: { [any]: any } = if typeof(bruto) == "table" then bruto :: any else {}
	local mejoras: { [string]: number } = {}
	if typeof(t.Mejoras) == "table" then
		for nombre, nivel in t.Mejoras do
			if typeof(nombre) == "string" and string.sub(nombre, 1, #Mejoras.PrefijoAtributo) == Mejoras.PrefijoAtributo then
				mejoras[nombre] = math.min(entero(nivel, 0, 0), 100)
			end
		end
	end
	local armas: { string } = {}
	if typeof(t.Armas) == "table" then
		for _, claveArma in t.Armas do
			if Armas.PorClave(claveArma) and not table.find(armas, claveArma) then
				table.insert(armas, claveArma)
			end
		end
	end
	return {
		Armas = armas,
		Version = VERSION_DATOS,
		Monedas = entero(t.Monedas, 0, 0),
		Derrotados = entero(t.Derrotados, 0, 0),
		Nivel = entero(t.Nivel, 1, 1),
		Experiencia = entero(t.Experiencia, 0, 0),
		Impulsos = math.min(entero(t.Impulsos, 0, 0), 100),
		MejorOleada = math.min(entero(t.MejorOleada, 0, 0), 100000), -- campo nuevo: datos antiguos → 0
		Arquetipo = if Heroinas.EsValido(t.Arquetipo) then t.Arquetipo else Heroinas.PorDefecto,
		Mejoras = mejoras,
	}
end

local function aplicar(jugador: Player, datos: Datos)
	jugador:SetAttribute("Monedas", datos.Monedas)
	jugador:SetAttribute("Derrotados", datos.Derrotados)
	jugador:SetAttribute("Nivel", datos.Nivel)
	jugador:SetAttribute("Experiencia", datos.Experiencia)
	jugador:SetAttribute("Impulsos", datos.Impulsos)
	jugador:SetAttribute("MejorOleada", datos.MejorOleada)
	jugador:SetAttribute("Arquetipo", datos.Arquetipo)
	for nombre, nivel in datos.Mejoras do
		jugador:SetAttribute(nombre, nivel)
	end
	for _, claveArma in datos.Armas do
		jugador:SetAttribute(Armas.PrefijoAtributo .. claveArma, true)
	end
end

local function recoger(jugador: Player): Datos
	local mejoras: { [string]: number } = {}
	for nombre, valor in jugador:GetAttributes() do
		if string.sub(nombre, 1, #Mejoras.PrefijoAtributo) == Mejoras.PrefijoAtributo and typeof(valor) == "number" then
			mejoras[nombre] = valor
		end
	end
	local datos = jugador:GetAttributes()
	datos.Mejoras = mejoras
	local armas = {}
	for _, arma in Armas.Lista do
		if jugador:GetAttribute(Armas.PrefijoAtributo .. arma.Clave) == true then
			table.insert(armas, arma.Clave)
		end
	end
	datos.Armas = armas
	return sanear(datos)
end

-- ─── leaderstats ─────────────────────────────────────────────────────────────

local function crearLeaderstats(jugador: Player)
	local carpeta = Instance.new("Folder")
	carpeta.Name = "leaderstats"

	local lista: { RBXScriptConnection } = {}
	conexiones[jugador] = lista

	-- { atributo, nombre visible en la lista de jugadores }
	for _, par in { { "Monedas", "Monedas" }, { "Derrotados", "Derrotados" }, { "MejorOleada", "Récord" } } do
		local atributo, visible = par[1], par[2]
		local valor = Instance.new("IntValue")
		valor.Name = visible
		valor.Parent = carpeta
		local function sincronizar()
			valor.Value = entero(jugador:GetAttribute(atributo), 0, 0)
		end
		sincronizar()
		table.insert(lista, jugador:GetAttributeChangedSignal(atributo):Connect(sincronizar))
	end

	carpeta.Parent = jugador
end

-- ─── Carga / guardado ────────────────────────────────────────────────────────

local function cargar(jugador: Player)
	local almacenActual = almacen
	if not almacenActual then
		return
	end
	local ok, bruto = conReintentos(`Cargar a {jugador.Name}`, function()
		return almacenActual:GetAsync(clave(jugador))
	end)
	if jugador.Parent == nil then
		return -- se fue mientras cargaba
	end
	if ok then
		aplicar(jugador, sanear(bruto))
		cargados[jugador] = true
	end
end

function DatosService.Guardar(jugador: Player): boolean
	local almacenActual = almacen
	if not almacenActual or not cargados[jugador] then
		return false
	end
	local datos = recoger(jugador)
	local ok = conReintentos(`Guardar a {jugador.Name}`, function()
		almacenActual:SetAsync(clave(jugador), datos, { jugador.UserId })
	end)
	return ok
end

local function alEntrar(jugador: Player)
	crearLeaderstats(jugador)
	cargar(jugador)
end

local function alSalir(jugador: Player)
	DatosService.Guardar(jugador)
	cargados[jugador] = nil
	local lista = conexiones[jugador]
	if lista then
		for _, conexion in lista do
			conexion:Disconnect()
		end
	end
	conexiones[jugador] = nil
end

function DatosService.Init()
	if game.PlaceId == 0 then
		print("[DatosService] Lugar sin publicar: el progreso no se guardará (normal al probar en Studio).")
		return
	end
	local ok, resultado = pcall(function()
		return DataStoreService:GetDataStore(NOMBRE_ALMACEN)
	end)
	if ok then
		almacen = resultado
	else
		print(`[DatosService] DataStore no disponible: {resultado}`)
	end
end

function DatosService.Start()
	Players.PlayerAdded:Connect(alEntrar)
	Players.PlayerRemoving:Connect(alSalir)
	for _, jugador in Players:GetPlayers() do
		task.spawn(alEntrar, jugador)
	end

	-- Autoguardado periódico
	task.spawn(function()
		while true do
			task.wait(INTERVALO_AUTOGUARDADO)
			for _, jugador in Players:GetPlayers() do
				task.spawn(DatosService.Guardar, jugador)
			end
		end
	end)

	-- Al cerrar el servidor: guardar a todos en paralelo y esperar (con límite)
	game:BindToClose(function()
		if not almacen then
			return
		end
		local pendientes = 0
		for _, jugador in Players:GetPlayers() do
			pendientes += 1
			task.spawn(function()
				DatosService.Guardar(jugador)
				pendientes -= 1
			end)
		end
		local limite = os.clock() + ESPERA_MAXIMA_CIERRE
		while pendientes > 0 and os.clock() < limite do
			task.wait(0.2)
		end
	end)

	if RunService:IsStudio() and almacen then
		print("[DatosService] Lugar publicado: se intenta guardar también en Studio (si no hay permiso, se desactiva solo).")
	end
end

return DatosService
