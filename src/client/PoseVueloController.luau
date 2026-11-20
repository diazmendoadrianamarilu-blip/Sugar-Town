--!strict
-- PoseVueloController: ÚNICO sistema que mueve las articulaciones de las heroínas por código.
-- Cada frame (PreSimulation, justo después del Animator de Roblox) mezcla el Transform de cada
-- articulación (Motor6D o AnimationConstraint) con dos capas, por prioridad:
--   1) Pose base: "Vuelo" o "Carrera" (entra y sale suave).          prioridad baja
--   2) Golpe del combo (puño/patada, con variantes propias en vuelo).  prioridad alta
-- En vuelo el cuello compensa la inclinación del cuerpo: la cabeza mira siempre al frente.
-- No se replica: cada cliente anima a todas las heroínas (pose según los atributos "Volando" /
-- "Corriendo" que pone el servidor; golpes según el RemoteEvent "EfectoGolpe").

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type Pose = "Ninguna" | "Vuelo" | "Carrera"

-- Rotación respecto a la pose de reposo (Transform de la articulación).
--   Brazos/piernas: X positivo = la extremidad va hacia delante.
--   Waist/Neck: X positivo = se inclina hacia atrás (la cabeza mira arriba); Y positivo = gira a la izquierda.
local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local POSES: { [Pose]: { [string]: CFrame } } = {
	Ninguna = {},
	-- Vuelo de superheroína: un puño adelante, el otro brazo pegado al cuerpo, piernas estiradas
	Vuelo = {
		Waist = rot(8, 0, 0),
		RightShoulder = rot(172, 0, 0),
		RightElbow = rot(0, 0, 0),
		LeftShoulder = rot(12, 0, -8),
		LeftElbow = rot(15, 0, 0),
		RightHip = rot(-8, 0, 0),
		LeftHip = rot(-3, 0, 0),
		RightKnee = rot(-6, 0, 0),
		LeftKnee = rot(-22, 0, 0),
		-- Neck: se calcula cada frame (compensa la inclinación del cuerpo)
	},
	Carrera = {
		Waist = rot(-16, 0, 0), -- torso inclinado hacia delante (sprint)
		Neck = rot(10, 0, 0), -- mirada al frente
	},
}

-- "duracionCarga"/"duracionMantener" opcionales: el láser se carga y se sostiene más que un puño.
type Animacion = {
	carga: { [string]: CFrame },
	golpe: { [string]: CFrame },
	duracionCarga: number?,
	duracionMantener: number?,
}

