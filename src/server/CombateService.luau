--!strict
-- CombateService: ejecuta los poderes de forma autoritativa.
-- El cliente solo envía (ranura, punto al que apunta). El servidor:
--   1) valida tipos, que el personaje esté vivo y el enfriamiento del poder del arquetipo ACTUAL,
--   2) calcula impactos desde la posición REAL del personaje en el servidor (alcances y radios
--      salen de Config/Poderes, nunca del cliente),
--   3) aplica daño/efectos y avisa a todos los clientes para que dibujen los visuales.
-- Los enemigos son Modelos con Humanoid y la etiqueta (CollectionService) "Enemigo".

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Armas = require(Shared.Config.Armas)
local Combate = require(Shared.Config.Combate)
local Heroinas = require(Shared.Config.Heroinas)
local Mejoras = require(Shared.Config.Mejoras)
local Poderes = require(Shared.Config.Poderes)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local HeroinaService = require(script.Parent.HeroinaService)

type PoderConfig = Types.PoderConfig

local ETIQUETA_ENEMIGO = "Enemigo"
local RECOMPENSA_POR_DEFECTO = 10
local TOLERANCIA_ENFRIAMIENTO = 0.15 -- margen por latencia de red
local COORDENADA_MAXIMA = 1e5 -- descarta vectores absurdos/NaN/infinito
local NOMBRE_ESCUDO = "EscudoHeroina"
local NOMBRE_RALENTIZADO = "Ralentizado"

local enfriamientos: { [Player]: { [string]: number } } = {}
local eventoEfecto: RemoteEvent
local eventoNumero: RemoteEvent
local eventoGolpe: RemoteEvent

-- Estado del combo cuerpo a cuerpo de cada jugadora (solo lo escribe el servidor).
type EstadoCombo = {
	paso: number, -- último golpe lanzado (1..#Combate.Golpes)
	ultimoGolpe: number,
	listoEn: number, -- os.clock() a partir del cual se acepta el siguiente golpe
	conteo: number, -- golpes acertados seguidos (contador "xN COMBO!")
	ultimoAcierto: number,
}
local combos: { [Player]: EstadoCombo } = {}

-- Límite de frecuencia por jugadora y remote (cubo de fichas): frena a quien dispare el remote en bucle.
type Cubo = { fichas: number, ultimo: number }
local cubos: { [Player]: { [string]: Cubo } } = {}

local function permitir(jugador: Player, clave: string, porSegundo: number, rafaga: number): boolean
	local ahora = os.clock()
	local deJugador = cubos[jugador]
	if not deJugador then
		deJugador = {}
		cubos[jugador] = deJugador
	end
	local cubo = deJugador[clave]
	if not cubo then
		cubo = { fichas = rafaga, ultimo = ahora }
		deJugador[clave] = cubo
	end
	cubo.fichas = math.min(rafaga, cubo.fichas + (ahora - cubo.ultimo) * porSegundo)
	cubo.ultimo = ahora
	if cubo.fichas < 1 then
		return false
	end
	cubo.fichas -= 1
	return true
end

local CombateService = {}

-- ─── Utilidades ──────────────────────────────────────────────────────────────

local function esVectorValido(v: unknown): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local vector = v :: Vector3
	for _, c in { vector.X, vector.Y, vector.Z } do
		if c ~= c or math.abs(c) > COORDENADA_MAXIMA then
			return false
		end
	end
	return true
end

local function obtenerRaiz(character: Model?): BasePart?
	if not character then
		return nil
	end
	local raiz = character:FindFirstChild("HumanoidRootPart")
	if raiz and raiz:IsA("BasePart") then
		return raiz
	end
	return nil
end

local function humanoideVivo(modelo: Model): Humanoid?
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Sube por los ancestros de una pieza golpeada hasta encontrar un enemigo vivo.
local function enemigoDesdeInstancia(instancia: Instance?): Model?
	local actual = instancia
	while actual and actual ~= Workspace do
		if actual:IsA("Model") and CollectionService:HasTag(actual, ETIQUETA_ENEMIGO) then
			return if humanoideVivo(actual) then actual else nil
		end
		actual = actual.Parent
	end
	return nil
end

-- Enemigos vivos cuyo cuerpo toca la esfera (usa el tamaño del modelo: sirve para monstruos gigantes).
local function enemigosEnRadio(centro: Vector3, radio: number): { Model }
	local resultado = {}
	for _, instancia in CollectionService:GetTagged(ETIQUETA_ENEMIGO) do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) and humanoideVivo(instancia) then
			local pivote = instancia:GetPivot().Position
			local medioTamano = instancia:GetExtentsSize().Magnitude / 2
			if (pivote - centro).Magnitude <= radio + medioTamano then
				table.insert(resultado, instancia)
			end
		end
	end
	return resultado
