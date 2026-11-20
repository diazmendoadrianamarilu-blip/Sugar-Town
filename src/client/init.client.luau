--!strict
-- Punto de entrada del cliente. Orden: Init de controladores -> Start de controladores.

local EfectosController = require(script.EfectosController)
local UIController = require(script.UIController)
local PoseVueloController = require(script.PoseVueloController)
local VueloController = require(script.VueloController)
local PoderesController = require(script.PoderesController)
local CombateController = require(script.CombateController)
local CamaraController = require(script.CamaraController)
local RescateController = require(script.RescateController)
local ArmasController = require(script.ArmasController)
local TraficoController = require(script.TraficoController)

EfectosController.Init()
UIController.Init()
PoseVueloController.Init()
VueloController.Init()
PoderesController.Init()
CombateController.Init()
CamaraController.Init()
RescateController.Init()
ArmasController.Init()
TraficoController.Init()
UIController.AlVolar(VueloController.Alternar) -- botón VOLAR del HUD

VueloController.Start()
UIController.Start()
PoderesController.Start()
CombateController.Start()
CamaraController.Start()
RescateController.Start()
ArmasController.Start()
TraficoController.Start()
