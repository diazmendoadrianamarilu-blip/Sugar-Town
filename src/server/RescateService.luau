--!strict
-- RescateService: derrota y rescate de heroínas en la ciudad (el servidor decide todo).
--   • Los monstruos no matan: el daño pasa por RescateService.Danar. Si llegaría a 0, la heroína
--     queda DERRIBADA (vida 1, no puede atacar ni volar, los monstruos la ignoran).
--   • SOLO (nadie más en pie en la ciudad): oferta inmediata → revivir con Robux o volver al lobby.
--   • Grupo: una compañera en pie la SALVA manteniendo pulsado el ProximityPrompt "Salvar",
--     o ella misma paga YA el producto "Revivir" (botón "REVIVIR YA" mientras espera).
--     Si caen todas, o pasa Juego.Rescate.EsperaRescate sin ayuda, cada una recibe la oferta.
--   • La oferta caduca a los TiempoOferta s → lobby. "Pagar" usa el producto "Revivir" de
--     Config/TiendaRobux (Id 0 = compra simulada en Studio). Si una compra llega cuando ya no está
--     derribada, se guarda como "revivir guardado" y se usa sola la próxima vez.
-- Atributos: personaje → "Derribada"; jugador → "RescateEstado" ("Derribada" | "Oferta"),
-- "RescateHasta" (hora del servidor en que caduca la espera/oferta), "RevivirGuardado".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Juego = require(Shared.Config.Juego)
local Remotes = require(Shared.Remotes)
local TiendaRobux = require(Shared.Config.TiendaRobux)
local LobbyService = require(script.Parent.LobbyService)

local CONFIG = Juego.Rescate
local NOMBRE_PROMPT = "Rescate"
local NOMBRE_AYUDA = "AyudaRescate"
local NOMBRE_PROTECCION = "ProteccionRescate"
local COLOR_ROSA = Color3.fromRGB(255, 110, 199)
local COLOR_VERDE = Color3.fromRGB(90, 255, 140)

type Estado = "Derribada" | "Oferta"
type Registro = {
	estado: Estado,
	character: Model,
	hasta: number, -- hora del servidor
	comprando: boolean,
}

local registros: { [Player]: Registro } = {}
local eventoAnuncio: RemoteEvent

local RescateService = {}

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

local function anunciar(jugador: Player, titulo: string, subtitulo: string, color: Color3)
	eventoAnuncio:FireClient(jugador, titulo, subtitulo, color)
end

