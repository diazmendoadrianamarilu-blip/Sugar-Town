--!strict
-- Armas de fantasía (no hay armas realistas). Solo datos.
-- Cada arma se consigue de DOS formas (nunca es obligatorio pagar):
--   • Pase de Robux de Config/TiendaRobux (misma Clave) → atributo "Pase_<Clave>".
--   • Con monedas, a partir de NivelMonedas → atributo "Arma_<Clave>" (se guarda en DataStore).
-- La lógica de daño está en CombateService (remote "UsarArma"), los visuales en EfectosController.

local Types = require(script.Parent.Parent.Types)

type PoderConfig = Types.PoderConfig

export type ArmaConfig = {
	Clave: string, -- coincide con la Clave del pase en TiendaRobux
	Nombre: string,
	Icono: string,
	NivelMonedas: number, -- nivel desde el que se puede comprar con monedas
	CostoMonedas: number,
	Poder: PoderConfig,
}

local function poder(datos: { [string]: any }): PoderConfig
	local base: { [string]: any } = {
		Enfriamiento = 1,
		Dano = 0,
		Alcance = 0,
		Radio = 0,
		Duracion = 0.3,
		Cantidad = 1,
		Dispersion = 0,
		Empuje = 0,
		Ralentizacion = 1,
		NivelRequerido = 1,
		Carga = 0,
	}
	for k, v in datos do
		base[k] = v
	end
	return table.freeze(base) :: any
end

local LISTA: { ArmaConfig } = {
	{
		Clave = "LanzadorDulces",
		Nombre = "Lanzador de Dulces",
		Icono = "🍬",
		NivelMonedas = 6,
		CostoMonedas = 1500,
		Poder = poder({
			Id = "ArmaLanzadorDulces",
			Nombre = "Lanzador de Dulces",
			Icono = "🍬",
			Tipo = "Dulce",
			Color = Color3.fromRGB(255, 120, 200),
			Enfriamiento = 0.45,
			Dano = 28,
			Alcance = 160,
			Radio = 2,
			Duracion = 0.3, -- tiempo de vuelo del caramelo
		}),
	},
	{
		Clave = "MartilloCaramelo",
		Nombre = "Martillo de Caramelo",
		Icono = "🍭",
		NivelMonedas = 8,
		CostoMonedas = 2500,
		Poder = poder({
			Id = "ArmaMartilloCaramelo",
			Nombre = "Martillo de Caramelo",
			Icono = "🍭",
			Tipo = "Martillo",
			Color = Color3.fromRGB(255, 80, 120),
			Enfriamiento = 2.5,
			Dano = 75,
			Alcance = 7, -- distancia delante de la heroína donde cae el golpe
			Radio = 18,
			Duracion = 0.35,
			Empuje = 70,
		}),
	},
	{
		Clave = "VaritaEstrellas",
		Nombre = "Varita de Estrellas",
		Icono = "⭐",
		NivelMonedas = 10,
		CostoMonedas = 4000,
		Poder = poder({
			Id = "ArmaVaritaEstrellas",
			Nombre = "Varita de Estrellas",
			Icono = "⭐",
			Tipo = "Estrellas",
			Color = Color3.fromRGB(255, 220, 70),
			Enfriamiento = 1.6,
			Dano = 32,
			Alcance = 110, -- busca monstruos hasta esta distancia
			Cantidad = 3, -- estrellas (una por monstruo, los más cercanos)
			Duracion = 0.5,
		}),
	},
}

local PorClave: { [string]: ArmaConfig } = {}
for _, arma in LISTA do
	PorClave[arma.Clave] = table.freeze(arma)
end

local Armas = {
	Lista = table.freeze(LISTA),
	PrefijoAtributo = "Arma_", -- desbloqueada con monedas: atributo booleano "Arma_<Clave>"
}

function Armas.PorClave(clave: unknown): ArmaConfig?
	if typeof(clave) ~= "string" then
		return nil
	end
	return PorClave[clave]
end

-- ¿La tiene? (pase de Robux o desbloqueada con monedas). Atributos que solo escribe el servidor.
function Armas.Tiene(jugador: Player, clave: string): boolean
	return jugador:GetAttribute("Pase_" .. clave) == true or jugador:GetAttribute(Armas.PrefijoAtributo .. clave) == true
end

return Armas