end

local function distanciaASegmento(punto: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local largo2 = ab:Dot(ab)
	if largo2 < 1e-6 then
		return (punto - a).Magnitude
	end
	local t = math.clamp((punto - a):Dot(ab) / largo2, 0, 1)
	return (punto - (a + ab * t)).Magnitude
end

local function enemigosEnCapsula(a: Vector3, b: Vector3, radio: number): { Model }
	local resultado = {}
	for _, instancia in CollectionService:GetTagged(ETIQUETA_ENEMIGO) do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) and humanoideVivo(instancia) then
			local medioTamano = instancia:GetExtentsSize().Magnitude / 2
			if distanciaASegmento(instancia:GetPivot().Position, a, b) <= radio + medioTamano then
				table.insert(resultado, instancia)
			end
		end
	end
	return resultado
end

-- Los rayos atraviesan a todas las jugadoras (no hay fuego amigo).
local function parametrosSinJugadoras(): RaycastParams
	local excluir: { Instance } = {}
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(excluir, jugador.Character)
		end
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	return parametros
end

-- Fin del haz láser: atraviesa jugadoras y monstruos (daña a toda la línea) pero lo para el escenario.
local function finDelLaser(origen: Vector3, direccion: Vector3, alcance: number): Vector3
	local excluir: { Instance } = CollectionService:GetTagged(ETIQUETA_ENEMIGO)
	for _, jugador in Players:GetPlayers() do
		if jugador.Character then
			table.insert(excluir, jugador.Character)
		end
	end
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.FilterDescendantsInstances = excluir
	local resultado = Workspace:Raycast(origen, direccion * alcance, parametros)
	return if resultado then resultado.Position else origen + direccion * alcance
end

local function lanzarProyectil(origen: Vector3, direccion: Vector3, poder: PoderConfig): Model?
	local resultado = Workspace:Spherecast(origen, poder.Radio, direccion.Unit * poder.Alcance, parametrosSinJugadoras())
	return if resultado then enemigoDesdeInstancia(resultado.Instance) else nil
end

local function empujar(enemigo: Model, desde: Vector3, velocidad: number)
	local raiz = obtenerRaiz(enemigo) or enemigo.PrimaryPart
	if not raiz or raiz.Anchored or velocidad <= 0 then
		return
	end
	local direccion = raiz.Position - desde
	direccion = if direccion.Magnitude > 0.1 then direccion.Unit else Vector3.yAxis
	raiz.AssemblyLinearVelocity += (direccion + Vector3.new(0, 0.5, 0)).Unit * velocidad
end

local function ralentizar(enemigo: Model, multiplicador: number, duracion: number)
	local humanoid = humanoideVivo(enemigo)
	if not humanoid then
		return
	end
	local base = enemigo:GetAttribute("VelocidadBase")
	if typeof(base) ~= "number" then
		base = humanoid.WalkSpeed
		enemigo:SetAttribute("VelocidadBase", base)
	end
	humanoid.WalkSpeed = (base :: number) * multiplicador

	local hasta = os.clock() + duracion
	enemigo:SetAttribute("RalentizadoHasta", hasta)

	-- Se tiñe de verde el Highlight de contorno que ya tiene el monstruo (no se crea otro:
	-- Roblox solo dibuja 31 Highlight a la vez). Si no tiene, se crea uno temporal.
	local resaltado = enemigo:FindFirstChildOfClass("Highlight")
	if not resaltado then
		local nuevo = Instance.new("Highlight")
		nuevo.Name = NOMBRE_RALENTIZADO
		nuevo.OutlineColor = Color3.new(0, 0, 0)
		nuevo.Parent = enemigo
		resaltado = nuevo
	end
	if resaltado then
		resaltado.FillColor = Color3.fromRGB(80, 255, 140)
		resaltado.FillTransparency = 0.55
	end

	task.delay(duracion, function()
		-- Solo restaura si nadie volvió a ralentizarlo mientras tanto.
		if enemigo:GetAttribute("RalentizadoHasta") ~= hasta then
			return
		end
		humanoid.WalkSpeed = base :: number
		enemigo:SetAttribute("RalentizadoHasta", nil)
		local actual = enemigo:FindFirstChildOfClass("Highlight")
		if actual then
			if actual.Name == NOMBRE_RALENTIZADO then
				actual:Destroy()
			else
				actual.FillTransparency = 1
			end
		end
	end)
