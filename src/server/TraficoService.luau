--!strict
-- TraficoService: choques de autos con heroínas (el servidor decide; los autos los dibuja cada
-- cliente con la misma fórmula de Shared/Trafico).
-- Choque (a pie o volando bajo) → atributo de personaje "Aturdida" durante Trafico.Aturdimiento s:
-- no puede atacar (CombateService/clientes lo comprueban), estrellitas y sonido cómico en los
-- clientes, y un empujón. Sin daño. Nunca afecta a monstruos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Trafico = require(Shared.Trafico)

local INTERVALO = 0.1 -- s entre comprobaciones (a 48 studs/s el auto avanza menos que su largo)

local ultimoChoque: { [Player]: number } = {}
local eventoEmpujon: RemoteEvent

local TraficoService = {}

local function aturdir(jugador: Player, character: Model, auto: CFrame, raiz: BasePart)
	local ahora = Workspace:GetServerTimeNow()
	ultimoChoque[jugador] = ahora
	local hasta = ahora + Trafico.Aturdimiento
	character:SetAttribute("Aturdida", true)
	character:SetAttribute("AturdidaHasta", hasta)
	-- Empujón hacia el lado del auto donde está la heroína, y un poco hacia arriba
	local lateral = auto.RightVector * (if auto:PointToObjectSpace(raiz.Position).X >= 0 then 1 else -1)
	eventoEmpujon:FireClient(jugador, (lateral + Vector3.new(0, 0.7, 0)).Unit * Trafico.EmpujeChoque)
	task.delay(Trafico.Aturdimiento, function()
		if character:GetAttribute("AturdidaHasta") == hasta then
			character:SetAttribute("Aturdida", nil)
			character:SetAttribute("AturdidaHasta", nil)
		end
	end)
end

local function revisar()
	local ahora = Workspace:GetServerTimeNow()
	local autos: { CFrame } = {}
	for i = 1, Trafico.CantidadAutos do
		autos[i] = Trafico.CFrameAuto(i, ahora)
	end
	for _, jugador in Players:GetPlayers() do
		if jugador:GetAttribute("EnCiudad") ~= true then
			continue
		end
		if ahora - (ultimoChoque[jugador] or -math.huge) < Trafico.EsperaEntreChoques then
			continue
		end
		local character = jugador.Character
		local raiz = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not character or not raiz or not raiz:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end
		if character:GetAttribute("Derribada") == true then
			continue
		end
		for _, auto in autos do
			local rel = auto:PointToObjectSpace(raiz.Position)
			if math.abs(rel.X) < Trafico.MedioAncho and math.abs(rel.Z) < Trafico.MedioLargo and rel.Y > -4 and rel.Y < 6 then
				aturdir(jugador, character, auto, raiz)
				break
			end
		end
	end
end

function TraficoService.Init()
	eventoEmpujon = Remotes.Evento("Empujon")
end

function TraficoService.Start()
	Players.PlayerRemoving:Connect(function(jugador)
		ultimoChoque[jugador] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(INTERVALO)
			revisar()
		end
	end)
end

return TraficoService
