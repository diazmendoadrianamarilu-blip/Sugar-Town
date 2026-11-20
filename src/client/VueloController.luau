--!strict
-- VueloController: vuelo de la heroína local.
--   Activar/desactivar: doble Espacio o F (mando: ButtonY).
--   Dirección: WASD relativo a la cámara (mirar arriba/abajo = subir/bajar).
--   Turbo: mantener Shift.
-- Física: LinearVelocity (movimiento) + AlignOrientation (inclinación hacia donde vuela).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Heroinas = require(Shared.Config.Heroinas)
local Juego = require(Shared.Config.Juego)
local Mejoras = require(Shared.Config.Mejoras)
local Remotes = require(Shared.Remotes)
local TiendaRobux = require(Shared.Config.TiendaRobux)
local Types = require(Shared.Types)
local EfectosController = require(script.Parent.EfectosController)
local PoseVueloController = require(script.Parent.PoseVueloController)

local VENTANA_DOBLE_SALTO = 0.3 -- segundos entre dos pulsaciones de Espacio
local AGILIDAD = 5 -- qué tan rápido la velocidad real alcanza la deseada
local SUAVIDAD_INCLINACION = 6
local INCLINACION_MAXIMA = math.rad(85) -- 90° = cuerpo totalmente horizontal
local RESPONSIVIDAD_GIRO = 18

type EstadoVuelo = {
	personaje: Model,
	humanoid: Humanoid,
	root: BasePart,
	attachment: Attachment,
	velocidad: LinearVelocity,
	orientacion: AlignOrientation,
	velActual: Vector3,
	inclinacion: number,
	mirada: Vector3, -- dirección horizontal hacia la que mira el cuerpo
	conexionPaso: RBXScriptConnection,
}

local jugador = Players.LocalPlayer
local personaje: Model? = nil
local vuelo: EstadoVuelo? = nil
local ultimoSalto = 0
local controles: any = nil
local eventoEstado: RemoteEvent
local eventoCarrera: RemoteEvent
local corriendo = false

local VueloController = {}

local function obtenerConfig(): Types.HeroinaConfig
	return Heroinas.Obtener(jugador:GetAttribute("Arquetipo"))
end

-- Intenta obtener los controles del PlayerModule sin bloquear (puede no existir en algunas plantillas).
local function buscarControles()
	if controles then
		return
	end
	local playerScripts = jugador:FindFirstChild("PlayerScripts")
	local playerModule = if playerScripts then playerScripts:FindFirstChild("PlayerModule") else nil
	if playerModule and playerModule:IsA("ModuleScript") then
		local ok, resultado = pcall(function()
			return (require(playerModule) :: any):GetControls()
		end)
		if ok then
			controles = resultado
		end
	end
end

local function tecla(codigo: Enum.KeyCode): number
	return if UserInputService:IsKeyDown(codigo) then 1 else 0
end

