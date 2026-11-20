--!strict
-- Punto de entrada del servidor. Orden: Remotes -> Init de servicios -> Start de servicios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DatosService = require(script.DatosService)
local HeroinaService = require(script.HeroinaService)
local CombateService = require(script.CombateService)
local MejorasService = require(script.MejorasService)
local MonetizacionService = require(script.MonetizacionService)
local EdificioService = require(script.EdificioService)
local LobbyService = require(script.LobbyService)
local RescateService = require(script.RescateService)
local TraficoService = require(script.TraficoService)
local MonstruoService = require(script.MonstruoService)
local RondaService = require(script.RondaService)

Remotes.Init()

EdificioService.Init() -- ciudad + iluminación limpia
LobbyService.Init() -- lobby: única aparición activa
RescateService.Init() -- derrota y rescate de heroínas
TraficoService.Init() -- choques con los autos
DatosService.Init()
HeroinaService.Init()
CombateService.Init()
MejorasService.Init()
MonstruoService.Init()
RondaService.Init()
MonetizacionService.Init()

HeroinaService.Start() -- valores por defecto
DatosService.Start() -- después carga lo guardado encima
LobbyService.Start()
RescateService.Start()
TraficoService.Start()
MonstruoService.Start()
RondaService.Start()
MonetizacionService.Start()
