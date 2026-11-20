--!strict
-- Fuente única de RemoteEvents.
-- Servidor: Remotes.Init() los crea en ReplicatedStorage.Remotes.
-- Cliente: Remotes.Evento(nombre) los espera con WaitForChild.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type NombreEvento =
	"EstadoVuelo" -- cliente -> servidor: (volando: boolean)
	| "ElegirHeroina" -- cliente -> servidor: (arquetipo: ArquetipoId)
	| "UsarPoder" -- cliente -> servidor: (ranura: Ranura, objetivo: Vector3)
	| "EfectoPoder" -- servidor -> clientes: (lanzador: Player, poderId: string, objetivo: Vector3)
	| "Anuncio" -- servidor -> cliente(s): (titulo: string, subtitulo: string, color: Color3)
	| "NumeroDano" -- servidor -> clientes: (posicion: Vector3, cantidad: number, color: Color3, grande: boolean)
	| "ComprarMejora" -- cliente -> servidor: (tipo: TipoMejora)
	| "EstadoCarrera" -- cliente -> servidor: (corriendo: boolean)
	| "UsarEstallido" -- cliente -> servidor: (sin argumentos)
	| "ComprarTienda" -- cliente -> servidor: (articuloId: string)
	| "VolverLobby" -- cliente -> servidor: (sin argumentos)
	| "Golpear" -- cliente -> servidor: (direccion: Vector3) intención de golpe cuerpo a cuerpo
	| "EfectoGolpe" -- servidor -> clientes: (atacante: Player, paso: number, impacto: Vector3?, enemigo: Model?, combo: number)
	| "Empujon" -- servidor -> cliente: (velocidad: Vector3) un ataque de monstruo lanza a la heroína (ella es dueña de su física)
	| "Curacion" -- servidor -> clientes: (character: Model, cantidad: number) regeneración: "+N" verde y brillo
	| "DecisionRescate" -- cliente -> servidor: (opcion: "Pagar" | "Lobby") al ser derrotada
	| "UsarArma" -- cliente -> servidor: (clave: string, objetivo: Vector3) disparar un arma propia
	| "DesbloquearArma" -- cliente -> servidor: (clave: string) comprar un arma con monedas
	| "MonstruoDerrotado" -- servidor -> clientes: (posicion: Vector3, color: Color3, tamano: number, asesino: Player?, monedas: number)

local NOMBRE_CARPETA = "Remotes"
local EVENTOS: { NombreEvento } =
	{
		"EstadoVuelo",
		"ElegirHeroina",
		"UsarPoder",
		"EfectoPoder",
		"Anuncio",
		"NumeroDano",
		"ComprarMejora",
		"EstadoCarrera",
		"UsarEstallido",
		"ComprarTienda",
		"VolverLobby",
		"Golpear",
		"EfectoGolpe",
		"Empujon",
		"MonstruoDerrotado",
		"Curacion",
		"DecisionRescate",
		"UsarArma",
		"DesbloquearArma",
	}

local Remotes = {}

function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init() solo se puede llamar desde el servidor")

	local carpeta = ReplicatedStorage:FindFirstChild(NOMBRE_CARPETA)
	if carpeta == nil then
		local nueva = Instance.new("Folder")
		nueva.Name = NOMBRE_CARPETA
		carpeta = nueva
	end
	assert(carpeta)

	for _, nombre in EVENTOS do
		if carpeta:FindFirstChild(nombre) == nil then
			local evento = Instance.new("RemoteEvent")
			evento.Name = nombre
			evento.Parent = carpeta
		end
	end

	-- Se publica al final para que el cliente nunca vea la carpeta a medias.
	carpeta.Parent = ReplicatedStorage
end

function Remotes.Evento(nombre: NombreEvento): RemoteEvent
	local remoto: Instance?
	if RunService:IsServer() then
		local carpeta = ReplicatedStorage:FindFirstChild(NOMBRE_CARPETA)
		remoto = if carpeta then carpeta:FindFirstChild(nombre) else nil
	else
		remoto = ReplicatedStorage:WaitForChild(NOMBRE_CARPETA):WaitForChild(nombre)
	end

	if remoto and remoto:IsA("RemoteEvent") then
		return remoto
	end
	error(`RemoteEvent '{nombre}' no encontrado (¿se llamó a Remotes.Init() en el servidor?)`)
end

return Remotes