end

local function aplicarEscudo(character: Model, poder: PoderConfig)
	local raiz = obtenerRaiz(character)
	if not raiz then
		return
	end
	for _, nombre in { NOMBRE_ESCUDO, NOMBRE_ESCUDO .. "FF" } do
		local anterior = character:FindFirstChild(nombre)
		if anterior then
			anterior:Destroy()
		end
	end

	-- El ForceField (invisible) hace que Humanoid:TakeDamage no tenga efecto: protección real.
	local campo = Instance.new("ForceField")
	campo.Name = NOMBRE_ESCUDO .. "FF"
	campo.Visible = false
	campo.Parent = character

	local esfera = Instance.new("Part")
	esfera.Name = NOMBRE_ESCUDO
	esfera.Shape = Enum.PartType.Ball
	esfera.Size = Vector3.one * 9
	esfera.Material = Enum.Material.ForceField
	esfera.Transparency = 0.65 -- translúcida: nunca tapa la visión
	esfera.Color = poder.Color
	esfera.CanCollide = false
	esfera.CanQuery = false
	esfera.CanTouch = false
	esfera.Massless = true
	esfera.CastShadow = false
	esfera.CFrame = raiz.CFrame
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = raiz
	soldadura.Part1 = esfera
	soldadura.Parent = esfera
	esfera.Parent = character

	Debris:AddItem(campo, poder.Duracion)
	Debris:AddItem(esfera, poder.Duracion)
end

-- ─── API pública ─────────────────────────────────────────────────────────────

function CombateService.EsEnemigo(modelo: Instance): boolean
	return CollectionService:HasTag(modelo, ETIQUETA_ENEMIGO)
end

function CombateService.TieneEscudo(character: Model): boolean
	return character:FindFirstChild(NOMBRE_ESCUDO .. "FF") ~= nil
end

-- Número de daño flotante (lo dibuja cada cliente en EfectosController).
function CombateService.MostrarNumero(posicion: Vector3, cantidad: number, color: Color3, grande: boolean)
	eventoNumero:FireAllClients(posicion, math.floor(cantidad + 0.5), color, grande)
end

-- Daña a un enemigo y, si lo derrota, da monedas y experiencia (una sola vez) a quien lo derrotó.
function CombateService.AplicarDano(atacante: Player, enemigo: Model, cantidad: number, color: Color3?, cargaEnergia: boolean?)
	local humanoid = humanoideVivo(enemigo)
	if not humanoid or cantidad <= 0 then
		return
	end
	local vidaAntes = humanoid.Health
	-- Antes del daño: así quien maneje Humanoid.Died sabe quién lo derrotó (monedas que vuelan hacia ella)
	enemigo:SetAttribute("UltimoAtacante", atacante.UserId)
	humanoid:TakeDamage(cantidad)
	local hecho = vidaAntes - humanoid.Health
	local derrotado = humanoid.Health <= 0

	if hecho > 0 and cargaEnergia ~= false then
		local energia = atacante:GetAttribute("Energia")
		local actual = if typeof(energia) == "number" then energia else 0
		atacante:SetAttribute("Energia", math.min(Poderes.EnergiaMaxima, actual + hecho * Poderes.EnergiaPorDano))
	end

	if hecho > 0 then
		local altura = enemigo:GetExtentsSize().Y / 2
		CombateService.MostrarNumero(enemigo:GetPivot().Position + Vector3.new(0, altura, 0), hecho, color or Color3.new(1, 1, 1), derrotado)
	end

	if derrotado and enemigo:GetAttribute("Recompensado") ~= true then
		enemigo:SetAttribute("Recompensado", true)
		HeroinaService.SumarDerrotado(atacante)
		local recompensa = enemigo:GetAttribute("Recompensa")
		local experiencia = enemigo:GetAttribute("Experiencia")
		HeroinaService.SumarMonedasGanadas(atacante, if typeof(recompensa) == "number" then recompensa else RECOMPENSA_POR_DEFECTO)
		if typeof(experiencia) == "number" and experiencia > 0 then
			HeroinaService.SumarExperiencia(atacante, experiencia)
		end
	end
