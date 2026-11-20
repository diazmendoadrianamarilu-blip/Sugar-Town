--!strict
-- RescateController: comportamiento de la heroína local mientras está DERRIBADA (lo decide el
-- servidor con el atributo "Derribada" del personaje). Solo física/visual del cliente:
--   • deja de volar, se sienta en el suelo y no puede saltar (ella es dueña de su física);
--   • oculta SU PROPIO botón "Salvar" (solo lo ven las compañeras).
-- La ventana de revivir / volver al lobby la dibuja UIController.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local VueloController = require(script.Parent.VueloController)

local NOMBRE_PROMPT = "Rescate"

local jugador = Players.LocalPlayer
local conexionesPersonaje: { RBXScriptConnection } = {}

local RescateController = {}

local function seguirPersonaje(character: Model)
	for _, conexion in conexionesPersonaje do
		conexion:Disconnect()
	end
	table.clear(conexionesPersonaje)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local function aplicar()
		local derribada = character:GetAttribute("Derribada") == true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not derribada)
		if derribada then
			if VueloController.EstaVolando() then
				VueloController.Alternar()
			end
			humanoid.Sit = true
		else
			humanoid.Sit = false
		end
	end
	table.insert(conexionesPersonaje, character:GetAttributeChangedSignal("Derribada"):Connect(aplicar))
	-- Mientras esté derribada, sigue sentada aunque algo la levante (empujones, controles)
	table.insert(conexionesPersonaje, RunService.Heartbeat:Connect(function()
		if character:GetAttribute("Derribada") == true and not humanoid.Sit then
			humanoid.Sit = true
		end
	end))
	-- Su propio botón "Salvar" no se muestra en su pantalla
	local function ocultarPropio(objeto: Instance)
		if objeto:IsA("ProximityPrompt") and objeto.Name == NOMBRE_PROMPT then
			objeto.Enabled = false
		end
	end
	for _, d in character:GetDescendants() do
		ocultarPropio(d)
	end
	table.insert(conexionesPersonaje, character.DescendantAdded:Connect(ocultarPropio))
	aplicar()
end

function RescateController.Init() end

function RescateController.Start()
	jugador.CharacterAdded:Connect(seguirPersonaje)
	if jugador.Character then
		task.spawn(seguirPersonaje, jugador.Character)
	end
end

return RescateController