-- Vector de movimiento local: X = derecha, Z = atrás (W da Z = -1).
-- 1º PlayerModule (WASD + joystick táctil + mando). 2º Humanoid.MoveDirection: los controles de
-- Roblox lo rellenan SIEMPRE (también con el joystick de tablet/celular y aunque el PlayerModule no
-- esté en PlayerScripts, como pasa en las versiones nuevas de Roblox). 3º teclado directo.
local function obtenerEntrada(): Vector3
	if controles then
		local ok, vector = pcall(function()
			return controles:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" and vector.Magnitude > 0 then
			return vector
		end
	end
	local estado = vuelo
	local camara = Workspace.CurrentCamera
	if estado and camara then
		local mundo = estado.humanoid.MoveDirection -- dirección horizontal en el mundo
		if mundo.Magnitude > 0.01 then
			-- Pasarla a ejes de la cámara (derecha / delante), para que mirar arriba o abajo
			-- siga sirviendo para subir o bajar
			local derecha = Vector3.new(camara.CFrame.RightVector.X, 0, camara.CFrame.RightVector.Z)
			local delante = Vector3.new(camara.CFrame.LookVector.X, 0, camara.CFrame.LookVector.Z)
			if derecha.Magnitude > 0.01 and delante.Magnitude > 0.01 then
				return Vector3.new(mundo:Dot(derecha.Unit), 0, -mundo:Dot(delante.Unit))
			end
		end
	end
	local x = tecla(Enum.KeyCode.D) + tecla(Enum.KeyCode.Right) - tecla(Enum.KeyCode.A) - tecla(Enum.KeyCode.Left)
	local z = tecla(Enum.KeyCode.S) + tecla(Enum.KeyCode.Down) - tecla(Enum.KeyCode.W) - tecla(Enum.KeyCode.Up)
	return Vector3.new(x, 0, z)
end

local function aplanar(v: Vector3): Vector3?
	local plano = Vector3.new(v.X, 0, v.Z)
	if plano.Magnitude < 0.01 then
		return nil
	end
	return plano.Unit
end

-- Ralentización (p. ej. gelatina del Gomiloso): el servidor marca el personaje con los atributos
-- LentaFactor / LentaHasta y aquí se aplica, porque la heroína es dueña de su movimiento.
local function factorLentitud(): number
	local character = personaje
	if not character then
		return 1
	end
	local hasta = character:GetAttribute("LentaHasta")
	local factor = character:GetAttribute("LentaFactor")
	if typeof(hasta) == "number" and typeof(factor) == "number" and Workspace:GetServerTimeNow() < hasta then
		return math.clamp(factor, 0.1, 1)
	end
	return 1
end

local function paso(dt: number)
	local estado = vuelo
	local camara = Workspace.CurrentCamera
	if not estado or not camara then
		return
	end

	local config = obtenerConfig()
	local camCF = camara.CFrame

	-- 1) Velocidad deseada según cámara + WASD
	local entrada = obtenerEntrada()
	local direccion = camCF.RightVector * entrada.X - camCF.LookVector * entrada.Z
	local intensidad = math.min(direccion.Magnitude, 1)
	local turbo = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local mejora = Mejoras.Multiplicador(jugador, config.Id, "Vuelo")
		* (if TiendaRobux.TienePase(jugador, "VueloSupersonico") then 2 else 1)
	local rapidezMax = (if turbo then config.VelocidadTurbo else config.VelocidadVuelo) * mejora * factorLentitud()
	local deseada = if intensidad > 0.01 then direccion.Unit * rapidezMax * intensidad else Vector3.zero

	estado.velActual = estado.velActual:Lerp(deseada, math.min(1, dt * AGILIDAD))
	estado.velocidad.VectorVelocity = estado.velActual
	EfectosController.SonidoVuelo(true, math.clamp(estado.velActual.Magnitude / (config.VelocidadTurbo * mejora), 0, 1))

	-- 2) Orientación: girar hacia la dirección de vuelo e inclinar el cuerpo (cabeza por delante)
	local vel = estado.velActual
	local horizontal = aplanar(vel)
	if horizontal and Vector3.new(vel.X, 0, vel.Z).Magnitude > 1 then
		estado.mirada = horizontal
	else
		estado.mirada = aplanar(camCF.LookVector) or estado.mirada
	end

	local rapidez = vel.Magnitude
	local objetivo = 0
	if rapidez > 1 then
		local elevacion = math.asin(math.clamp(vel.Y / rapidez, -1, 1))
		local factor = math.clamp(rapidez / config.VelocidadVuelo, 0, 1)
		objetivo = math.clamp(math.pi / 2 - elevacion, 0, INCLINACION_MAXIMA) * factor
	end
	estado.inclinacion += (objetivo - estado.inclinacion) * math.min(1, dt * SUAVIDAD_INCLINACION)

	estado.orientacion.CFrame = CFrame.lookAt(Vector3.zero, estado.mirada)
		* CFrame.Angles(-estado.inclinacion, 0, 0)
end

-- ─── Sprint en tierra (Shift) ────────────────────────────────────────────────

local function establecerCarrera(activa: boolean)
	if corriendo == activa then
		return
	end
	corriendo = activa
	local character = personaje
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.WalkSpeed = if activa then Juego.Carrera.VelocidadSprint else Juego.Carrera.VelocidadNormal
	end
	if character then
		PoseVueloController.AplicarPose(character, if activa then "Carrera" else "Ninguna")
	end
	eventoCarrera:FireServer(activa) -- el servidor enciende la estela de velocidad
end

local function actualizarCarrera()
	if vuelo then
		return -- en el aire Shift es el turbo de vuelo
	end
	local character = personaje
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		establecerCarrera(false)
		return
	end
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		and UserInputService:GetFocusedTextBox() == nil
	establecerCarrera(shift and humanoid.MoveDirection.Magnitude > 0.1)
	-- Velocidad a pie con la ralentización aplicada
	local base = if corriendo then Juego.Carrera.VelocidadSprint else Juego.Carrera.VelocidadNormal
	local deseada = base * factorLentitud()
	if humanoid.WalkSpeed ~= deseada then
		humanoid.WalkSpeed = deseada
	end
end

