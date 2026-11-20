--!strict
-- Trafico: rutas de los autos de caricatura (función pura, sin estado).
-- La posición de cada auto depende solo de la hora del servidor (Workspace:GetServerTimeNow()):
--   • el SERVIDOR la usa para detectar choques con heroínas (TraficoService),
--   • cada CLIENTE dibuja sus autos con la misma fórmula (TraficoController): movimiento suave
--     sin replicar nada por la red.
-- Las rutas son anillos rectangulares por las calles de x/z = ±270 y ±540: nunca pasan por la
-- Plaza Central y solo CRUZAN las avenidas centrales por donde entran los monstruos. Los autos no
-- tienen colisión física (CanCollide = false), así que no atropellan monstruos ni bloquean calles.

local Juego = require(script.Parent.Config.Juego)

export type Anillo = {
	Medio: number, -- distancia del centro a la calle (studs)
	Carril: number, -- desplazamiento del carril respecto al centro de la calle
	Sentido: number, -- 1 o -1
	Autos: number,
	Velocidad: number, -- studs/s
}

local ANILLOS: { Anillo } = {
	{ Medio = 270, Carril = -9, Sentido = 1, Autos = 3, Velocidad = 42 },
	{ Medio = 270, Carril = 9, Sentido = -1, Autos = 3, Velocidad = 36 },
	{ Medio = 540, Carril = -9, Sentido = 1, Autos = 2, Velocidad = 48 },
}

local ALTURA = 1.9 -- centro del auto sobre el asfalto

type AutoInfo = { anillo: Anillo, fase: number }
local AUTOS: { AutoInfo } = {}
for _, anillo in ANILLOS do
	for i = 1, anillo.Autos do
		table.insert(AUTOS, { anillo = anillo, fase = (i - 1) / anillo.Autos })
	end
end

local Trafico = {
	CantidadAutos = #AUTOS,
	Aturdimiento = 1.5, -- s que queda mareada la heroína
	EsperaEntreChoques = 3, -- s de gracia tras un choque
	EmpujeChoque = 45, -- velocidad del empujón (studs/s)
	MedioLargo = 8.5, -- caja de choque (mitad del largo del auto)
	MedioAncho = 4.5,
}

-- CFrame del auto i (1..CantidadAutos) en el instante t (hora del servidor). Mira hacia -Z local.
function Trafico.CFrameAuto(i: number, t: number): CFrame
	local info = AUTOS[i]
	local anillo = info.anillo
	local r = anillo.Medio + anillo.Carril
	local esquinas = {
		Vector2.new(r, r),
		Vector2.new(-r, r),
		Vector2.new(-r, -r),
		Vector2.new(r, -r),
	}
	if anillo.Sentido < 0 then
		esquinas = { esquinas[1], esquinas[4], esquinas[3], esquinas[2] }
	end
	local perimetro = 8 * r
	local s = (t * anillo.Velocidad + info.fase * perimetro) % perimetro
	local tramo = math.floor(s / (2 * r)) + 1
	local resto = s - (tramo - 1) * 2 * r
	local a = esquinas[tramo]
	local b = esquinas[tramo % 4 + 1]
	local p = a:Lerp(b, resto / (2 * r))
	local d = (b - a).Unit
	local centro = Juego.Ciudad.Centro
	local posicion = centro + Vector3.new(p.X, ALTURA, p.Y)
	return CFrame.lookAt(posicion, posicion + Vector3.new(d.X, 0, d.Y))
end

return Trafico
