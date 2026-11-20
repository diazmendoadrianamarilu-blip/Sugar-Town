--!strict
-- Mejoras compradas con monedas. Son POR HEROÍNA: cada arquetipo tiene sus propios niveles.
-- El nivel se guarda en el atributo del jugador "Mejora_<Arquetipo>_<Tipo>" (lo escribe solo el servidor).

local Types = require(script.Parent.Parent.Types)

type TipoMejora = Types.TipoMejora
type MejoraConfig = Types.MejoraConfig

local LISTA: { [TipoMejora]: MejoraConfig } = {
	Dano = {
		Id = "Dano",
		Nombre = "Daño",
		Icono = "💥",
		Descripcion = "+10% de daño en todos tus poderes",
		NivelMaximo = 10,
		CostoBase = 30,
		CostoPorNivel = 25,
		BonoPorNivel = 0.10,
	},
	Vuelo = {
		Id = "Vuelo",
		Nombre = "Vuelo",
		Icono = "💨",
		Descripcion = "+8% de velocidad de vuelo y turbo",
		NivelMaximo = 10,
		CostoBase = 20,
		CostoPorNivel = 20,
		BonoPorNivel = 0.08,
	},
}
for _, config in LISTA do
	table.freeze(config)
end
table.freeze(LISTA)

local ORDEN: { TipoMejora } = { "Dano", "Vuelo" }

local Mejoras = {
	Lista = LISTA,
	Orden = table.freeze(ORDEN),
	PrefijoAtributo = "Mejora_",
}

function Mejoras.EsTipo(valor: unknown): boolean
	return valor == "Dano" or valor == "Vuelo"
end

function Mejoras.Atributo(arquetipo: string, tipo: TipoMejora): string
	return `{Mejoras.PrefijoAtributo}{arquetipo}_{tipo}`
end

function Mejoras.Nivel(jugador: Player, arquetipo: string, tipo: TipoMejora): number
	local valor = jugador:GetAttribute(Mejoras.Atributo(arquetipo, tipo))
	return if typeof(valor) == "number" then math.clamp(math.floor(valor), 0, LISTA[tipo].NivelMaximo) else 0
end

-- Coste de comprar el SIGUIENTE nivel.
function Mejoras.Costo(tipo: TipoMejora, nivelActual: number): number
	local config = LISTA[tipo]
	return config.CostoBase + config.CostoPorNivel * nivelActual
end

function Mejoras.Multiplicador(jugador: Player, arquetipo: string, tipo: TipoMejora): number
	return 1 + LISTA[tipo].BonoPorNivel * Mejoras.Nivel(jugador, arquetipo, tipo)
end

return Mejoras