end

-- ─── Ejecución de poderes ────────────────────────────────────────────────────

local function ejecutarPoder(jugador: Player, raiz: BasePart, poder: PoderConfig, objetivo: Vector3)
	local origen = raiz.Position
	local haciaObjetivo = objetivo - origen
	local direccion = if haciaObjetivo.Magnitude > 0.1 then haciaObjetivo.Unit else raiz.CFrame.LookVector
	-- Daño con la mejora comprada para la heroína ACTUAL (leída del atributo que solo escribe el servidor)
	local arquetipo = Heroinas.Obtener(jugador:GetAttribute("Arquetipo")).Id
	local dano = poder.Dano * Mejoras.Multiplicador(jugador, arquetipo, "Dano")

	if poder.Tipo == "Rayo" then
		local enemigo = lanzarProyectil(origen, direccion, poder)
		if enemigo then
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
		end
	elseif poder.Tipo == "Rafaga" then
		local aleatorio = Random.new()
		local dispersion = math.rad(poder.Dispersion)
		for _ = 1, poder.Cantidad do
			local giro = CFrame.Angles(
				aleatorio:NextNumber(-dispersion, dispersion),
				aleatorio:NextNumber(-dispersion, dispersion),
				0
			)
			local enemigo = lanzarProyectil(origen, (CFrame.lookAt(Vector3.zero, direccion) * giro).LookVector, poder)
			if enemigo then
				CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
			end
		end
	elseif poder.Tipo == "Onda" then
		for _, enemigo in enemigosEnRadio(origen, poder.Radio) do
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
			empujar(enemigo, origen, poder.Empuje)
		end
	elseif poder.Tipo == "Impulso" then
		-- La jugadora se mueve en su cliente; el servidor golpea a lo largo de la trayectoria máxima.
		local fin = origen + direccion * poder.Alcance
		for _, enemigo in enemigosEnCapsula(origen, fin, poder.Radio) do
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
		end
	elseif poder.Tipo == "Escudo" then
		for _, otro in Players:GetPlayers() do
			local otroCharacter = otro.Character
			local otraRaiz = obtenerRaiz(otroCharacter)
			if otroCharacter and otraRaiz and humanoideVivo(otroCharacter) then
				if otro == jugador or (otraRaiz.Position - origen).Magnitude <= poder.Radio then
					aplicarEscudo(otroCharacter, poder)
				end
			end
		end
	elseif poder.Tipo == "Dulce" then
		-- Caramelo: proyectil recto contra el primer monstruo de la línea. Atraviesa árboles y
		-- decorados (solo choca con monstruos) para que en una ciudad llena siempre se pueda usar.
		local soloEnemigos = RaycastParams.new()
		soloEnemigos.FilterType = Enum.RaycastFilterType.Include
		soloEnemigos.FilterDescendantsInstances = CollectionService:GetTagged(ETIQUETA_ENEMIGO)
		local golpe = Workspace:Spherecast(origen, poder.Radio, direccion * poder.Alcance, soloEnemigos)
		local enemigo = if golpe then enemigoDesdeInstancia(golpe.Instance) else nil
		if enemigo then
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
		end
	elseif poder.Tipo == "Martillo" then
		-- Golpe al suelo delante de la heroína: área + empuje
		local plano = Vector3.new(direccion.X, 0, direccion.Z)
		local centro = origen + (if plano.Magnitude > 0.01 then plano.Unit else Vector3.zero) * poder.Alcance
		for _, enemigo in enemigosEnRadio(centro, poder.Radio) do
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
			empujar(enemigo, centro, poder.Empuje)
		end
	elseif poder.Tipo == "Estrellas" then
		-- Una estrella por monstruo, los más cercanos dentro del alcance
		local candidatos = {}
		for _, enemigo in enemigosEnRadio(origen, poder.Alcance) do
			table.insert(candidatos, { enemigo = enemigo, distancia = (enemigo:GetPivot().Position - origen).Magnitude })
		end
		table.sort(candidatos, function(a, b)
			return a.distancia < b.distancia
		end)
		for i = 1, math.min(poder.Cantidad, #candidatos) do
			CombateService.AplicarDano(jugador, candidatos[i].enemigo, dano, poder.Color)
		end
	elseif poder.Tipo == "Laser" then
		-- Daño en línea: todos los monstruos que toca el haz, una vez cada uno
		local fin = finDelLaser(origen, direccion, poder.Alcance)
		for _, enemigo in enemigosEnCapsula(origen, fin, poder.Radio) do
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
		end
	elseif poder.Tipo == "Pulso" then
		for _, enemigo in enemigosEnRadio(origen, poder.Radio) do
			CombateService.AplicarDano(jugador, enemigo, dano, poder.Color)
			ralentizar(enemigo, poder.Ralentizacion, poder.Duracion)
		end
	end
end

local function alUsarPoder(jugador: Player, ranura: unknown, objetivo: unknown)
	if not permitir(jugador, "UsarPoder", 6, 4) then
		return
	end
	-- 1) Validar tipos
	if not Poderes.EsRanura(ranura) or not esVectorValido(objetivo) then
		return
	end
	local character = jugador.Character
	local raiz = obtenerRaiz(character)
	if not character or not raiz or not humanoideVivo(character) then
		return
	end
	if character:GetAttribute("Aturdida") == true or character:GetAttribute("Derribada") == true then
		return
	end

	-- 2) El poder sale del arquetipo que el SERVIDOR tiene asignado, y debe estar desbloqueado
	--    por el nivel de la jugadora (atributo que solo escribe el servidor)
	local poder = Poderes.Obtener(jugador:GetAttribute("Arquetipo"), ranura :: Types.Ranura)
	--    (antes del nivel permanente, el láser va por tiempo: el SERVIDOR abre la ventana activa al
	--    primer uso y escribe las horas de fin y de recarga; durante la recarga se rechaza)
	local ahoraServidor = Workspace:GetServerTimeNow()
	local estadoUso = Poderes.EstadoUso(jugador, poder, ahoraServidor)
	if estadoUso == "Bloqueado" or estadoUso == "Recarga" then
		return
	end

	-- 3) Enfriamiento
	local ahora = os.clock()
	local tabla = enfriamientos[jugador]
	if not tabla then
		tabla = {}
		enfriamientos[jugador] = tabla
	end
	local listoEn = tabla[poder.Id] or 0
	if ahora < listoEn - TOLERANCIA_ENFRIAMIENTO then
		return
	end
	tabla[poder.Id] = ahora + poder.Enfriamiento
	if estadoUso == "Listo" then
		local temporal = Poderes.LaserTemporal
		jugador:SetAttribute(Poderes.AtributoLaserActivo, ahoraServidor + temporal.Activo)
		jugador:SetAttribute(Poderes.AtributoLaserRecarga, ahoraServidor + temporal.Activo + temporal.Recarga)
	end

	-- 4) Avisar a los clientes (cada uno dibuja los efectos) y ejecutar. Con carga (láser), el
	--    daño llega al terminar la carga, desde donde esté la heroína en ese momento.
	eventoEfecto:FireAllClients(jugador, poder.Id, objetivo)
	if poder.Carga > 0 then
		task.delay(poder.Carga, function()
			local raizAhora = obtenerRaiz(jugador.Character)
			if jugador.Character ~= character or not raizAhora or not humanoideVivo(character) then
				return
			end
			if character:GetAttribute("Aturdida") == true then
				return
			end
			ejecutarPoder(jugador, raizAhora, poder, objetivo :: Vector3)
		end)
	else
		ejecutarPoder(jugador, raiz, poder, objetivo :: Vector3)
	end