local GOLPES: { [string]: Animacion } = {
	-- En tierra
	PunoDerecho = {
		carga = { Waist = rot(0, -22, 0), RightShoulder = rot(30, 0, 0), RightElbow = rot(80, 0, 0), LeftShoulder = rot(25, 0, 0), LeftElbow = rot(60, 0, 0) },
		golpe = { Waist = rot(0, 28, 0), RightShoulder = rot(90, 0, 0), RightElbow = rot(0, 0, 0), LeftShoulder = rot(-10, 0, 0), LeftElbow = rot(70, 0, 0) },
	},
	PunoIzquierdo = {
		carga = { Waist = rot(0, 22, 0), LeftShoulder = rot(30, 0, 0), LeftElbow = rot(80, 0, 0), RightShoulder = rot(25, 0, 0), RightElbow = rot(60, 0, 0) },
		golpe = { Waist = rot(0, -28, 0), LeftShoulder = rot(90, 0, 0), LeftElbow = rot(0, 0, 0), RightShoulder = rot(-10, 0, 0), RightElbow = rot(70, 0, 0) },
	},
	Patada = {
		carga = { Waist = rot(6, 0, 0), RightHip = rot(50, 0, 0), RightKnee = rot(-90, 0, 0), RightShoulder = rot(20, 0, 30), LeftShoulder = rot(20, 0, -30) },
		golpe = { Waist = rot(12, 0, 0), RightHip = rot(95, 0, 0), RightKnee = rot(0, 0, 0), RightShoulder = rot(30, 0, 55), LeftShoulder = rot(30, 0, -55) },
	},
	-- En vuelo (cuerpo horizontal): puñetazo al frente estilo superhéroe y patada
	PunoVueloDerecho = {
		carga = { RightShoulder = rot(110, 0, 0), RightElbow = rot(100, 0, 0), LeftShoulder = rot(150, 0, 0) },
		golpe = { Waist = rot(0, 14, 0), RightShoulder = rot(176, 0, 0), RightElbow = rot(0, 0, 0), LeftShoulder = rot(20, 0, -10), LeftElbow = rot(20, 0, 0) },
	},
	PunoVueloIzquierdo = {
		carga = { LeftShoulder = rot(110, 0, 0), LeftElbow = rot(100, 0, 0), RightShoulder = rot(150, 0, 0) },
		golpe = { Waist = rot(0, -14, 0), LeftShoulder = rot(176, 0, 0), LeftElbow = rot(0, 0, 0), RightShoulder = rot(20, 0, 10), RightElbow = rot(20, 0, 0) },
	},
	PatadaVuelo = {
		carga = { RightHip = rot(-35, 0, 0), RightKnee = rot(-100, 0, 0), RightShoulder = rot(150, 0, 15), LeftShoulder = rot(150, 0, -15) },
		golpe = { Waist = rot(-10, 0, 0), RightHip = rot(75, 0, 0), RightKnee = rot(0, 0, 0), RightShoulder = rot(160, 0, 20), LeftShoulder = rot(160, 0, -20) },
	},
	-- Rayo láser: carga con la mano derecha junto al pecho y dispara con el brazo estirado
	Disparo = {
		carga = { Waist = rot(0, -18, 0), RightShoulder = rot(70, 0, 0), RightElbow = rot(70, 0, 0), LeftShoulder = rot(60, 0, 0), LeftElbow = rot(80, 0, 0) },
		golpe = { Waist = rot(0, 10, 0), RightShoulder = rot(90, 0, 0), RightElbow = rot(0, 0, 0), LeftShoulder = rot(15, 0, -10), LeftElbow = rot(30, 0, 0) },
		duracionCarga = 0.45,
		duracionMantener = 0.4,
	},
	DisparoVuelo = {
		carga = { RightShoulder = rot(120, 0, 0), RightElbow = rot(80, 0, 0), LeftShoulder = rot(120, 0, 0), LeftElbow = rot(80, 0, 0) },
		golpe = { RightShoulder = rot(176, 0, 0), RightElbow = rot(0, 0, 0), LeftShoulder = rot(20, 0, -10), LeftElbow = rot(20, 0, 0) },
		duracionCarga = 0.45,
		duracionMantener = 0.4,
	},
}
-- Golpe de tierra → variante en vuelo
local VARIANTE_VUELO: { [string]: string } = {
	PunoDerecho = "PunoVueloDerecho",
	PunoIzquierdo = "PunoVueloIzquierdo",
	Patada = "PatadaVuelo",
	Disparo = "DisparoVuelo",
}

local DURACION_CARGA = 0.05
local DURACION_GOLPE = 0.07
local DURACION_MANTENER = 0.08
local DURACION_VUELTA = 0.16
local function duracionTotal(animacion: Animacion): number
	return (animacion.duracionCarga or DURACION_CARGA) + DURACION_GOLPE + (animacion.duracionMantener or DURACION_MANTENER) + DURACION_VUELTA
end
local VELOCIDAD_POSE = 9 -- qué tan rápido entra/sale la pose base (1/s)
local CUELLO_MAXIMO = 70 -- grados que puede levantar la cabeza en vuelo
local INTERVALO_REVISION = 1 -- s: vuelve a buscar articulaciones (ApplyDescription cambia el cuerpo)

-- Nombres de todas las articulaciones que alguna capa puede mover
local NOMBRES: { [string]: boolean } = { Neck = true }
for _, pose in POSES do
	for nombre in pose do
		NOMBRES[nombre] = true
	end
