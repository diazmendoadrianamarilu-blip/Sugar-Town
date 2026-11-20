--!strict
-- Sonidos del juego. Solo datos.
-- Sonidos INTEGRADOS en el cliente de Roblox (rbxasset://sounds/...), que siempre cargan, y audios
-- PÚBLICOS de la Creator Store (rbxassetid://<número>), que funcionan en cualquier experiencia.
-- EfectosController los combina con distintos tonos (PlaybackSpeed) para crear variaciones y fanfarrias.

local Types = require(script.Parent.Parent.Types)

type SonidoConfig = Types.SonidoConfig

local Sonidos: { [string]: SonidoConfig } = {
	Viento = { Id = "rbxasset://sounds/action_falling.mp3", Volumen = 0.35, Tono = 1 }, -- bucle de vuelo
	Laser = { Id = "rbxasset://sounds/electronicpingshort.wav", Volumen = 0.5, Tono = 1.6 },
	Rafaga = { Id = "rbxasset://sounds/electronicpingshort.wav", Volumen = 0.35, Tono = 2.2 },
	Explosion = { Id = "rbxasset://sounds/collide.wav", Volumen = 0.8, Tono = 0.7 },
	Impulso = { Id = "rbxassetid://123796710194563", Volumen = 0.8, Tono = 0.9 }, -- "Whoosh Swinging Sound"
	Escudo = { Id = "rbxasset://sounds/electronicpingshort.wav", Volumen = 0.5, Tono = 0.8 },
	Pulso = { Id = "rbxassetid://123796710194563", Volumen = 0.8, Tono = 0.55 },
	Derrota = { Id = "rbxasset://sounds/collide.wav", Volumen = 0.5, Tono = 1.4 }, -- monstruo derrotado
	Nota = { Id = "rbxasset://sounds/electronicpingshort.wav", Volumen = 0.45, Tono = 1 }, -- base de las fanfarrias
	Boton = { Id = "rbxasset://sounds/button.wav", Volumen = 0.5, Tono = 1 },
	-- Combate cuerpo a cuerpo (audios públicos de la Creator Store)
	GolpeAire = { Id = "rbxassetid://123796710194563", Volumen = 0.45, Tono = 1.25 }, -- "Whoosh Swinging Sound": el golpe corta el aire
	GolpePuno = { Id = "rbxassetid://132504023010884", Volumen = 0.7, Tono = 1 }, -- "Punch Impact 1"
	GolpePuno2 = { Id = "rbxassetid://126895218143022", Volumen = 0.7, Tono = 1.05 }, -- "Punch Impact 2"
	GolpePatada = { Id = "rbxassetid://82235785832022", Volumen = 0.85, Tono = 0.95 }, -- "Heavy punch impact #3"
	Combo = { Id = "rbxasset://sounds/electronicpingshort.wav", Volumen = 0.35, Tono = 2 }, -- pitido al subir el combo
	-- Monstruos (audios públicos de la Creator Store)
	Rugido = { Id = "rbxassetid://121887934885380", Volumen = 0.9, Tono = 1 }, -- "Monster growl 2": aviso de ataque especial
	Escupitajo = { Id = "rbxassetid://1370363170", Volumen = 0.8, Tono = 0.9 }, -- "Spit Sound": Gomiloso lanza la gelatina
	Gelatina = { Id = "rbxassetid://75221355097604", Volumen = 0.9, Tono = 1 }, -- "slime splat 2": la gelatina cae
	Embestida = { Id = "rbxassetid://123796710194563", Volumen = 1, Tono = 0.6 }, -- whoosh grave: Zumbón sale disparado
	GolpeSuelo = { Id = "rbxassetid://74149238738530", Volumen = 1, Tono = 1 }, -- "Ground Slam Impact Shockwave"
	Poof = { Id = "rbxassetid://101988252664265", Volumen = 1, Tono = 1 }, -- "Poof Cartoon": monstruo derrotado
	-- Rayo láser (Q, nivel 3)
	LaserCarga = { Id = "rbxassetid://123132185939954", Volumen = 0.8, Tono = 1.15 }, -- "Light Laser Charge Up"
	LaserDisparo = { Id = "rbxassetid://9116225257", Volumen = 0.75, Tono = 1.1 }, -- "Laser Blast 101 (SFX)" (ProSoundEffects)
	-- Armas (audios públicos de la Creator Store)
	Dulce = { Id = "rbxassetid://106984966606682", Volumen = 0.9, Tono = 1 }, -- "Cartoon Pop - Daily Sounds"
	Martillo = { Id = "rbxassetid://132937320140224", Volumen = 1, Tono = 0.9 }, -- "cartoon-bonk"
	Estrellas = { Id = "rbxassetid://117011707307950", Volumen = 0.8, Tono = 1.1 }, -- "Glitter Sparkle Magic Sound"
	-- Progreso y tráfico
	SubirNivel = { Id = "rbxassetid://105193542038988", Volumen = 0.8, Tono = 1 }, -- "Cute level up"
	Bocina = { Id = "rbxassetid://136659551490452", Volumen = 0.9, Tono = 1 }, -- "klaxon_small"
	Mareo = { Id = "rbxassetid://8730871251", Volumen = 0.8, Tono = 1 }, -- "Cartoon dizzy birds"
	Moneda = { Id = "rbxasset://sounds/electronicpingshort.wav", Volumen = 0.3, Tono = 2.6 }, -- moneda recogida
}

for _, sonido in Sonidos do
	table.freeze(sonido)
end

return table.freeze(Sonidos)
