--!strict
-- Tipos de monstruo (valores base en la oleada 1). Solo datos.

local Types = require(script.Parent.Parent.Types)

type MonstruoConfig = Types.MonstruoConfig

local LISTA: { MonstruoConfig } = {
	{
		Id = "Gomiloso",
		Nombre = "Gomiloso",
		Color = Color3.fromRGB(170, 90, 255),
		ColorOjos = Color3.fromRGB(255, 255, 90),
		Escala = 1.5,
		Vida = 260,
		Dano = 14,
		Velocidad = 22,
		RangoAtaque = 6,
		CadenciaAtaque = 1.4,
		RadioPersecucion = 90,
		Recompensa = 8,
		Experiencia = 20,
		AparecenDesdeOleada = 1,
		Peso = 6,
		-- Escupe una bola de gelatina que cae donde estaba la heroína y la ralentiza
		Especial = {
			Tipo = "Gelatina",
			Nombre = "Bola de gelatina",
			Enfriamiento = 6,
			Aviso = 1,
			AlcanceMin = 12,
			AlcanceMax = 75,
			Dano = 10,
			Radio = 9,
			Ralentizacion = 0.45,
			DuracionEfecto = 3,
			Empuje = 0,
		},
	},
	{
		Id = "Zumbon",
		Nombre = "Zumbón",
		Color = Color3.fromRGB(255, 140, 40),
		ColorOjos = Color3.fromRGB(80, 255, 255),
		Escala = 1.1,
		Vida = 130,
		Dano = 8,
		Velocidad = 28,
		RangoAtaque = 5,
		CadenciaAtaque = 0.8,
		RadioPersecucion = 130,
		Recompensa = 6,
		Experiencia = 15,
		AparecenDesdeOleada = 2,
		Peso = 4,
		-- Embestida rápida en línea recta (franja roja antes de salir disparado)
		Especial = {
			Tipo = "Embestida",
			Nombre = "Embestida",
			Enfriamiento = 5,
			Aviso = 0.9,
			AlcanceMin = 14,
			AlcanceMax = 60,
			Dano = 14,
			Radio = 5, -- media anchura de la franja
			Ralentizacion = 1,
			DuracionEfecto = 0,
			Empuje = 70,
		},
	},
	{
		Id = "Bruton",
		Nombre = "Brutón",
		Color = Color3.fromRGB(110, 210, 70),
		ColorOjos = Color3.fromRGB(255, 50, 80),
		Escala = 2.5,
		Vida = 750, -- tanque: ~19 golpes del combo jugando sola (vida base)
		Dano = 40,
		Velocidad = 20,
		RangoAtaque = 8,
		CadenciaAtaque = 2.2,
		RadioPersecucion = 80,
		Recompensa = 25,
		Experiencia = 60,
		AparecenDesdeOleada = 3,
		Peso = 2,
		-- Golpe al suelo: onda expansiva y piedras alrededor del monstruo (también el jefe)
		Especial = {
			Tipo = "GolpeSuelo",
			Nombre = "Golpe sísmico",
			Enfriamiento = 7,
			Aviso = 1.1,
			AlcanceMin = 0,
			AlcanceMax = 24, -- usa el golpe si la heroína está a menos de esto (×1.5 en el jefe)
			Dano = 30,
			Radio = 26, -- radio de la onda (×1.5 en el jefe)
			Ralentizacion = 1,
			DuracionEfecto = 0,
			Empuje = 80,
		},
	},
}

for _, config in LISTA do
	table.freeze(config.Especial)
	table.freeze(config)
end

local Monstruos = {
	Lista = table.freeze(LISTA),
	-- El jefe usa este tipo con multiplicadores
	JefeBase = "Bruton",
	Jefe = table.freeze({
		MultiplicadorVida = 4,
		MultiplicadorDano = 1.5,
		MultiplicadorEscala = 1.5,
		MultiplicadorRecompensa = 5,
	}),
}

function Monstruos.PorId(id: string): MonstruoConfig?
	for _, config in LISTA do
		if config.Id == id then
			return config
		end
	end
	return nil
end

return Monstruos