end

-- ─── Armas (Config/Armas) ────────────────────────────────────────────────────

-- El cliente solo envía (clave del arma, punto apuntado). El servidor comprueba que la TIENE
-- (pase o desbloqueo con monedas), su enfriamiento y el estado de la heroína.
local function alUsarArma(jugador: Player, clave: unknown, objetivo: unknown)
	if not permitir(jugador, "UsarArma", 6, 4) then
		return
	end
	local arma = Armas.PorClave(clave)
	if not arma or not esVectorValido(objetivo) or not Armas.Tiene(jugador, arma.Clave) then
		return
	end
	local character = jugador.Character
	local raiz = obtenerRaiz(character)
	if not character or not raiz or not humanoideVivo(character) then
		return
	end
	if character:GetAttribute("Aturdida") == true or character:GetAttribute("Derribada") == true then
		return
	end
	local poder = arma.Poder
	local ahora = os.clock()
	local tabla = enfriamientos[jugador]
	if not tabla then
		tabla = {}
		enfriamientos[jugador] = tabla
	end
	if ahora < (tabla[poder.Id] or 0) - TOLERANCIA_ENFRIAMIENTO then
		return
	end
	tabla[poder.Id] = ahora + poder.Enfriamiento
	eventoEfecto:FireAllClients(jugador, poder.Id, objetivo)
	ejecutarPoder(jugador, raiz, poder, objetivo :: Vector3)
