--!strict
-- Configuración de los 3 arquetipos de heroína. Solo datos: sin lógica de juego.

local Types = require(script.Parent.Parent.Types)

type HeroinaConfig = Types.HeroinaConfig
type ArquetipoId = Types.ArquetipoId

-- Trajes de heroína: artículos PÚBLICOS del catálogo de avatares de Roblox (sin franquicias).
-- Se aplican con HumanoidDescription al llegar a la ciudad; la cabeza, la cara y el tono de piel
-- del jugador se conservan. Para cambiar una pieza basta con cambiar su id aquí (0 = sin pieza).
-- Cuerpo: paquete gratuito oficial "Mujer" de Roblox (bundle 239), solo torso, brazos y piernas.
local CUERPO_ESTANDAR: Types.CuerpoCatalogo = table.freeze({
	Torso = 86499666,
	BrazoIzquierdo = 86499716,
	BrazoDerecho = 86499698,
	PiernaIzquierda = 86499753,
	PiernaDerecha = 86499793,
})

local LISTA: { [ArquetipoId]: HeroinaConfig } = {
	Fuerza = {
		Id = "Fuerza",
		Nombre = "Fuerza",
		Descripcion = "Golpes devastadores y ataques de área.",
		Icono = "💥",
		ColorPrincipal = Color3.fromRGB(255, 40, 100),
		VidaMaxima = 150,
		VelocidadVuelo = 60,
		VelocidadTurbo = 110,
		FuerzaImpulso = 520, -- arranques y frenadas muy bruscos
		Estela = {
			ColorInicio = Color3.fromRGB(255, 30, 90),
			ColorFin = Color3.fromRGB(255, 150, 200),
			Ancho = 3.4,
			Duracion = 0.7,
		},
		Atuendo = {
			-- Fuerza: body fucsia, guantes de brazo rosa, botas de plataforma rosa,
			-- coleta alta fucsia y pinzas de estrella rosa.
			Catalogo = {
				Cuerpo = CUERPO_ESTANDAR,
				Pelo = 93539044157674,
				Accesorio = 8969906636,
				Body = 70588051583626,
				Guantes = 13571992449,
				BotaIzquierda = 129227930878026, -- paquete de botas 252084968075831
				BotaDerecha = 84833228999306,
			},
		},
	},
	Velocidad = {
		Id = "Velocidad",
		Nombre = "Velocidad",
		Descripcion = "La más rápida del cielo: ataques en ráfaga.",
		Icono = "⚡",
		ColorPrincipal = Color3.fromRGB(0, 200, 255),
		VidaMaxima = 100,
		VelocidadVuelo = 85,
		VelocidadTurbo = 170,
		FuerzaImpulso = 380,
		Estela = {
			ColorInicio = Color3.fromRGB(0, 190, 255),
			ColorFin = Color3.fromRGB(170, 240, 255),
			Ancho = 3.2,
			Duracion = 0.9,
		},
		Atuendo = {
			-- Velocidad: body azul, guantes de brazo azul claro, botas de plataforma azules,
			-- coleta lateral azul platino y pinzas de estrella azules.
			Catalogo = {
				Cuerpo = CUERPO_ESTANDAR,
				Pelo = 76014013239806,
				Accesorio = 8969913883,
				Body = 113348371921982,
				Guantes = 13571986363,
				BotaIzquierda = 104210839624372, -- paquete de botas 80389513325652
				BotaDerecha = 101793789469613,
			},
		},
	},
	Estrategia = {
		Id = "Estrategia",
		Nombre = "Estrategia",
		Descripcion = "Escudos, trampas y apoyo para todo el equipo.",
		Icono = "🛡️",
		ColorPrincipal = Color3.fromRGB(60, 255, 120),
		VidaMaxima = 125,
		VelocidadVuelo = 68,
		VelocidadTurbo = 125,
		FuerzaImpulso = 430,
		Estela = {
			ColorInicio = Color3.fromRGB(40, 255, 110),
			ColorFin = Color3.fromRGB(200, 255, 215),
			Ancho = 3.3,
			Duracion = 0.8,
		},
		Atuendo = {
			-- Estrategia: body verde, guantes de brazo menta, botas de plataforma verdes,
			-- trenza lateral morada y pinzas de estrella verdes.
			Catalogo = {
				Cuerpo = CUERPO_ESTANDAR,
				Pelo = 13251202411,
				Accesorio = 8969910406,
				Body = 88905546942396,
				Guantes = 13733068490,
				BotaIzquierda = 78950231109700, -- paquete de botas 205830825829483
				BotaDerecha = 75058007668706,
			},
		},
	},
}

for _, config in LISTA do
	table.freeze(config.Atuendo.Catalogo)
	table.freeze(config.Atuendo)
	table.freeze(config.Estela)
	table.freeze(config)
end
table.freeze(LISTA)

local Heroinas = {
	Lista = LISTA,
	Orden = table.freeze({ "Fuerza", "Velocidad", "Estrategia" } :: { ArquetipoId }),
	PorDefecto = "Fuerza" :: ArquetipoId,
}

function Heroinas.EsValido(id: unknown): boolean
	return typeof(id) == "string" and (LISTA :: any)[id] ~= nil
end

-- Devuelve la config del arquetipo; si el id no es válido, la del arquetipo por defecto.
function Heroinas.Obtener(id: unknown): HeroinaConfig
	if Heroinas.EsValido(id) then
		return LISTA[id :: ArquetipoId]
	end
	return LISTA[Heroinas.PorDefecto]
end

return Heroinas
