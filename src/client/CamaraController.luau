--!strict
-- CamaraController: que los monstruos nunca tapen la pantalla (solo visual, en este cliente).
--   • Si un monstruo queda entre la cámara y la heroína (o la cámara está dentro de él), sus piezas
--     se vuelven semitransparentes con LocalTransparencyModifier y se apaga su contorno.
--   • Cerca de monstruos grandes y jefes la cámara se aleja un poco (CameraMinZoomDistance).
--   • La barra de vida/nombre de cada monstruo se ajusta a la pantalla y se oculta si quedaría
--     sobre la interfaz de arriba (monedas, OLEADA) o si el monstruo está pegado a la cámara.
--   • Los demás carteles 3D (BillboardGui: NPC, plataformas, edificios) se ocultan mientras su
--     rectángulo en pantalla se monte sobre la interfaz (tarjeta, monedas, radar, botones...).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local UIController = require(script.Parent.UIController)

local jugador = Players.LocalPlayer

local TRANSPARENCIA_TAPANDO = 0.72 -- cuánto se transparenta un monstruo que tapa a la heroína
local VELOCIDAD_FUNDIDO = 10 -- 1/s
local TAMANO_GRANDE = 24 -- studs (diagonal): monstruo "grande" (Brutón, jefes)
local DISTANCIA_ALEJAR = 45 -- studs: cerca de un grande, la cámara se aleja
local ZOOM_MINIMO_GRANDE = 16
local MARGEN_CAJA = 0.85 -- la caja del modelo es generosa (brazos abiertos): se encoge un poco
local ZONA_HUD_ARRIBA = 0.2 -- fracción superior de la pantalla reservada a la interfaz
local DISTANCIA_BARRA_MINIMA = 14 -- studs cámara-monstruo por debajo de los cuales se oculta su barra
local TAMANO_BARRA = Vector2.new(170, 40) -- px de diseño (escala 1)

type EstadoMonstruo = {
	opacidad: number, -- 0 = normal, 1 = totalmente "tapando"
}

local estados: { [Model]: EstadoMonstruo } = {}
local carteles: { [BillboardGui]: boolean } = {} -- carteles 3D vigilados
local ocultosPorHud: { [BillboardGui]: boolean } = {} -- los que ESTE script apagó
local INTERVALO_CARTELES = 0.1
local revisarCarteles: (camara: Camera) -> () -- se define más abajo
local proximaRevisionCarteles = 0
local zoomOriginal: number? = nil

local CamaraController = {}

local function estadoDe(modelo: Model): EstadoMonstruo
	local estado = estados[modelo]
	if estado then
		return estado
	end
	local nuevo: EstadoMonstruo = { opacidad = 0 }
	estados[modelo] = nuevo
	return nuevo
end

-- ¿El segmento a→b cruza la caja orientada (o empieza dentro)? Método de las placas.
local function segmentoCruzaCaja(a: Vector3, b: Vector3, caja: CFrame, tamano: Vector3): boolean
	local la = caja:PointToObjectSpace(a)
	local lb = caja:PointToObjectSpace(b)
	local medio = tamano / 2
	local d = lb - la
	local tMin, tMax = 0, 1
	for _, eje in { "X", "Y", "Z" } do
		local origen = (la :: any)[eje] :: number
		local delta = (d :: any)[eje] :: number
		local m = (medio :: any)[eje] :: number
		if math.abs(delta) < 1e-6 then
			if origen < -m or origen > m then
				return false
			end
		else
			local t1 = (-m - origen) / delta
			local t2 = (m - origen) / delta
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return false
			end
		end
	end
	return true
end

local function escalaPantalla(camara: Camera): number
	local vista = camara.ViewportSize
	return math.clamp(math.min(vista.X / 1000, vista.Y / 540), 0.6, 1)
end

local function actualizarBarra(modelo: Model, camara: Camera, escala: number)
	local raiz = modelo:FindFirstChild("HumanoidRootPart")
	local barra = if raiz then raiz:FindFirstChild("BarraVida") else nil
	if not barra or not barra:IsA("BillboardGui") then
		return
	end
	barra.Size = UDim2.fromOffset(TAMANO_BARRA.X * escala, TAMANO_BARRA.Y * escala)
	local ancla = (raiz :: BasePart).Position + barra.StudsOffsetWorldSpace
	local enPantalla, visible = camara:WorldToViewportPoint(ancla)
	local cerca = (camara.CFrame.Position - (raiz :: BasePart).Position).Magnitude < DISTANCIA_BARRA_MINIMA
	local sobreHud = visible and enPantalla.Y < camara.ViewportSize.Y * ZONA_HUD_ARRIBA
	barra.Enabled = not cerca and not sobreHud
end