end

-- ─── Combo cuerpo a cuerpo ───────────────────────────────────────────────────

-- Distancia de un punto a la caja (orientada) de un modelo y el punto más cercano de la caja.
local function distanciaACaja(punto: Vector3, caja: CFrame, tamano: Vector3): (number, Vector3)
	local relativo = caja:PointToObjectSpace(punto)
	local medio = tamano / 2
	local cercano = Vector3.new(
		math.clamp(relativo.X, -medio.X, medio.X),
		math.clamp(relativo.Y, -medio.Y, medio.Y),
		math.clamp(relativo.Z, -medio.Z, medio.Z)
	)
	local mundo = caja:PointToWorldSpace(cercano)
	return (punto - mundo).Magnitude, mundo
end

-- Monstruo vivo más cercano al alcance del golpe y delante de la heroína (o casi pegado a ella).
local function objetivoCuerpoACuerpo(origen: Vector3, direccion: Vector3, alcance: number): (Model?, Vector3?)
	local mejor: Model? = nil
	local mejorPunto: Vector3? = nil
	local mejorDistancia = math.huge
	for _, instancia in CollectionService:GetTagged(ETIQUETA_ENEMIGO) do
		if instancia:IsA("Model") and instancia:IsDescendantOf(Workspace) and humanoideVivo(instancia) then
			local caja, tamano = instancia:GetBoundingBox()
			local distancia, punto = distanciaACaja(origen, caja, tamano)
			if distancia <= alcance and distancia < mejorDistancia then
				local hacia = punto - origen
				local plano = Vector3.new(hacia.X, 0, hacia.Z)
				local delante = distancia < 2.5 or plano.Magnitude < 0.5 or plano.Unit:Dot(direccion) >= Combate.ConoFrontal
				if delante then
					mejor, mejorPunto, mejorDistancia = instancia, punto, distancia
				end
			end
		end
	end
	return mejor, mejorPunto
end

