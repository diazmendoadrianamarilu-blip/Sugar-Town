--!strict
-- Configuración general de la partida: ciudad, edificios defendibles, oleadas y progresión.
-- Solo datos.

local Types = require(script.Parent.Parent.Types)

-- Escala de la ciudad (×3 respecto a la versión inicial)
local ESCALA = 3

local EDIFICIOS: { Types.EdificioConfig } = {
	{
		Id = "Ayuntamiento",
		Nombre = "Ayuntamiento",
		Posicion = Vector2.new(-135, -135),
		Tamano = Vector3.new(70, 95, 60),
		Color = Color3.fromRGB(255, 190, 220),
		ColorAcento = Color3.fromRGB(255, 60, 160),
		Techo = "Cupula",
		VidaMaxima = 3000,
	},
	{
		Id = "FabricaDulces",
		Nombre = "Fábrica de Dulces",
		Posicion = Vector2.new(135, -135),
		Tamano = Vector3.new(85, 70, 70),
		Color = Color3.fromRGB(255, 230, 160),
		ColorAcento = Color3.fromRGB(255, 140, 40),
		Techo = "Piramide",
		VidaMaxima = 2700,
	},
	{
		Id = "Hospital",
		Nombre = "Hospital Arcoíris",
		Posicion = Vector2.new(-135, 135),
		Tamano = Vector3.new(65, 120, 65),
		Color = Color3.fromRGB(200, 240, 255),
		ColorAcento = Color3.fromRGB(0, 190, 255),
		Techo = "Plano",
		VidaMaxima = 2700,
	},
	{
		Id = "Escuela",
		Nombre = "Escuela Estelar",
		Posicion = Vector2.new(135, 135),
		Tamano = Vector3.new(90, 72, 60),
		Color = Color3.fromRGB(210, 255, 210),
		ColorAcento = Color3.fromRGB(40, 220, 110),
		Techo = "Piramide",
		VidaMaxima = 2500,
	},
	{
		Id = "TorreRadio",
		Nombre = "Torre de Radio",
		Posicion = Vector2.new(405, -405),
		Tamano = Vector3.new(40, 150, 40),
		Color = Color3.fromRGB(225, 205, 255),
		ColorAcento = Color3.fromRGB(170, 80, 255),
		Techo = "Antena",
		VidaMaxima = 2200,
	},
}

