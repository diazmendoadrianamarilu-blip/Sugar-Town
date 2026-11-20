--!strict
-- Combate cuerpo a cuerpo (combo de 3 golpes). Solo datos: la lógica autoritativa está en
-- CombateService (servidor); las animaciones y efectos en CombateController (cliente).

local Types = require(script.Parent.Parent.Types)

type GolpeConfig = Types.GolpeConfig

local GOLPES: { GolpeConfig } = {
	{
		Id = "PunoDerecho",
		Nombre = "Puño",
		Dano = 24,
		Alcance = 8, -- studs desde la heroína hasta la superficie del monstruo
		Recuperacion = 0.26, -- segundos hasta poder lanzar el siguiente golpe
		Empuje = 0,
		Sonido = "GolpePuno",
		Animacion = "PunoDerecho",
	},
	{
		Id = "PunoIzquierdo",
		Nombre = "Puño",
		Dano = 24,
		Alcance = 8,
		Recuperacion = 0.26,
		Empuje = 0,
		Sonido = "GolpePuno2",
		Animacion = "PunoIzquierdo",
	},
	{
		Id = "Patada",
		Nombre = "Patada",
		Dano = 36,
		Alcance = 9,
		Recuperacion = 0.45,
		Empuje = 55, -- la patada final empuja al monstruo (studs/s)
		Sonido = "GolpePatada",
		Animacion = "Patada",
	},
}

for _, golpe in GOLPES do
	table.freeze(golpe)
end

local Combate = {
	Golpes = table.freeze(GOLPES),
	VentanaCombo = 0.9, -- si pasa más tiempo entre golpes, el combo vuelve al primer puño
	ToleranciaRed = 0.08, -- margen de latencia al validar la recuperación en el servidor
	ConoFrontal = 0.1, -- producto escalar mínimo (dirección de ataque · hacia el monstruo)
	-- Contador de combo ("x5 COMBO!"): golpes acertados seguidos
	DuracionContador = 2.5, -- segundos sin acertar para que el contador se reinicie
	CadaCuantosBono = 5, -- cada 5 golpes de combo…
	MonedasBono = 2, -- …monedas extra (con los multiplicadores de amigos/VIP/impulsos)
	HitStop = 0.05, -- pausa al impactar (solo en la pantalla de quien golpea)
	SacudidaGolpe = 0.12,
	SacudidaPatada = 0.25,
}

return table.freeze(Combate)