local function actualizar(dt: number)
	local camara = Workspace.CurrentCamera
	local character = jugador.Character
	if not camara then
		return
	end
	local cabeza = if character then character:FindFirstChild("Head") else nil
	local foco = if cabeza and cabeza:IsA("BasePart") then cabeza.Position else camara.Focus.Position
	local posicionCamara = camara.CFrame.Position
	local escala = escalaPantalla(camara)
	local hayGrandeCerca = false
	local paso = math.min(1, dt * VELOCIDAD_FUNDIDO)

	local vistos: { [Model]: boolean } = {}
	for _, instancia in CollectionService:GetTagged("Enemigo") do
		if not instancia:IsA("Model") or not instancia:IsDescendantOf(Workspace) then
			continue
		end
		local modelo = instancia :: Model
		vistos[modelo] = true
		local caja, tamano = modelo:GetBoundingBox()
		local grande = tamano.Magnitude >= TAMANO_GRANDE
		if grande and (caja.Position - foco).Magnitude < DISTANCIA_ALEJAR then
			hayGrandeCerca = true
		end

		-- ¿Tapa a la heroína?
		local tapando = segmentoCruzaCaja(posicionCamara, foco, caja, tamano * MARGEN_CAJA)
		local estado = estadoDe(modelo)
		local objetivo = if tapando then 1 else 0
		if estado.opacidad ~= objetivo then
			estado.opacidad += (objetivo - estado.opacidad) * paso
			if math.abs(estado.opacidad - objetivo) < 0.02 then
				estado.opacidad = objetivo
			end
			-- Las piezas se leen en cada fundido (el modelo puede seguir llegando por red al
			-- aparecer); solo ocurre mientras cambia la opacidad, no cada frame.
			local modificador = estado.opacidad * TRANSPARENCIA_TAPANDO
			for _, d in modelo:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = modificador
				elseif d:IsA("Highlight") then
					d.Enabled = estado.opacidad < 0.5
				end
			end
		end

		actualizarBarra(modelo, camara, escala)
	end
	if os.clock() >= proximaRevisionCarteles then
		proximaRevisionCarteles = os.clock() + INTERVALO_CARTELES
		revisarCarteles(camara)
	end
	-- Monstruos que ya no están: olvidar su estado
	for modelo in estados do
		if not vistos[modelo] then
			estados[modelo] = nil
		end
	end

	-- Alejar la cámara un poco cerca de monstruos grandes y jefes
	if hayGrandeCerca then
		if zoomOriginal == nil then
			zoomOriginal = jugador.CameraMinZoomDistance
		end
		jugador.CameraMinZoomDistance = math.max(zoomOriginal :: number, ZOOM_MINIMO_GRANDE)
	elseif zoomOriginal ~= nil then
		jugador.CameraMinZoomDistance = zoomOriginal :: number
		zoomOriginal = nil
	end
end

-- Posición en el mundo de un cartel (adornee o padre) con sus desplazamientos.
local function posicionCartel(cartel: BillboardGui, camara: Camera): Vector3?
	local base = cartel.Adornee or cartel.Parent
	local posicion: Vector3
	if base and base:IsA("BasePart") then
		posicion = base.Position
	elseif base and base:IsA("Attachment") then
		posicion = base.WorldPosition
	elseif base and base:IsA("Model") then
		posicion = base:GetPivot().Position
	else
		return nil
	end
	local giro = camara.CFrame
	local o = cartel.StudsOffset
	return posicion + cartel.StudsOffsetWorldSpace + giro.RightVector * o.X + giro.UpVector * o.Y - giro.LookVector * o.Z
end

revisarCarteles = function(camara: Camera)
	local zonas = UIController.ZonasHud()
	local inset = GuiService:GetGuiInset()
	local vista = camara.ViewportSize
	local factorStud = vista.Y / (2 * math.tan(math.rad(camara.FieldOfView) / 2))
	for cartel in carteles do
		if not cartel:IsDescendantOf(Workspace) then
			carteles[cartel] = nil
			ocultosPorHud[cartel] = nil
			continue
		end
		local posicion = posicionCartel(cartel, camara)
		local tapa = false
		if posicion then
			local punto, delante = camara:WorldToViewportPoint(posicion)
			local distancia = (posicion - camara.CFrame.Position).Magnitude
			if delante and distancia <= cartel.MaxDistance then
				-- Tamaño en píxeles: offset directo, o studs convertidos según la distancia
				local tam = cartel.Size
				local px = factorStud / math.max(distancia, 1)
				local ancho = tam.X.Offset + tam.X.Scale * px
				local alto = tam.Y.Offset + tam.Y.Scale * px
				-- Rectángulo del cartel en coordenadas de la interfaz (sin la barra superior)
				local centro = Vector2.new(punto.X, punto.Y) - inset
				local minimo = centro - Vector2.new(ancho, alto) / 2
				local maximo = centro + Vector2.new(ancho, alto) / 2
				for _, zona in zonas do
					local zMin = zona.AbsolutePosition
					local zMax = zMin + zona.AbsoluteSize
					if minimo.X < zMax.X and maximo.X > zMin.X and minimo.Y < zMax.Y and maximo.Y > zMin.Y then
						tapa = true
						break
					end
				end
			end
		end
		if tapa and cartel.Enabled then
			cartel.Enabled = false
			ocultosPorHud[cartel] = true
		elseif not tapa and ocultosPorHud[cartel] then
			cartel.Enabled = true
			ocultosPorHud[cartel] = nil
		end
	end
end

local function vigilarCartel(instancia: Instance)
	if not instancia:IsA("BillboardGui") or instancia:IsDescendantOf(Workspace.Terrain) then
		return -- los números de daño (en el Terrain) son efímeros
	end
	if instancia.Name == "BarraVida" then
		return -- las barras de monstruo tienen su propia regla
	end
	local character = jugador.Character
	if character and instancia:IsDescendantOf(character) then
		return
	end
	carteles[instancia] = true
end

function CamaraController.Init() end

function CamaraController.Start()
	for _, d in Workspace:GetDescendants() do
		vigilarCartel(d)
	end
	Workspace.DescendantAdded:Connect(vigilarCartel)
	-- Justo después de que la cámara de Roblox calcule su posición
	RunService:BindToRenderStep("SugarTownCamaraMonstruos", Enum.RenderPriority.Camera.Value + 2, actualizar)
end

return CamaraController