local function humanoideDe(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function ponerEstado(jugador: Player, registro: Registro?)
	if registro then
		jugador:SetAttribute("RescateEstado", registro.estado)
		jugador:SetAttribute("RescateHasta", registro.hasta)
	else
		jugador:SetAttribute("RescateEstado", nil)
		jugador:SetAttribute("RescateHasta", nil)
	end
end

local function quitarAyuda(character: Model)
	for _, nombre in { NOMBRE_PROMPT, NOMBRE_AYUDA } do
		local raiz = character:FindFirstChild("HumanoidRootPart")
		local objeto = if raiz then raiz:FindFirstChild(nombre) else nil
		if objeto then
			objeto:Destroy()
		end
	end
end

-- ¿Sigue en pie (en la ciudad, viva y no derribada)?
local function enPie(jugador: Player): boolean
	if jugador:GetAttribute("EnCiudad") ~= true or registros[jugador] then
		return false
	end
	local humanoid = humanoideDe(jugador.Character)
	return humanoid ~= nil and humanoid.Health > 0
end

local function companerasEnPie(excepto: Player?): number
	local n = 0
	for _, otro in Players:GetPlayers() do
		if otro ~= excepto and enPie(otro) then
			n += 1
		end
	end
	return n
end

local function terminar(jugador: Player)
	local registro = registros[jugador]
	registros[jugador] = nil
	ponerEstado(jugador, nil)
	if registro and registro.character.Parent then
		registro.character:SetAttribute("Derribada", nil)
		quitarAyuda(registro.character)
	end
end

-- Se levanta con una fracción de su vida y unos segundos de protección.
local function levantar(jugador: Player, fraccion: number)
	local registro = registros[jugador]
	local character = if registro then registro.character else jugador.Character
	terminar(jugador)
	local humanoid = humanoideDe(character)
	if not character or not humanoid then
		return
	end
	humanoid.Health = math.max(1, humanoid.MaxHealth * fraccion)
	local campo = Instance.new("ForceField")
	campo.Name = NOMBRE_PROTECCION
	campo.Visible = false
	campo.Parent = character
	task.delay(CONFIG.Invulnerable, function()
		if campo.Parent then
			campo:Destroy()
		end
	end)
end

local function alLobby(jugador: Player)
	local registro = registros[jugador]
	local character = if registro then registro.character else jugador.Character
	terminar(jugador)
	local humanoid = humanoideDe(character)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	LobbyService.EnviarAlLobby(jugador)
	anunciar(jugador, "DE VUELTA EN EL LOBBY", "¡Recupérate y vuelve a defender Sugar Town!", COLOR_ROSA)
end

local function ofrecer(jugador: Player)
	local registro = registros[jugador]
	if not registro or registro.estado == "Oferta" then
		return
	end
	-- Un "revivir" ya pagado (compra que llegó tarde) se usa solo
	local guardado = jugador:GetAttribute("RevivirGuardado")
	if typeof(guardado) == "number" and guardado > 0 then
		jugador:SetAttribute("RevivirGuardado", guardado - 1)
		levantar(jugador, CONFIG.VidaAlRevivir)
		anunciar(jugador, "💖 ¡DE PIE OTRA VEZ!", "Usaste un revivir guardado", COLOR_VERDE)
		return
	end
	registro.estado = "Oferta"
	registro.hasta = ahora() + CONFIG.TiempoOferta
	quitarAyuda(registro.character) -- ya no se la puede salvar: decide ella
	ponerEstado(jugador, registro)
end

-- Si ya no queda nadie en pie, todas las derribadas reciben la oferta.
local function revisarCaidaTotal()
	if companerasEnPie(nil) > 0 then
		return
	end
	for jugador, registro in registros do
		if registro.estado == "Derribada" then
			ofrecer(jugador)
		end
	end
end

-- Cartel "¡AYUDA!" y botón "Salvar" (el cliente de la propia heroína oculta su botón).
local function ponerAyuda(jugador: Player, character: Model)
	local raiz = character:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return
	end
	local cartel = Instance.new("BillboardGui")
	cartel.Name = NOMBRE_AYUDA
	cartel.Size = UDim2.fromOffset(150, 46)
	cartel.StudsOffset = Vector3.new(0, 4.5, 0)
	cartel.AlwaysOnTop = true
	cartel.MaxDistance = 220
	cartel.LightInfluence = 0
	local texto = Instance.new("TextLabel")
	texto.BackgroundTransparency = 1
	texto.Size = UDim2.fromScale(1, 1)
	texto.Font = Enum.Font.FredokaOne
	texto.Text = "¡AYUDA!"
	texto.TextScaled = true
	texto.TextColor3 = COLOR_ROSA
	texto.TextStrokeTransparency = 0
	texto.Parent = cartel
	cartel.Parent = raiz

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = NOMBRE_PROMPT
	prompt.ActionText = "Salvar"
	prompt.ObjectText = jugador.DisplayName
	prompt.HoldDuration = CONFIG.DuracionSalvar
	prompt.MaxActivationDistance = CONFIG.DistanciaSalvar
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.Parent = raiz
	prompt.Triggered:Connect(function(salvadora: Player)
		if salvadora == jugador or not enPie(salvadora) then
			return
		end
		local registro = registros[jugador]
		if not registro or registro.estado ~= "Derribada" or registro.character ~= character then
			return
		end
		levantar(jugador, CONFIG.VidaAlSalvar)
		anunciar(jugador, "💖 ¡TE SALVARON!", `{salvadora.DisplayName} te levantó`, COLOR_VERDE)
		anunciar(salvadora, "💖 ¡HEROÍNA SALVADA!", `Levantaste a {jugador.DisplayName}`, COLOR_VERDE)
	end)
end

local function derribar(jugador: Player, character: Model, humanoid: Humanoid)
	humanoid.Health = 1
	character:SetAttribute("Derribada", true)
	character:SetAttribute("Volando", false)
	local registro: Registro = {
		estado = "Derribada",
		character = character,
		hasta = ahora() + CONFIG.EsperaRescate,
		comprando = false,
	}
	registros[jugador] = registro
	if companerasEnPie(jugador) == 0 then
		-- SOLO (o todas caídas): decide ya
		ofrecer(jugador)
		revisarCaidaTotal()
	else
		ponerEstado(jugador, registro)
		ponerAyuda(jugador, character)
	end
end

-- ─── API pública ─────────────────────────────────────────────────────────────

function RescateService.EstaDerribada(character: Model): boolean
	return character:GetAttribute("Derribada") == true
end

-- Daño de un monstruo a una heroína. Devuelve el daño aplicado (0 si estaba protegida/derribada).
function RescateService.Danar(character: Model, humanoid: Humanoid, cantidad: number): number
	if cantidad <= 0 or humanoid.Health <= 0 or RescateService.EstaDerribada(character) then
		return 0
	end
	if character:FindFirstChildOfClass("ForceField") then
		return 0 -- escudo de Estrategia o protección al levantarse
	end
	local jugador = Players:GetPlayerFromCharacter(character)
	if jugador and jugador:GetAttribute("EnCiudad") == true and humanoid.Health - cantidad <= 0 then
		local hecho = humanoid.Health - 1
		derribar(jugador, character, humanoid)
		return hecho
	end
	humanoid:TakeDamage(cantidad)
	return cantidad
end

-- Compra de "Revivir" confirmada (recibo o simulación en Studio). Siempre se entrega.
function RescateService.EntregarRevivir(jugador: Player): boolean
	if registros[jugador] then
		levantar(jugador, CONFIG.VidaAlRevivir)
		anunciar(jugador, "💖 ¡DE VUELTA A LA BATALLA!", "¡Gracias por tu compra!", COLOR_VERDE)
	else
		local guardado = jugador:GetAttribute("RevivirGuardado")
		jugador:SetAttribute("RevivirGuardado", (if typeof(guardado) == "number" then guardado else 0) + 1)
		anunciar(jugador, "💖 REVIVIR GUARDADO", "Se usará solo la próxima vez que caigas", COLOR_VERDE)
	end
	return true
end

local function alDecidir(jugador: Player, opcion: unknown)
	local registro = registros[jugador]
	if not registro then
		return
	end
	-- Mientras espera a una compañera ("Derribada") ya puede pagar; "Lobby" solo en la oferta
	if registro.estado ~= "Oferta" and opcion ~= "Pagar" then
		return
	end
	if registro.comprando then
		return -- ya tiene abierta la ventana de compra
	end
	if opcion == "Lobby" then
		alLobby(jugador)
	elseif opcion == "Pagar" then
		local articulo = TiendaRobux.PorClave("Revivir")
		if not articulo then
			return
		end
		if articulo.Id == 0 then
			if RunService:IsStudio() then
				print(`[RescateService] Revivir SIMULADO en Studio para {jugador.Name}`)
				RescateService.EntregarRevivir(jugador)
			end
			return -- publicado con Id 0: no se puede comprar (el cliente lo muestra como "Próximamente")
		end
		-- Mientras está abierta la ventana de compra de Roblox, la espera/oferta no caduca
		-- (si está "Derribada", una compañera aún puede salvarla; la compra quedaría guardada)
		registro.comprando = true
		registro.hasta = math.max(registro.hasta, ahora() + CONFIG.TiempoCompra)
		ponerEstado(jugador, registro)
		MarketplaceService:PromptProductPurchase(jugador, articulo.Id)
	end
end

function RescateService.Init()
	eventoAnuncio = Remotes.Evento("Anuncio")
	Remotes.Evento("DecisionRescate").OnServerEvent:Connect(alDecidir)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, comprado: boolean)
		local jugador = Players:GetPlayerByUserId(userId)
		local registro = if jugador then registros[jugador] else nil
		if jugador and registro and not comprado and registro.comprando then
			-- Canceló: en la oferta vuelve a tener el tiempo normal; derribada sigue esperando
			registro.comprando = false
			if registro.estado == "Oferta" then
				registro.hasta = ahora() + CONFIG.TiempoOferta
			end
			ponerEstado(jugador, registro)
		end
	end)
end

function RescateService.Start()
	Players.PlayerRemoving:Connect(function(jugador)
		registros[jugador] = nil
		task.defer(revisarCaidaTotal) -- si se va la última en pie, las demás deciden
	end)
	-- Reloj: caducan esperas y ofertas; limpia registros de personajes que ya no existen
	task.spawn(function()
		while true do
			task.wait(0.5)
			local t = ahora()
			for jugador, registro in registros do
				local humanoid = humanoideDe(registro.character)
				if not registro.character.Parent or not humanoid or humanoid.Health <= 0 then
					terminar(jugador) -- reapareció o murió de verdad
				elseif jugador:GetAttribute("EnCiudad") ~= true then
					-- Volvió al lobby por su cuenta (botón Lobby): llega con la vida llena
					terminar(jugador)
					humanoid.Health = humanoid.MaxHealth
				elseif t >= registro.hasta then
					if registro.estado == "Derribada" then
						ofrecer(jugador)
					else
						alLobby(jugador)
					end
				end
			end
		end
	end)
end

return RescateService