end
for _, animacion in GOLPES do
	for _, fase in { animacion.carga, animacion.golpe } do
		for nombre in fase do
			NOMBRES[nombre] = true
		end
	end
end

type Capa = { cf: CFrame, peso: number }
type Golpe = { animacion: Animacion, inicio: number }
type Estado = {
	character: Model,
	pose: Pose,
	articulaciones: { [string]: Instance }, -- Motor6D o AnimationConstraint
	base: { [string]: Capa },
	golpe: Golpe?,
	revision: number,
}

local estados: { [Model]: Estado } = {}
local conexionesPersonaje: { [Player]: { RBXScriptConnection } } = {}
local conexionesJugador: { [Player]: RBXScriptConnection } = {}

local PoseVueloController = {}

local function buscarArticulaciones(estado: Estado)
	table.clear(estado.articulaciones)
	for _, d in estado.character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and NOMBRES[d.Name] then
			estado.articulaciones[d.Name] = d
		end
	end
	estado.revision = os.clock()
end

local function obtenerEstado(character: Model): Estado
	local estado = estados[character]
	if estado then
		return estado
	end
	local nuevo: Estado = { character = character, pose = "Ninguna", articulaciones = {}, base = {}, golpe = nil, revision = 0 }
	buscarArticulaciones(nuevo)
	estados[character] = nuevo
	return nuevo
end

-- Inclinación hacia delante del cuerpo (radianes): 0 de pie, ~85° volando horizontal.
local function inclinacion(character: Model): number
	local raiz = character:FindFirstChild("HumanoidRootPart")
	if raiz and raiz:IsA("BasePart") then
		return math.asin(math.clamp(-raiz.CFrame.LookVector.Y, -1, 1))
	end
	return 0
end

local function muestrearGolpe(animacion: Animacion, nombre: string, t: number): (CFrame?, number)
	local carga = animacion.carga[nombre]
	local golpe = animacion.golpe[nombre]
	if not carga and not golpe then
		return nil, 0
	end
	local c = carga or CFrame.identity
	local g = golpe or CFrame.identity
	local duracionCarga = animacion.duracionCarga or DURACION_CARGA
	local duracionMantener = animacion.duracionMantener or DURACION_MANTENER
	if t < duracionCarga then
		-- Entra rápido en la pose de carga y la sostiene el resto de la carga
		return c, math.min(1, t / DURACION_CARGA)
	end
	t -= duracionCarga
	if t < DURACION_GOLPE then
		local a = t / DURACION_GOLPE
		return c:Lerp(g, 1 - (1 - a) * (1 - a)), 1
	end
	t -= DURACION_GOLPE
	if t < duracionMantener then
		return g, 1
	end
	t -= duracionMantener
	return g, 1 - math.clamp(t / DURACION_VUELTA, 0, 1)
end

local function actualizar(dt: number)
	local ahora = os.clock()
	local suavizado = math.min(1, dt * VELOCIDAD_POSE)
	for character, estado in estados do
		if not character:IsDescendantOf(game) then
			estados[character] = nil
			continue
		end
		local golpe = estado.golpe
		if golpe and ahora - golpe.inicio >= duracionTotal(golpe.animacion) then
			estado.golpe = nil
			golpe = nil
		end
		if ahora - estado.revision > INTERVALO_REVISION then
			buscarArticulaciones(estado)
		end
		local pose = POSES[estado.pose]

		for nombre, articulacion in estado.articulaciones do
			if not articulacion.Parent then
				continue
			end
			-- 1) Capa base (entra y sale suave)
			local objetivo = pose[nombre]
			if nombre == "Neck" and estado.pose == "Vuelo" then
				objetivo = CFrame.Angles(math.clamp(inclinacion(character) * 0.8, 0, math.rad(CUELLO_MAXIMO)), 0, 0)
			end
			local capa = estado.base[nombre]
			if objetivo and not capa then
				capa = { cf = objetivo, peso = 0 }
				estado.base[nombre] = capa
			end
			if capa then
				if objetivo then
					capa.cf = capa.cf:Lerp(objetivo, suavizado)
				end
				capa.peso += ((if objetivo then 1 else 0) - capa.peso) * suavizado
				if capa.peso < 0.01 and not objetivo then
					estado.base[nombre] = nil
					capa = nil
				end
			end

			local transform = (articulacion :: any).Transform :: CFrame
			local cambiado = false
			if capa then
				transform = transform:Lerp(capa.cf, capa.peso)
				cambiado = true
			end
			-- 2) Capa del golpe (manda sobre la base)
			if golpe then
				local cf, peso = muestrearGolpe(golpe.animacion, nombre, math.max(ahora - golpe.inicio, 0))
				if cf and peso > 0 then
					transform = transform:Lerp(cf, peso)
					cambiado = true
				end
			end
			if cambiado then
				(articulacion :: any).Transform = transform
			end
		end
	end
