--!strict
-- MejorasService: compra de mejoras (Daño / Vuelo) para la heroína ACTUAL, pagando con monedas.
-- Valida: tipo válido, nivel máximo, monedas suficientes y frecuencia de compra.
-- El efecto lo aplican CombateService (daño) y VueloController (velocidad) leyendo el atributo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Armas = require(Shared.Config.Armas)
local Heroinas = require(Shared.Config.Heroinas)
local Mejoras = require(Shared.Config.Mejoras)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local HeroinaService = require(script.Parent.HeroinaService)

local INTERVALO_MINIMO = 0.2 -- segundos entre compras (anti-spam)

local ultimaCompra: { [Player]: number } = {}

local MejorasService = {}

local function alComprar(jugador: Player, tipoBruto: unknown)
	if not Mejoras.EsTipo(tipoBruto) then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimaCompra[jugador] or 0) < INTERVALO_MINIMO then
		return
	end
	ultimaCompra[jugador] = ahora

	local tipo = tipoBruto :: Types.TipoMejora
	local arquetipo = Heroinas.Obtener(jugador:GetAttribute("Arquetipo")).Id
	local nivel = Mejoras.Nivel(jugador, arquetipo, tipo)
	if nivel >= Mejoras.Lista[tipo].NivelMaximo then
		return
	end
	if HeroinaService.GastarMonedas(jugador, Mejoras.Costo(tipo, nivel)) then
		jugador:SetAttribute(Mejoras.Atributo(arquetipo, tipo), nivel + 1)
	end
end

-- Arma con monedas: nivel mínimo y monedas suficientes (valores de Config/Armas, nunca del cliente)
local function alDesbloquearArma(jugador: Player, claveBruta: unknown)
	local arma = Armas.PorClave(claveBruta)
	if not arma then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimaCompra[jugador] or 0) < INTERVALO_MINIMO then
		return
	end
	ultimaCompra[jugador] = ahora
	if Armas.Tiene(jugador, arma.Clave) then
		return
	end
	local nivel = jugador:GetAttribute("Nivel")
	if typeof(nivel) ~= "number" or nivel < arma.NivelMonedas then
		return
	end
	if HeroinaService.GastarMonedas(jugador, arma.CostoMonedas) then
		jugador:SetAttribute(Armas.PrefijoAtributo .. arma.Clave, true)
		Remotes.Evento("Anuncio"):FireClient(jugador, `{arma.Icono} ¡{string.upper(arma.Nombre)}!`, "Ya es tuya: pulsa ARMA (tecla T)", Color3.fromRGB(255, 205, 50))
	end
end

function MejorasService.Init()
	Remotes.Evento("ComprarMejora").OnServerEvent:Connect(alComprar)
	Remotes.Evento("DesbloquearArma").OnServerEvent:Connect(alDesbloquearArma)
	Players.PlayerRemoving:Connect(function(jugador)
		ultimaCompra[jugador] = nil
	end)
end

return MejorasService
