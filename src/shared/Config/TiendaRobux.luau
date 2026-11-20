--!strict
-- Artículos de la tienda con Robux. Solo datos.
--
-- ⚠️ Los IDs reales se crean en el Creator Dashboard (create.roblox.com → tu experiencia →
--    Monetización → Pases / Productos para desarrolladores) y se pegan aquí.
--    Mientras un Id valga 0:
--      • En Roblox Studio → la compra se SIMULA gratis (modo de prueba) para probar todo el flujo.
--      • En el juego publicado → el artículo aparece como "Próximamente" y no se puede comprar.
--    Con Ids reales, Studio también muestra la ventana de compra de prueba de Roblox (sin cobrar Robux).

export type TipoArticulo = "Pase" | "Producto"

export type ArticuloConfig = {
	Clave: string, -- identificador interno (lo envía el cliente)
	Tipo: TipoArticulo,
	Id: number, -- GamePassId o ProductId
	Nombre: string,
	Icono: string,
	Descripcion: string,
	PrecioReferencia: number, -- Robux (solo para mostrar; el precio real lo fija Roblox)
	Monedas: number?, -- productos de monedas
	OcultoEnTienda: boolean?,
	Arma: boolean?, -- arma de Config/Armas (también se puede desbloquear con monedas) -- no aparece en la tienda (se ofrece en otro momento, p. ej. al ser derrotada)
}

local ARTICULOS: { ArticuloConfig } = {
	{
		Clave = "VueloSupersonico",
		Tipo = "Pase",
		Id = 2093176018,
		Nombre = "Vuelo Supersónico x2",
		Icono = "🚀",
		Descripcion = "Duplica tu velocidad de vuelo y turbo para siempre.",
		PrecioReferencia = 149,
	},
	{
		Clave = "HeroinaVIP",
		Tipo = "Pase",
		Id = 2094526011,
		Nombre = "Pase VIP",
		Icono = "👑",
		Descripcion = "+50% de monedas ganadas, aura dorada y título VIP.",
		PrecioReferencia = 299,
	},
	{
		Clave = "LanzadorDulces",
		Tipo = "Pase",
		Id = 2093062007,
		Nombre = "Lanzador de Dulces",
		Icono = "🍬",
		Descripcion = "Arma: dispara caramelos que estallan. [T]",
		PrecioReferencia = 99,
		Arma = true,
	},
	{
		Clave = "MartilloCaramelo",
		Tipo = "Pase",
		Id = 2092750019,
		Nombre = "Martillo de Caramelo",
		Icono = "🍭",
		Descripcion = "Arma: golpe gigante que aplasta a varios monstruos.",
		PrecioReferencia = 149,
		Arma = true,
	},
	{
		Clave = "VaritaEstrellas",
		Tipo = "Pase",
		Id = 2093505989,
		Nombre = "Varita de Estrellas",
		Icono = "⭐",
		Descripcion = "Arma: lanza estrellas que persiguen a los monstruos.",
		PrecioReferencia = 199,
		Arma = true,
	},
	{
		Clave = "Monedas500",
		Tipo = "Producto",
		Id = 3733514512,
		Nombre = "+500 Monedas",
		Icono = "💰",
		Descripcion = "Un saco de monedas para tus mejoras.",
		PrecioReferencia = 49,
		Monedas = 500,
	},
	{
		Clave = "Monedas2500",
		Tipo = "Producto",
		Id = 3733514609,
		Nombre = "+2500 Monedas",
		Icono = "💰",
		Descripcion = "¡Un cofre enorme de monedas!",
		PrecioReferencia = 199,
		Monedas = 2500,
	},
	{
		Clave = "BombaEstelar",
		Tipo = "Producto",
		Id = 3733514710,
		Nombre = "Bomba de Esencia Estelar",
		Icono = "💣",
		Descripcion = "Elimina al instante a todos los monstruos de la oleada.",
		PrecioReferencia = 25,
	},
	{
		Clave = "Revivir",
		Tipo = "Producto",
		Id = 3733514404,
		Nombre = "Revivir",
		Icono = "💖",
		Descripcion = "Vuelve a la batalla con toda la vida.",
		PrecioReferencia = 25,
		OcultoEnTienda = true,
	},
}

local PorClave: { [string]: ArticuloConfig } = {}
for _, articulo in ARTICULOS do
	PorClave[articulo.Clave] = table.freeze(articulo)
end

local TiendaRobux = {
	Lista = table.freeze(ARTICULOS),
	PrefijoPase = "Pase_", -- atributo booleano del jugador: "Pase_<Clave>"
}

function TiendaRobux.PorClave(clave: unknown): ArticuloConfig?
	if typeof(clave) ~= "string" then
		return nil
	end
	return PorClave[clave]
end

function TiendaRobux.PorProductId(productId: number): ArticuloConfig?
	if productId == 0 then
		return nil
	end
	for _, articulo in ARTICULOS do
		if articulo.Tipo == "Producto" and articulo.Id == productId then
			return articulo
		end
	end
	return nil
end

function TiendaRobux.AtributoPase(clave: string): string
	return TiendaRobux.PrefijoPase .. clave
end

function TiendaRobux.TienePase(jugador: Player, clave: string): boolean
	return jugador:GetAttribute(TiendaRobux.AtributoPase(clave)) == true
end

return TiendaRobux
