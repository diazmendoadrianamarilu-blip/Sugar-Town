--!strict
-- Poderes de cada arquetipo. Solo datos: la lógica está en CombateService (servidor)
-- y los visuales en EfectosController (cliente).

local Types = require(script.Parent.Parent.Types)
local Heroinas = require(script.Parent.Heroinas)
local Armas = require(script.Parent.Armas)

type PoderConfig = Types.PoderConfig
type PoderesHeroina = Types.PoderesHeroina
type ArquetipoId = Types.ArquetipoId
type Ranura = Types.Ranura

-- Progresión (ajustable): nivel 1 = solo el combo cuerpo a cuerpo (Clic / GOLPE).
--   Q (Secundario) = RAYO LÁSER del color de la heroína, desde NIVEL_LASER.
--   E (Primario)   = poder único de cada heroína, desde NIVEL_PODER_UNICO.
local NIVEL_LASER = 3
local NIVEL_PODER_UNICO = 5

-- Antes del nivel del láser permanente, desde NivelDesde se puede usar el láser POR TIEMPO:
-- al usarlo se abre una ventana de Activo s (dispara con su enfriamiento normal); al acabar se
-- apaga y recarga durante Recarga s. Desde NIVEL_LASER ya no tiene límite de tiempo.
local LASER_TEMPORAL = table.freeze({
	NivelDesde = 2,
	Activo = 120,
	Recarga = 60,
})

-- Rayo láser: se carga (Carga s) y dispara un haz recto que daña a TODOS los monstruos de la línea.
local function laser(id: string, nombre: string, icono: string, color: Color3): PoderConfig
	return {
		Id = id,
		Nombre = nombre,
		Icono = icono,
		Tipo = "Laser",
		Color = color,
		Enfriamiento = 3,
		Dano = 40,
		Alcance = 120, -- largo del haz
		Radio = 3, -- grosor de la zona que daña
		Duracion = 0.45, -- lo que dura el haz en pantalla
		Cantidad = 1,
		Dispersion = 0,
		Empuje = 0,
		Ralentizacion = 1,
		NivelRequerido = NIVEL_LASER,
		Carga = 0.5,
	}
end

local LISTA: { [ArquetipoId]: PoderesHeroina } = {
	Fuerza = {
		Primario = {
			Id = "OndaChoque",
			Nombre = "Onda de Choque",
			Icono = "💥",
			Tipo = "Onda",
			Color = Color3.fromRGB(255, 90, 140),
			Enfriamiento = 6,
			Dano = 55,
			Alcance = 0,
			Radio = 22,
			Duracion = 0.5,
			Cantidad = 1,
			Dispersion = 0,
			Empuje = 90,
			Ralentizacion = 1,
			NivelRequerido = NIVEL_PODER_UNICO,
			Carga = 0,
		},
		Secundario = laser("LaserCarmesi", "Láser Carmesí", "🔴", Color3.fromRGB(255, 40, 110)),
	},
	Velocidad = {
		Primario = {
			Id = "ImpulsoRelampago",
			Nombre = "Impulso Relámpago",
			Icono = "⚡",
			Tipo = "Impulso",
			Color = Color3.fromRGB(120, 230, 255),
			Enfriamiento = 4,
			Dano = 30,
			Alcance = 45, -- distancia del impulso
			Radio = 5, -- grosor de la zona que golpea
			Duracion = 0.3,
			Cantidad = 1,
			Dispersion = 0,
			Empuje = 0,
			Ralentizacion = 1,
			NivelRequerido = NIVEL_PODER_UNICO,
			Carga = 0,
		},
		Secundario = laser("LaserCeleste", "Láser Celeste", "🔵", Color3.fromRGB(40, 190, 255)),
	},
	Estrategia = {
		Primario = {
			Id = "EsferaEscudo",
			Nombre = "Esfera Escudo",
			Icono = "🛡️",
			Tipo = "Escudo",
			Color = Color3.fromRGB(60, 255, 130),
			Enfriamiento = 10,
			Dano = 0,
			Alcance = 0,
			Radio = 18, -- protege también a las aliadas dentro de este radio
			Duracion = 5,
			Cantidad = 1,
			Dispersion = 0,
			Empuje = 0,
			Ralentizacion = 1,
			NivelRequerido = NIVEL_PODER_UNICO,
			Carga = 0,
		},
		Secundario = laser("LaserEsmeralda", "Láser Esmeralda", "🟢", Color3.fromRGB(50, 235, 120)),
	},
}

local POR_ID: { [string]: PoderConfig } = {}
for _, poderes in LISTA do
	for _, poder in { poderes.Primario, poderes.Secundario } do
		assert(POR_ID[poder.Id] == nil, `Id de poder duplicado: {poder.Id}`)
		POR_ID[poder.Id] = table.freeze(poder)
	end
	table.freeze(poderes)
end
table.freeze(LISTA)