local Juego = {
	Ciudad = {
		-- Lejos del origen para no chocar con el contenido existente del lugar.
		Centro = Vector3.new(0, 0, 3000),
		Tamano = 380 * ESCALA, -- 1140: lado de la zona urbana (studs)
		SeparacionCalles = 90 * ESCALA, -- calles en -540, -270, 0, 270, 540
		AnchoCalle = 40,
		RadioPlazaCentral = 70,
		AlturaMinRascacielos = 75,
		AlturaMaxRascacielos = 145,
		RadioAnilloFondo = 820, -- rascacielos de fondo
		RadioColinas = 1150, -- anillo de montañas que tapa el borde
		Semilla = 2024, -- misma ciudad en cada partida
	},

	Edificios = EDIFICIOS,

	-- Monstruos entran por los extremos de las avenidas (X, Z relativos al centro)
	PuntosAparicionMonstruos = {
		Vector2.new(0, -560),
		Vector2.new(0, 560),
		Vector2.new(-560, 0),
		Vector2.new(560, 0),
	},

	Oleadas = {
		TiempoPreparacionInicial = 15,
		TiempoEntreOleadas = 8,
		MonstruosBase = 3,
		MonstruosPorOleada = 2, -- extra por cada oleada
		MaxVivosALaVez = 16, -- también limita los Highlight simultáneos (máx. 31 por cliente)
		IntervaloAparicion = 1.2,
		CadaCuantasJefe = 5, -- oleada 5, 10, 15... trae un jefe
		BonoMonedasOleada = 15,
		AumentoVidaPorOleada = 0.15, -- +15% de vida por oleada
		AumentoDanoPorOleada = 0.08,

		-- ── Fase 1: que perder no borre todo ──
		CadaCuantasPuntoControl = 5, -- al perder se reanuda tras el último múltiplo de 5 superado (6, 11, 16…)
		ReparacionPorOleada = 0.25, -- al superar una oleada, los edificios en pie recuperan 25 % de su vida
		ReconstruccionTrasJefe = 0.5, -- al vencer una oleada de jefe, los edificios caídos se reconstruyen al 50 %
		RecompensaDerrotaPorOleada = 8, -- monedas al perder = oleada alcanzada × 8 (con multiplicadores)
		BonoNuevoRecord = 50, -- monedas extra si la jugadora supera su récord personal
		-- Dificultad según cuántas heroínas hay en la ciudad (índice = nº de jugadoras, 4+ usa la última fila).
		-- SOLA: claramente más fácil (un Gomiloso de la oleada 1 cae con 7 golpes del combo a nivel 1).
		-- En grupo suben vida y cantidad algo más que el daño extra del equipo: es un reto, no un paseo.
		AjusteJugadoras = {
			{ Cantidad = 0.6, Vida = 0.7, Dano = 0.7 }, -- SOLO
			{ Cantidad = 1.0, Vida = 1.0, Dano = 0.9 }, -- DÚO
			{ Cantidad = 1.3, Vida = 1.2, Dano = 1.0 }, -- 3 heroínas
			{ Cantidad = 1.6, Vida = 1.35, Dano = 1.1 }, -- ESCUADRÓN (4)
		},
	},

	TiempoReinicio = 10, -- segundos tras perder todos los edificios

	ExperienciaPorNivel = 100, -- el nivel N requiere N * 100 XP

	-- Regeneración de vida propia (la de Roblox se desactiva): solo cura tras un rato sin recibir daño.
	-- Derrota de una heroína en la ciudad (RescateService). Los monstruos no la matan: queda DERRIBADA.
	--   SOLO: oferta inmediata (revivir con Robux o volver al lobby).
	--   Grupo: una compañera la salva manteniendo pulsado "Salvar" a su lado; si caen todas (o pasa
	--   EsperaRescate sin ayuda), cada una recibe la oferta. Sin pagar → lobby.
	Rescate = {
		EsperaRescate = 45, -- s que una heroína derribada espera a que la salven (en grupo)
		TiempoOferta = 20, -- s para decidir revivir con Robux o volver al lobby
		TiempoCompra = 60, -- s extra mientras está abierta la ventana de compra de Roblox
		DuracionSalvar = 2, -- s que la compañera mantiene pulsado "Salvar"
		DistanciaSalvar = 12, -- studs
		VidaAlSalvar = 0.5, -- fracción de vida al ser salvada por una compañera
		VidaAlRevivir = 1, -- fracción de vida al revivir pagando
		Invulnerable = 3, -- s de protección al levantarse
	},
	Regeneracion = {
		EsperaTrasDano = 4, -- segundos sin recibir daño antes de empezar a curar
		PorcentajePorSegundo = 0.05, -- fracción de la vida máxima que se recupera por segundo
		Intervalo = 1, -- cada cuánto se cura (y se muestra el "+N" verde)
	},

	Lobby = {
		Centro = Vector3.new(0, 500, 0), -- patio de espera, separado de la ciudad
		CuentaAtrasGrupo = 5, -- segundos sobre una plataforma antes de teletransportar
		IntervaloDeteccion = 0.25,
		Plataformas = {
			{ Nombre = "SOLO", Maximo = 1, X = -18 },
			{ Nombre = "DÚO", Maximo = 2, X = 0 },
			{ Nombre = "ESCUADRÓN", Maximo = 4, X = 18 },
		},
		-- Recompensa por tiempo jugado en el tubo de Esencia Estelar
		IntervaloRecompensa = 15 * 60, -- segundos entre impulsos
		BonoPorImpulso = 0.05, -- +5% monedas ganadas por impulso permanente
		MaxImpulsos = 20,
	},

	-- Impulso de amigos: monedas ganadas × min(MaxMultiplicador, 1 + amigos conectados)
	MaxMultiplicadorAmigos = 4,

	Carrera = {
		VelocidadNormal = 18,
		VelocidadSprint = 38,
	},
}

return Juego