end

-- ─── API pública ─────────────────────────────────────────────────────────────

-- Pose base (prioridad baja).
function PoseVueloController.AplicarPose(character: Model, pose: Pose)
	obtenerEstado(character).pose = pose
end

-- Compatibilidad: activar/desactivar la pose de vuelo.
function PoseVueloController.Aplicar(character: Model, volando: boolean)
	PoseVueloController.AplicarPose(character, if volando then "Vuelo" else "Ninguna")
end

-- Golpe del combo (prioridad alta). En vuelo usa su variante aérea.
function PoseVueloController.ReproducirGolpe(character: Model, nombre: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local estado = obtenerEstado(character)
	local volando = estado.pose == "Vuelo" or character:GetAttribute("Volando") == true
	local animacion = GOLPES[if volando then VARIANTE_VUELO[nombre] or nombre else nombre]
	if animacion then
		estado.golpe = { animacion = animacion, inicio = os.clock() }
	end
end

-- Hit-stop: congela un instante la pose del golpe.
function PoseVueloController.HitStop(character: Model, segundos: number)
	local estado = estados[character]
	local golpe = if estado then estado.golpe else nil
	if golpe then
		golpe.inicio += segundos
	end
end

local function poseSegunAtributos(character: Model): Pose
	if character:GetAttribute("Volando") == true then
		return "Vuelo"
	elseif character:GetAttribute("Corriendo") == true then
		return "Carrera"
	end
	return "Ninguna"
end

local function observarPersonaje(jugador: Player, character: Model)
	local lista = conexionesPersonaje[jugador]
	if lista then
		for _, conexion in lista do
			conexion:Disconnect()
		end
	end
	local function actualizarPose()
		PoseVueloController.AplicarPose(character, poseSegunAtributos(character))
	end
	conexionesPersonaje[jugador] = {
		character:GetAttributeChangedSignal("Volando"):Connect(actualizarPose),
		character:GetAttributeChangedSignal("Corriendo"):Connect(actualizarPose),
	}
	actualizarPose()
end

local function observarJugador(jugador: Player)
	-- La jugadora local aplica su pose al instante desde VueloController (sin esperar al servidor).
	if jugador == Players.LocalPlayer then
		return
	end
	conexionesJugador[jugador] = jugador.CharacterAdded:Connect(function(character)
		observarPersonaje(jugador, character)
	end)
	if jugador.Character then
		observarPersonaje(jugador, jugador.Character)
	end
end

local function dejarDeObservar(jugador: Player)
	local lista = conexionesPersonaje[jugador]
	if lista then
		for _, conexion in lista do
			conexion:Disconnect()
		end
		conexionesPersonaje[jugador] = nil
	end
	local conexion = conexionesJugador[jugador]
	if conexion then
		conexion:Disconnect()
		conexionesJugador[jugador] = nil
	end
end

function PoseVueloController.Init()
	Players.PlayerRemoving:Connect(dejarDeObservar)
	Players.PlayerAdded:Connect(observarJugador)
	for _, jugador in Players:GetPlayers() do
		observarJugador(jugador)
	end
	RunService.PreSimulation:Connect(actualizar)
end

return PoseVueloController