-- El cliente solo envía la dirección a la que mira. El servidor decide el paso del combo,
-- valida la recuperación, busca el objetivo desde la posición REAL y aplica el daño de Config.
local function alGolpear(jugador: Player, direccion: unknown)
	if not permitir(jugador, "Golpear", 8, 4) then
		return
	end
	if not esVectorValido(direccion) then
		return
	end
	local character = jugador.Character
	local raiz = obtenerRaiz(character)
	if not character or not raiz or not humanoideVivo(character) then
		return
	end
	if character:GetAttribute("Aturdida") == true or character:GetAttribute("Derribada") == true then
		return -- aturdida (choque con un auto) o derribada: no puede atacar
	end

	local ahora = os.clock()
	local estado = combos[jugador]
	if not estado then
		estado = { paso = 0, ultimoGolpe = -math.huge, listoEn = 0, conteo = 0, ultimoAcierto = -math.huge }
		combos[jugador] = estado
	end
	if ahora < estado.listoEn - Combate.ToleranciaRed then
		return -- aún se recupera del golpe anterior
	end
	local paso = if ahora - estado.ultimoGolpe <= Combate.VentanaCombo then estado.paso % #Combate.Golpes + 1 else 1
	local golpe = Combate.Golpes[paso]
	estado.paso = paso
	estado.ultimoGolpe = ahora
	estado.listoEn = ahora + golpe.Recuperacion

	-- Dirección horizontal normalizada (si llega degenerada, la de la heroína en el servidor)
	local plano = Vector3.new((direccion :: Vector3).X, 0, (direccion :: Vector3).Z)
	local mirada = if plano.Magnitude > 0.01 then plano.Unit else Vector3.new(raiz.CFrame.LookVector.X, 0, raiz.CFrame.LookVector.Z).Unit

	local enemigo, impacto = objetivoCuerpoACuerpo(raiz.Position, mirada, golpe.Alcance)
	local combo = 0
	if enemigo and impacto then
		local config = Heroinas.Obtener(jugador:GetAttribute("Arquetipo"))
		local dano = golpe.Dano * Mejoras.Multiplicador(jugador, config.Id, "Dano")
		CombateService.AplicarDano(jugador, enemigo, dano, config.ColorPrincipal)
		if golpe.Empuje > 0 then
			empujar(enemigo, raiz.Position, golpe.Empuje)
		end
		if ahora - estado.ultimoAcierto > Combate.DuracionContador then
			estado.conteo = 0
		end
		estado.conteo += 1
		estado.ultimoAcierto = ahora
		combo = estado.conteo
		if combo % Combate.CadaCuantosBono == 0 then
			HeroinaService.SumarMonedasGanadas(jugador, Combate.MonedasBono)
		end
	end
	eventoGolpe:FireAllClients(jugador, paso, impacto, enemigo, combo)
end

-- ⭐ Estallido Estelar: consume toda la Esencia Estelar (validada en el servidor).
local function alUsarEstallido(jugador: Player)
	local character = jugador.Character
	local raiz = obtenerRaiz(character)
	if not character or not raiz or not humanoideVivo(character) or character:GetAttribute("Derribada") == true then
		return
	end
	local energia = jugador:GetAttribute("Energia")
	if typeof(energia) ~= "number" or energia < Poderes.EnergiaMaxima then
		return
	end
	jugador:SetAttribute("Energia", 0)

	local poder = Poderes.Especial
	local arquetipo = Heroinas.Obtener(jugador:GetAttribute("Arquetipo")).Id
	local dano = poder.Dano * Mejoras.Multiplicador(jugador, arquetipo, "Dano")
	local origen = raiz.Position
	for _, enemigo in enemigosEnRadio(origen, poder.Radio) do
		CombateService.AplicarDano(jugador, enemigo, dano, poder.Color, false)
		empujar(enemigo, origen, poder.Empuje)
	end
	eventoEfecto:FireAllClients(jugador, poder.Id, origen)
end

function CombateService.Init()
	eventoEfecto = Remotes.Evento("EfectoPoder")
	eventoNumero = Remotes.Evento("NumeroDano")
	Remotes.Evento("UsarPoder").OnServerEvent:Connect(alUsarPoder)
	Remotes.Evento("UsarEstallido").OnServerEvent:Connect(alUsarEstallido)
	eventoGolpe = Remotes.Evento("EfectoGolpe")
	Remotes.Evento("Golpear").OnServerEvent:Connect(alGolpear)
	Remotes.Evento("UsarArma").OnServerEvent:Connect(alUsarArma)
	Players.PlayerRemoving:Connect(function(jugador)
		enfriamientos[jugador] = nil
		combos[jugador] = nil
		cubos[jugador] = nil
	end)
end

return CombateService
