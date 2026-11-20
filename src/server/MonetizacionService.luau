--!strict
-- MonetizacionService: pases de juego y productos de Robux (Config/TiendaRobux.luau).
--   • Pases: UserOwnsGamePassAsync al entrar + PromptGamePassPurchaseFinished → atributo "Pase_<Clave>".
--   • Productos: MarketplaceService.ProcessReceipt, idempotente (cada PurchaseId se registra en un
--     DataStore para no entregarlo dos veces) y guardando el progreso antes de confirmar.
--   • Modo de prueba en Studio: si el Id del artículo es 0, la compra se simula gratis.
--     (Con Ids reales, Studio ya muestra la ventana de compra de prueba de Roblox, que no cobra Robux.)
-- Efectos: VueloSupersonico → VueloController (×2); HeroinaVIP → HeroinaService (+50% monedas, aura);
--          Monedas → HeroinaService; BombaEstelar → MonstruoService.DerrotarTodos().

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local TiendaRobux = require(Shared.Config.TiendaRobux)
local DatosService = require(script.Parent.DatosService)
local HeroinaService = require(script.Parent.HeroinaService)
local MonstruoService = require(script.Parent.MonstruoService)
local RescateService = require(script.Parent.RescateService)

type ArticuloConfig = TiendaRobux.ArticuloConfig

local NOMBRE_RECIBOS = "SugarTown_Recibos_v1"
local INTERVALO_MINIMO = 1 -- segundos entre peticiones de compra por jugador
local COLOR_DORADO = Color3.fromRGB(255, 215, 70)

local recibos: DataStore? = nil
local eventoAnuncio: RemoteEvent
local ultimaPeticion: { [Player]: number } = {}

local MonetizacionService = {}

local function avisar(jugador: Player, titulo: string, subtitulo: string)
	eventoAnuncio:FireClient(jugador, titulo, subtitulo, COLOR_DORADO)
end

local function otorgarPase(jugador: Player, articulo: ArticuloConfig)
	jugador:SetAttribute(TiendaRobux.AtributoPase(articulo.Clave), true)
	avisar(jugador, `{articulo.Icono} ¡{articulo.Nombre}!`, articulo.Descripcion)
end

local function entregarProducto(jugador: Player, articulo: ArticuloConfig): boolean
	local monedas = articulo.Monedas
	if monedas then
		HeroinaService.SumarMonedas(jugador, monedas)
		avisar(jugador, `+{monedas} monedas`, "¡Gracias por tu compra!")
		return true
	elseif articulo.Clave == "Revivir" then
		return RescateService.EntregarRevivir(jugador)
	elseif articulo.Clave == "BombaEstelar" then
		MonstruoService.DerrotarTodos()
		eventoAnuncio:FireAllClients("💣 ¡BOMBA ESTELAR!", `{jugador.DisplayName} limpió la oleada`, COLOR_DORADO)
		return true
	end
	return false
end

local function comprobarPases(jugador: Player)
	for _, articulo in TiendaRobux.Lista do
		if articulo.Tipo == "Pase" and articulo.Id ~= 0 then
			local ok, tiene = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(jugador.UserId, articulo.Id)
			end)
			if ok and tiene and jugador.Parent then
				jugador:SetAttribute(TiendaRobux.AtributoPase(articulo.Clave), true)
			end
		end
	end
end

-- ProcessReceipt: solo devuelve PurchaseGranted cuando el producto se entregó y quedó registrado.
local function procesarRecibo(info: { [string]: any }): Enum.ProductPurchaseDecision
	local jugador = Players:GetPlayerByUserId(info.PlayerId)
	if not jugador then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- se reintentará cuando vuelva a entrar
	end
	local articulo = TiendaRobux.PorProductId(info.ProductId)
	if not articulo then
		warn(`[MonetizacionService] ProductId desconocido: {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local clave = `recibo_{info.PurchaseId}`
	local almacen = recibos
	if almacen then
		local ok, yaEntregado = pcall(function()
			return almacen:GetAsync(clave)
		end)
		if not ok and RunService:IsStudio() then
			-- Studio sin acceso a DataStore: compra de PRUEBA (no cobra Robux) → entregar sin registrar
			almacen = nil
		elseif not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if yaEntregado then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	if not entregarProducto(jugador, articulo) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DatosService.Guardar(jugador)

	if almacen then
		local ok = pcall(function()
			almacen:SetAsync(clave, true)
		end)
		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function alPedirCompra(jugador: Player, claveBruta: unknown)
	local articulo = TiendaRobux.PorClave(claveBruta)
	if not articulo then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimaPeticion[jugador] or 0) < INTERVALO_MINIMO then
		return
	end
	ultimaPeticion[jugador] = ahora

	if articulo.Tipo == "Pase" and TiendaRobux.TienePase(jugador, articulo.Clave) then
		return
	end
	if articulo.Clave == "BombaEstelar" and MonstruoService.CantidadVivos() == 0 then
		avisar(jugador, "💣 Sin monstruos", "Guárdala para cuando ataque una oleada")
		return
	end

	if articulo.Id == 0 then
		if RunService:IsStudio() then
			-- Modo de prueba gratuito en Studio
			if articulo.Tipo == "Pase" then
				otorgarPase(jugador, articulo)
			else
				entregarProducto(jugador, articulo)
			end
			print(`[MonetizacionService] Compra SIMULADA en Studio: {articulo.Nombre} para {jugador.Name}`)
		end
		return -- en el juego publicado un Id 0 no se puede comprar
	end

	if articulo.Tipo == "Pase" then
		MarketplaceService:PromptGamePassPurchase(jugador, articulo.Id)
	else
		MarketplaceService:PromptProductPurchase(jugador, articulo.Id)
	end
end

function MonetizacionService.Init()
	eventoAnuncio = Remotes.Evento("Anuncio")

	if game.PlaceId ~= 0 then
		local ok, resultado = pcall(function()
			return DataStoreService:GetDataStore(NOMBRE_RECIBOS)
		end)
		if ok then
			recibos = resultado
		end
	end

	MarketplaceService.ProcessReceipt = procesarRecibo
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(jugador: Player, pasaId: number, comprado: boolean)
		if not comprado then
			return
		end
		for _, articulo in TiendaRobux.Lista do
			if articulo.Tipo == "Pase" and articulo.Id == pasaId then
				otorgarPase(jugador, articulo)
			end
		end
	end)
	Remotes.Evento("ComprarTienda").OnServerEvent:Connect(alPedirCompra)
end

function MonetizacionService.Start()
	Players.PlayerAdded:Connect(comprobarPases)
	Players.PlayerRemoving:Connect(function(jugador)
		ultimaPeticion[jugador] = nil
	end)
	for _, jugador in Players:GetPlayers() do
		task.spawn(comprobarPases, jugador)
	end
end

return MonetizacionService