-- Poder especial común a todas: se carga con ⭐ Esencia Estelar (tecla R)
local ESPECIAL: PoderConfig = table.freeze({
	Id = "EstallidoEstelar",
	Nombre = "Estallido Estelar",
	Icono = "⭐",
	Tipo = "Onda",
	Color = Color3.fromRGB(255, 215, 60),
	Enfriamiento = 1,
	Dano = 260,
	Alcance = 0,
	Radio = 75,
	Duracion = 0.8,
	Cantidad = 1,
	Dispersion = 0,
	Empuje = 120,
	Ralentizacion = 1,
	NivelRequerido = 1,
	Carga = 0,
})
POR_ID[ESPECIAL.Id] = ESPECIAL
-- Armas (Config/Armas): también se buscan por Id para dibujar sus efectos
for _, arma in Armas.Lista do
	POR_ID[arma.Poder.Id] = arma.Poder
end

local Poderes = {
	Especial = ESPECIAL,
	LaserTemporal = LASER_TEMPORAL,
	-- Atributos del jugador (los escribe SOLO el servidor; hora de GetServerTimeNow)
	AtributoLaserActivo = "LaserActivoHasta",
	AtributoLaserRecarga = "LaserRecargaHasta",
	EnergiaMaxima = 100,
	EnergiaPorDano = 1 / 12, -- energía ganada por cada punto de daño hecho
}

function Poderes.EsRanura(valor: unknown): boolean
	return valor == "Primario" or valor == "Secundario"
end

-- Poderes del arquetipo (si el id no es válido, los del arquetipo por defecto).
function Poderes.DeArquetipo(arquetipo: unknown): PoderesHeroina
	return LISTA[Heroinas.Obtener(arquetipo).Id]
end

function Poderes.Obtener(arquetipo: unknown, ranura: Ranura): PoderConfig
	local poderes = Poderes.DeArquetipo(arquetipo)
	return if ranura == "Primario" then poderes.Primario else poderes.Secundario
end

-- Nivel de la jugadora (atributo "Nivel" que solo escribe el servidor).
function Poderes.NivelDe(jugador: Player): number
	local nivel = jugador:GetAttribute("Nivel")
	return if typeof(nivel) == "number" then math.max(1, math.floor(nivel)) else 1
end

function Poderes.Desbloqueado(poder: PoderConfig, nivel: number): boolean
	return nivel >= poder.NivelRequerido
end

-- Nivel a partir del cual se puede usar (aunque sea por tiempo).
function Poderes.NivelMinimo(poder: PoderConfig): number
	if poder.Tipo == "Laser" then
		return math.min(poder.NivelRequerido, LASER_TEMPORAL.NivelDesde)
	end
	return poder.NivelRequerido
end

export type EstadoUso = "Bloqueado" | "Permanente" | "Listo" | "Activo" | "Recarga"

-- Estado de uso de un poder para un jugador. "restante" = segundos que quedan de la ventana
-- activa o de la recarga. "ahora" = Workspace:GetServerTimeNow().
function Poderes.EstadoUso(jugador: Player, poder: PoderConfig, ahora: number): (EstadoUso, number)
	local nivel = Poderes.NivelDe(jugador)
	if nivel >= poder.NivelRequerido then
		return "Permanente", 0
	end
	if poder.Tipo ~= "Laser" or nivel < LASER_TEMPORAL.NivelDesde then
		return "Bloqueado", 0
	end
	local activo = jugador:GetAttribute(Poderes.AtributoLaserActivo)
	local recarga = jugador:GetAttribute(Poderes.AtributoLaserRecarga)
	local activoHasta = if typeof(activo) == "number" then activo else 0
	local recargaHasta = if typeof(recarga) == "number" then recarga else 0
	if ahora < activoHasta then
		return "Activo", activoHasta - ahora
	elseif ahora < recargaHasta then
		return "Recarga", recargaHasta - ahora
	end
	return "Listo", 0
end

-- Siguiente poder que se desbloquea por encima de "nivel" (nil si ya los tiene todos).
function Poderes.ProximoDesbloqueo(arquetipo: unknown, nivel: number): (PoderConfig?, Ranura?)
	local poderes = Poderes.DeArquetipo(arquetipo)
	local mejor: PoderConfig? = nil
	local ranuraMejor: Ranura? = nil
	for _, ranura: Ranura in { "Secundario", "Primario" } do
		local poder = if ranura == "Primario" then poderes.Primario else poderes.Secundario
		local minimo = Poderes.NivelMinimo(poder)
		if minimo > nivel and (mejor == nil or minimo < Poderes.NivelMinimo(mejor :: PoderConfig)) then
			mejor, ranuraMejor = poder, ranura
		end
	end
	return mejor, ranuraMejor
end

-- Poder que se desbloquea EXACTAMENTE en este nivel (para el anuncio al subir de nivel).
-- "temporal" = se desbloquea en modo por tiempo (láser antes de su nivel permanente).
function Poderes.DesbloqueadoEn(arquetipo: unknown, nivel: number): (PoderConfig?, Ranura?, boolean)
	local poderes = Poderes.DeArquetipo(arquetipo)
	for _, ranura: Ranura in { "Secundario", "Primario" } do
		local poder = if ranura == "Primario" then poderes.Primario else poderes.Secundario
		if poder.NivelRequerido == nivel then
			return poder, ranura, false
		elseif Poderes.NivelMinimo(poder) == nivel then
			return poder, ranura, true
		end
	end
	return nil, nil, false
end

function Poderes.PorId(id: unknown): PoderConfig?
	if typeof(id) ~= "string" then
		return nil
	end
	return POR_ID[id]
end

return Poderes