local function activar()
	local character = personaje
	if vuelo or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	if not (root and root:IsA("BasePart")) then
		return
	end

	establecerCarrera(false)
	local config = obtenerConfig()
	buscarControles() -- reintento por si el PlayerModule cargó tarde

	local attachment = Instance.new("Attachment")
	attachment.Name = "VueloAttachment"
	attachment.Parent = root

	local velocidad = Instance.new("LinearVelocity")
	velocidad.Name = "VueloVelocidad"
	velocidad.Attachment0 = attachment
	velocidad.RelativeTo = Enum.ActuatorRelativeTo.World
	velocidad.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocidad.MaxForce = root.AssemblyMass * config.FuerzaImpulso
	velocidad.VectorVelocity = root.AssemblyLinearVelocity
	velocidad.Parent = root

	local orientacion = Instance.new("AlignOrientation")
	orientacion.Name = "VueloOrientacion"
	orientacion.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientacion.Attachment0 = attachment
	orientacion.MaxTorque = math.huge
	orientacion.Responsiveness = RESPONSIVIDAD_GIRO
	orientacion.CFrame = root.CFrame.Rotation
	orientacion.Parent = root

	humanoid.PlatformStand = true -- el Humanoid deja de caminar/caer; el Animate detiene sus animaciones

	vuelo = {
		personaje = character,
		humanoid = humanoid,
		root = root,
		attachment = attachment,
		velocidad = velocidad,
		orientacion = orientacion,
		velActual = root.AssemblyLinearVelocity,
		inclinacion = 0,
		mirada = aplanar(root.CFrame.LookVector) or Vector3.new(0, 0, -1),
		conexionPaso = RunService.PreSimulation:Connect(paso),
	}

	PoseVueloController.Aplicar(character, true)
	eventoEstado:FireServer(true)
end

local function desactivar()
	local estado = vuelo
	if not estado then
		return
	end
	vuelo = nil

	estado.conexionPaso:Disconnect()
	estado.velocidad:Destroy()
	estado.orientacion:Destroy()
	estado.attachment:Destroy()

	-- Enderezar el cuerpo para que el Humanoid no aterrice tumbado.
	if estado.root.Parent then
		local posicion = estado.root.Position
		estado.root.CFrame = CFrame.lookAt(posicion, posicion + estado.mirada)
	end
	if estado.humanoid.Parent then
		estado.humanoid.PlatformStand = false
		if estado.humanoid.Health > 0 then
			estado.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	PoseVueloController.Aplicar(estado.personaje, false) -- restaura los C0 originales
	EfectosController.SonidoVuelo(false, 0)
	eventoEstado:FireServer(false)
end

local function alternar()
	if vuelo then
		desactivar()
	else
		activar()
	end
end

local conexionMuerte: RBXScriptConnection? = nil

local function alAparecerPersonaje(character: Model)
	desactivar()
	personaje = character
	if conexionMuerte then
		conexionMuerte:Disconnect() -- la del personaje anterior
		conexionMuerte = nil
	end
	corriendo = false
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Juego.Carrera.VelocidadNormal
		conexionMuerte = humanoid.Died:Connect(desactivar)
	end
end

local function alPulsar(input: InputObject, procesado: boolean)
	if UserInputService:GetFocusedTextBox() then
		return -- escribiendo en el chat u otro TextBox
	end

	local tecla = input.KeyCode
	if tecla == Enum.KeyCode.F or tecla == Enum.KeyCode.ButtonY then
		if not procesado then
			alternar()
		end
	elseif tecla == Enum.KeyCode.Space or tecla == Enum.KeyCode.ButtonA then
		-- No se filtra por "procesado": el salto por defecto también usa Espacio.
		local ahora = os.clock()
		if ahora - ultimoSalto <= VENTANA_DOBLE_SALTO then
			ultimoSalto = 0
			alternar()
		else
			ultimoSalto = ahora
		end
	end
end

-- Botón VOLAR del HUD (móvil): igual que F o doble Espacio.
function VueloController.Alternar()
	alternar()
end

function VueloController.EstaVolando(): boolean
	return vuelo ~= nil
end

-- Fija la velocidad de vuelo de golpe (p. ej. Impulso Relámpago); luego vuelve sola a la normal.
function VueloController.Impulsar(velocidad: Vector3)
	local estado = vuelo
	if estado then
		estado.velActual = velocidad
		estado.velocidad.VectorVelocity = velocidad
	end
end

function VueloController.Init()
	eventoEstado = Remotes.Evento("EstadoVuelo")
	eventoCarrera = Remotes.Evento("EstadoCarrera")
	buscarControles()
end

function VueloController.Start()
	jugador.CharacterAdded:Connect(alAparecerPersonaje)
	jugador.CharacterRemoving:Connect(function()
		desactivar()
	end)
	if jugador.Character then
		task.spawn(alAparecerPersonaje, jugador.Character)
	end

	UserInputService.InputBegan:Connect(alPulsar)
	RunService.Heartbeat:Connect(actualizarCarrera)
end

return VueloController
