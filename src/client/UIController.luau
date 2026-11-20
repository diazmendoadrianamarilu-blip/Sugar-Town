--!strict
-- UIController: toda la interfaz se genera por código (nada creado a mano en Studio).
--   • Selector de heroína (menú inicial y botón "Cambiar").
--   • HUD superior derecho: clase actual, barra de vida, monedas, botón de cambio.
--   • Barra de poderes inferior: 2 ranuras con enfriamiento visual (también son botones: sirven en móvil).

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Heroinas = require(Shared.Config.Heroinas)
local Juego = require(Shared.Config.Juego)
local Mejoras = require(Shared.Config.Mejoras)
local Poderes = require(Shared.Config.Poderes)
local TiendaRobux = require(Shared.Config.TiendaRobux)
local Armas = require(Shared.Config.Armas)
local Poderes = require(Shared.Config.Poderes)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local EfectosController = require(script.Parent.EfectosController)

type Ranura = Types.Ranura
type HeroinaConfig = Types.HeroinaConfig

-- ─── Estilo ──────────────────────────────────────────────────────────────────

local FUENTE_TITULO = Enum.Font.FredokaOne
local FUENTE_TEXTO = Enum.Font.GothamBold
local COLOR_FONDO = Color3.fromRGB(40, 22, 72)
local COLOR_FONDO_OSCURO = Color3.fromRGB(22, 10, 42)
local COLOR_CONTORNO = Color3.fromRGB(15, 5, 30)
local COLOR_ROSA = Color3.fromRGB(255, 110, 199)
local COLOR_AMARILLO = Color3.fromRGB(255, 225, 80)
local BLANCO = Color3.new(1, 1, 1)

local TECLAS: { [Ranura]: string } = { Primario = "E", Secundario = "Q" }
local ORDEN_RANURAS: { Ranura } = { "Primario", "Secundario" }

-- ─── Estado ──────────────────────────────────────────────────────────────────

type Ranura_UI = {
	boton: TextButton,
	icono: TextLabel,
	nombre: TextLabel,
	trazo: UIStroke,
	cortina: Frame,
	cuenta: TextLabel,
	candado: Frame, -- tapa el botón mientras el poder no está desbloqueado por nivel
	textoCandado: TextLabel,
	iconoCandado: TextLabel,
	poderId: string,
}

local jugador = Players.LocalPlayer
local eventoElegir: RemoteEvent
local gui: ScreenGui
local menu: TextButton
local botonesElegir: { [string]: TextButton } = {}
local menuAbierto = false
local alPulsarPoder: ((Ranura) -> ())? = nil

local hudTrazo: UIStroke
local hudPanel: Frame -- tarjeta de la heroína (arriba izquierda)
local botonClases: TextButton
local hudIcono: TextLabel
local hudNombre: TextLabel
local barraVida: Frame
local textoVida: TextLabel
local textoMonedas: TextLabel
local textoNivel: TextLabel
local textoProximo: TextLabel -- "Nv. 3 → 🔴 Láser Carmesí" (siguiente poder que se desbloquea)
local avisoBloqueo: TextLabel
local pildoraRecompensa: Frame -- lobby: tiempo para el próximo impulso, impulsos y progreso
local textoRecompensa: TextLabel
local avisoActual = 0
local actualizarDesbloqueos: () -> ()
local barraExperiencia: Frame
local tituloOleada: TextLabel
local infoOleada: TextLabel
local anuncioTitulo: TextLabel
local anuncioSubtitulo: TextLabel
local anuncioEscala: UIScale
local anuncioActual = 0

type FilaMejora = { nivel: TextLabel, boton: TextButton, pips: { Frame }, textoBoton: TextLabel, monedaBoton: Frame }
local eventoComprar: RemoteEvent
local panelMejoras: TextButton
local ventanaMejoras: Ventana
local monedasMejoras: TextLabel
local subtituloMejoras: TextLabel
local filasMejora: { [Types.TipoMejora]: FilaMejora } = {}
local mejorasAbierto = false
local COLOR_NARANJA = Color3.fromRGB(255, 150, 40)
local COLOR_ORO = Color3.fromRGB(255, 205, 50)
local NEGRO = Color3.new(0, 0, 0)

-- Retrato (ViewportFrame con una copia del personaje)
local visorRetrato: ViewportFrame
local camaraRetrato: Camera
local anilloRetrato: UIStroke
local retratoPendiente = 0

-- Frascos de Esencia Estelar
local NUM_FRASCOS = 5
local frascos: { Frame } = {}
local textoEsencia: TextLabel
local alPulsarEstallido: (() -> ())? = nil

-- Radar
local RADIO_RADAR_PX = 56
local ALCANCE_RADAR = 520 -- studs que cubre el radar
local radar: Frame
local flechaRadar: TextLabel
local puntosRadar: { Frame } = {}

-- Tienda Robux
local eventoTienda: RemoteEvent
local panelTienda: TextButton
local tiendaAbierta = false
local botonesTienda: { [string]: TextButton } = {}
local botonesMonedasArma: { [string]: TextButton } = {} -- alternativa con monedas en las filas de armas
local eventoDesbloquearArma: RemoteEvent
local preciosReales: { [string]: number } = {}
local actualizarRescate: () -> () -- se define con la ventana de rescate
-- Botón ARMA (solo visible si tiene alguna arma de Config/Armas)
local botonArma: TextButton? = nil
local cambioArma: TextButton? = nil
local cortinaArma: Frame? = nil
local cuentaArma: TextLabel? = nil
local armaPoderId = ""
local alPulsarArma: (() -> ())? = nil
local alPulsarCambioArma: (() -> ())? = nil

-- Lobby / amigos
local eventoLobby: RemoteEvent
local botonLobby: TextButton
local textoAmigos: TextLabel
local COLOR_APAGADO = Color3.fromRGB(110, 100, 130)
local ranuras: { [Ranura]: Ranura_UI } = {}
-- Combo cuerpo a cuerpo
local alPulsarGolpe: (() -> ())? = nil
local contadorCombo: Frame
local escalaCombo: UIScale
local textoCombo: TextLabel
local textoBonoCombo: TextLabel
local comboActual = 0
-- Distribución adaptable (PC / móvil)
local escalasPantalla: { UIScale } = {}
local columnaDerecha: Frame
local botonAmigos: TextButton
local acciones: Frame? = nil
local botonCombo: TextButton
local botonVolar: TextButton
local alPulsarVolar: (() -> ())? = nil
local columnaLateral: Frame
local escalaColumna: UIScale
local rejillaColumna: UIGridLayout
local enfriamientos: { [string]: { fin: number, duracion: number } } = {}
local conexionesVida: { RBXScriptConnection } = {}

local UIController = {}

-- ─── Utilidades ──────────────────────────────────────────────────────────────

-- Crea una instancia con propiedades e hijos; "Parent" se asigna al final.
local function crear(clase: string, propiedades: { [string]: any }, hijos: { Instance }?): any
	local instancia = Instance.new(clase :: any)
	for nombre, valor in propiedades do
		if nombre ~= "Parent" then
			(instancia :: any)[nombre] = valor
		end
	end
	if hijos then
		for _, hijo in hijos do
			hijo.Parent = instancia
		end
	end
	if propiedades.Parent then
		instancia.Parent = propiedades.Parent
	end
	return instancia
end

local function esquinas(radio: number): UICorner
	return crear("UICorner", { CornerRadius = UDim.new(0, radio) })
end

local function contorno(grosor: number, color: Color3?): UIStroke
	return crear("UIStroke", {
		Thickness = grosor,
		Color = color or COLOR_CONTORNO,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Texto estilo caricatura: relleno blanco con contorno grueso oscuro.
local function texto(propiedades: { [string]: any }, grosorContorno: number?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FUENTE_TITULO,
		TextColor3 = BLANCO,
		TextScaled = true,
	}
	for k, v in propiedades do
		base[k] = v
	end
	local etiqueta: TextLabel = crear("TextLabel", base)
	if grosorContorno and grosorContorno > 0 then
		crear("UIStroke", {
			Thickness = grosorContorno,
			Color = COLOR_CONTORNO,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = etiqueta,
		})
	end
	return etiqueta
end

local function botonCaricatura(textoBoton: string, color: Color3, propiedades: { [string]: any }): TextButton
	local base: { [string]: any } = {
		BackgroundColor3 = color,
		Font = FUENTE_TITULO,
		Text = textoBoton,
		TextColor3 = BLANCO,
		TextScaled = true,
		AutoButtonColor = true,
	}
	for k, v in propiedades do
		base[k] = v
	end
	local boton: TextButton = crear("TextButton", base, {
		esquinas(14),
		contorno(4),
		crear("UIPadding", {
			PaddingTop = UDim.new(0.18, 0),
			PaddingBottom = UDim.new(0.18, 0),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})
	crear("UIStroke", {
		Thickness = 2,
		Color = COLOR_CONTORNO,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = boton,
	})
	boton.Activated:Connect(EfectosController.SonidoBoton)
	-- Pequeño "rebote" al pasar el ratón
	local escala: UIScale = crear("UIScale", { Parent = boton })
	boton.MouseEnter:Connect(function()
		TweenService:Create(escala, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
	end)
	boton.MouseLeave:Connect(function()
		TweenService:Create(escala, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	return boton
end

-- Icono de moneda propio (círculo dorado con estrella): el emoji de moneda no existe en la fuente
-- de Roblox y sale como un rectángulo vacío.
local function iconoMoneda(propiedades: { [string]: any }): Frame
	local base: { [string]: any } = {
		Name = "IconoMoneda",
		BackgroundColor3 = Color3.fromRGB(255, 200, 40),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}
	for k, v in propiedades do
		base[k] = v
	end
	local moneda: Frame = crear("Frame", base, {
		crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		crear("UIStroke", { Thickness = 2, Color = Color3.fromRGB(150, 85, 0), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		crear("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(230, 150, 20)) }),
	})
	crear("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.7, 0.7),
		Font = FUENTE_TITULO,
		Text = "★",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(170, 95, 0),
		ZIndex = (base.ZIndex or 1) + 1,
		Parent = moneda,
	})
	return moneda
end

-- Botón de cerrar común a todas las ventanas: una "X" de la fuente del juego (el carácter ✕ no
-- existe en ella y salía un cuadrito vacío).
local function botonCerrar(padre: Instance, accion: () -> ()): TextButton
	-- Sobre la esquina superior derecha del panel (medio fuera): nunca tapa el contenido aunque
	-- crezca en pantallas pequeñas para seguir siendo cómoda para el dedo.
	local boton: TextButton = crear("TextButton", {
		Name = "Cerrar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = COLOR_ROSA,
		AutoButtonColor = true,
		Text = "",
		ZIndex = 30,
		Parent = padre,
	}, { esquinas(14), contorno(4) })
	texto({
		Text = "X",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 31,
		Parent = boton,
	}, 2.5)
	boton.Activated:Connect(function()
		EfectosController.SonidoBoton()
		accion()
	end)
	return boton
end

-- ─── Ventanas (Clases, Mejoras, Tienda, Amigos): mismo estilo, misma X, caben en la pantalla ───
type Ventana = {
	fondo: TextButton,
	tarjeta: Frame,
	escala: UIScale,
	cerrar: TextButton,
	ancho: number,
	alto: number,
	abierta: boolean,
	alCerrar: () -> (),
	animacion: Tween?,
}
local ventanas: { Ventana } = {}
local ventanaAmigos: Ventana

-- Escala para que la ventana (tamaño de diseño ancho × alto) quepa en la zona segura.
local function escalaVentana(v: Ventana): number
	local pantalla = gui.AbsoluteSize
	if pantalla.X < 1 then
		return 1
	end
	-- Margen para la X, que sobresale de la esquina
	return math.min(1.15, pantalla.X * 0.9 / v.ancho, pantalla.Y * 0.86 / v.alto)
end

local function ajustarVentana(v: Ventana)
	-- Si la pantalla cambia durante la animación de apertura, la animación no debe pisar el ajuste
	local animacion = v.animacion
	if animacion then
		animacion:Cancel()
		v.animacion = nil
	end
	local escala = escalaVentana(v)
	v.escala.Scale = escala
	-- La X nunca baja de 44 px reales (tamaño cómodo para el dedo)
	local lado = math.max(48, 44 / escala)
	v.cerrar.Size = UDim2.fromOffset(lado, lado)
end

local function crearVentana(nombre: string, ancho: number, alto: number, colorBorde: Color3, zindex: number, alCerrar: () -> ()): Ventana
	-- Fondo a pantalla completa (Modal libera el ratón): tocar FUERA del panel cierra la ventana
	local fondo: TextButton = crear("TextButton", {
		Name = nombre,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_FONDO_OSCURO,
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		Text = "",
		Modal = true,
		Visible = false,
		ZIndex = zindex,
		Parent = gui,
	})
	-- Active = true: los toques DENTRO del panel no llegan al fondo (no la cierran)
	local tarjeta: Frame = crear("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(ancho, alto),
		BackgroundColor3 = COLOR_FONDO,
		Active = true,
		ZIndex = zindex,
		Parent = fondo,
	}, { esquinas(26), contorno(5, colorBorde) })
	local escala: UIScale = crear("UIScale", { Parent = tarjeta })
	local v: Ventana = {
		fondo = fondo,
		tarjeta = tarjeta,
		escala = escala,
		cerrar = botonCerrar(tarjeta, alCerrar),
		ancho = ancho,
		alto = alto,
		abierta = false,
		alCerrar = alCerrar,
	}
	fondo.Activated:Connect(alCerrar)
	table.insert(ventanas, v)
	return v
end

local function abrirVentana(v: Ventana)
	v.abierta = true
	v.fondo.Visible = true
	ajustarVentana(v)
	local final = v.escala.Scale
	v.escala.Scale = final * 0.85
	local animacion = TweenService:Create(v.escala, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = final })
	v.animacion = animacion
	animacion:Play()
end

local function cerrarVentana(v: Ventana)
	v.abierta = false
	v.fondo.Visible = false
end

local function configActual(): HeroinaConfig
	return Heroinas.Obtener(jugador:GetAttribute("Arquetipo"))
end

-- ─── Selector de heroína ─────────────────────────────────────────────────────

local function barraEstadistica(etiqueta: string, valor: number, color: Color3, orden: number): Frame
	local fila: Frame = crear("Frame", { Size = UDim2.fromScale(1, 0.07), BackgroundTransparency = 1, LayoutOrder = orden })
	texto({
		Text = etiqueta,
		Font = FUENTE_TEXTO,
		Size = UDim2.fromScale(0.36, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = fila,
	})
	local fondo: Frame = crear("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(0.62, 0.6),
		BackgroundColor3 = COLOR_FONDO_OSCURO,
		Parent = fila,
	}, { esquinas(8), contorno(2) })
	crear("Frame", {
		Size = UDim2.fromScale(math.clamp(valor, 0.05, 1), 1),
		BackgroundColor3 = color,
		Parent = fondo,
	}, { esquinas(8) })
	return fila
end

local function crearTarjeta(config: HeroinaConfig, padre: Instance, orden: number)
	local poderes = Poderes.DeArquetipo(config.Id)
	local claro = config.ColorPrincipal:Lerp(BLANCO, 0.25)
	local oscuro = config.ColorPrincipal:Lerp(COLOR_FONDO_OSCURO, 0.75)

	local tarjeta: Frame = crear("Frame", {
		Name = config.Id,
		Size = UDim2.fromScale(0.3, 1),
		BackgroundColor3 = BLANCO,
		LayoutOrder = orden,
		Parent = padre,
	}, {
		esquinas(24),
		contorno(5),
		crear("UIGradient", { Rotation = 90, Color = ColorSequence.new(claro:Lerp(oscuro, 0.35), oscuro) }),
		crear("UIPadding", {
			PaddingTop = UDim.new(0.04, 0),
			PaddingBottom = UDim.new(0.04, 0),
			PaddingLeft = UDim.new(0.07, 0),
			PaddingRight = UDim.new(0.07, 0),
		}),
		crear("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0.015, 0),
		}),
	})
	texto({ Text = config.Icono, Size = UDim2.fromScale(1, 0.17), LayoutOrder = 1, Parent = tarjeta })
	texto({
		Text = string.upper(config.Nombre),
		Size = UDim2.fromScale(1, 0.11),
		TextColor3 = claro,
		LayoutOrder = 2,
		Parent = tarjeta,
	}, 3)
	texto({
		Text = config.Descripcion,
		Font = FUENTE_TEXTO,
		Size = UDim2.fromScale(1, 0.12),
		TextWrapped = true,
		LayoutOrder = 3,
		Parent = tarjeta,
	}, 0)

	barraEstadistica("Vida", config.VidaMaxima / 150, Color3.fromRGB(255, 90, 120), 4).Parent = tarjeta
	barraEstadistica("Vuelo", config.VelocidadVuelo / 85, Color3.fromRGB(90, 220, 255), 5).Parent = tarjeta

	for i, ranura in ORDEN_RANURAS do
		local poder = if ranura == "Primario" then poderes.Primario else poderes.Secundario
		texto({
			Text = `{poder.Icono} {poder.Nombre}  <font color="#FFE150">[{TECLAS[ranura]}] Nv. {Poderes.NivelMinimo(poder)}</font>`,
			RichText = true,
			Font = FUENTE_TEXTO,
			Size = UDim2.fromScale(1, 0.08),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 5 + i,
			Parent = tarjeta,
		}, 0)
	end

	local boton = botonCaricatura("¡ELEGIR!", config.ColorPrincipal, {
		Size = UDim2.fromScale(0.9, 0.13),
		LayoutOrder = 10,
		Parent = tarjeta,
	})
	boton.Activated:Connect(function()
		eventoElegir:FireServer(config.Id)
		UIController.CerrarMenu()
	end)
	botonesElegir[config.Id] = boton
end

local ventanaMenu: Ventana

local function construirMenu()
	ventanaMenu = crearVentana("SelectorHeroina", 980, 540, COLOR_ROSA, 10, function()
		UIController.CerrarMenu()
	end)
	local contenedor = ventanaMenu.tarjeta
	contenedor.BackgroundColor3 = COLOR_FONDO_OSCURO
	menu = ventanaMenu.fondo

	texto({
		Text = "SUGAR TOWN",
		Position = UDim2.fromOffset(70, 14),
		Size = UDim2.new(1, -140, 0, 70),
		TextColor3 = COLOR_ROSA,
		ZIndex = 11,
		Parent = contenedor,
	}, 5)
	texto({
		Text = "Heroínas al Rescate · ¡Elige a tu heroína!",
		Position = UDim2.fromOffset(70, 86),
		Size = UDim2.new(1, -140, 0, 34),
		TextColor3 = COLOR_AMARILLO,
		ZIndex = 11,
		Parent = contenedor,
	}, 3)

	local fila: Frame = crear("Frame", {
		Position = UDim2.fromOffset(20, 134),
		Size = UDim2.new(1, -40, 1, -154),
		BackgroundTransparency = 1,
		Parent = contenedor,
	}, {
		crear("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0.03, 0),
		}),
	})

	for i, id in Heroinas.Orden do
		crearTarjeta(Heroinas.Lista[id], fila, i)
	end
end

-- ¿Eligió heroína en ESTA sesión? (atributo que pone el servidor)
local function heroinaElegida(): boolean
	return jugador:GetAttribute("HeroinaElegida") == true
end

function UIController.AbrirMenu()
	-- "ACTUAL ✓" solo si de verdad la eligió en esta sesión
	local actual = if heroinaElegida() then configActual().Id else nil
	for id, boton in botonesElegir do
		boton.Text = if id == actual then "ACTUAL ✓" else "¡ELEGIR!"
	end
	menuAbierto = true
	abrirVentana(ventanaMenu)
end

function UIController.CerrarMenu()
	menuAbierto = false
	cerrarVentana(ventanaMenu)
end

function UIController.MenuAbierto(): boolean
	for _, v in ventanas do
		if v.abierta then
			return true
		end
	end
	return menuAbierto or mejorasAbierto or tiendaAbierta
end

-- Zonas del HUD (en coordenadas de la interfaz) sobre las que no deben dibujarse carteles 3D.
function UIController.ZonasHud(): { GuiObject }
	local zonas: { GuiObject } = {}
	local candidatos: { Instance? } = {
		hudPanel,
		if tituloOleada then tituloOleada.Parent else nil,
		pildoraRecompensa,
		if columnaDerecha then columnaDerecha:FindFirstChild("Fila") else nil,
		radar,
		columnaLateral,
	}
	if acciones then
		for _, hijo in acciones:GetChildren() do
			table.insert(candidatos, hijo)
		end
	end
	for _, objeto in candidatos do
		if objeto and objeto:IsA("GuiObject") and objeto.Visible then
			table.insert(zonas, objeto)
		end
	end
	return zonas
end

-- ─── HUD ─────────────────────────────────────────────────────────────────────
-- Distribución (igual en PC y móvil; cada grupo lleva un UIScale según el tamaño de pantalla):
--   arriba izquierda: tarjeta de la heroína · arriba centro: píldora de oleada
--   arriba derecha: monedas + amigos y radar · lado izquierdo: columna de iconos
--   abajo derecha: GOLPE, poderes y VOLAR en arco alrededor del botón de saltar
--   abajo izquierda: libre para el joystick · centro: siempre libre

-- Escala común según la pantalla (diseño pensado para ~1000×540 px de zona segura)
local function escalaPantalla(): number
	local tam = gui.AbsoluteSize
	if tam.X < 1 or tam.Y < 1 then
		return 1
	end
	return math.clamp(math.min(tam.X / 1000, tam.Y / 540), 0.6, 1.3)
end

-- Añade un UIScale que sigue a la escala de pantalla.
local function escalable(grupo: GuiObject)
	local escala: UIScale = crear("UIScale", { Name = "EscalaPantalla", Parent = grupo })
	table.insert(escalasPantalla, escala)
end

-- Tarjeta compacta: retrato, nombre, vida, frascos de Esencia y nivel.
local ALTO_TARJETA = 128 -- alto de diseño de la tarjeta de la heroína

local function construirHud()
	local panel: Frame = crear("Frame", {
		Name = "HUD",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(300, ALTO_TARJETA),
		BackgroundColor3 = COLOR_FONDO,
		BackgroundTransparency = 0.08,
		Parent = gui,
	}, {
		esquinas(20),
		crear("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 160, 200)),
		}),
	})
	escalable(panel)
	hudPanel = panel
	hudTrazo = contorno(4, NEGRO)
	hudTrazo.Parent = panel

	-- Retrato circular con la cara y el peinado reales de la heroína
	local marco: Frame = crear("Frame", {
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.fromOffset(90, 90),
		BackgroundColor3 = Color3.fromRGB(255, 240, 250),
		Parent = panel,
	}, { esquinas(45) })
	crear("UIStroke", { Thickness = 4, Color = NEGRO, Parent = marco })
	anilloRetrato = crear("UIStroke", { Thickness = 3, Color = COLOR_ROSA, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	visorRetrato = crear("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 190, 210),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = marco,
	}, { esquinas(45) })
	anilloRetrato.Parent = marco
	camaraRetrato = crear("Camera", { FieldOfView = 28, Parent = visorRetrato })
	visorRetrato.CurrentCamera = camaraRetrato
	hudIcono = texto({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromOffset(102, 104),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 3,
		Parent = panel,
	}, 2)

	-- Nombre + vida
	hudNombre = texto({
		Position = UDim2.fromOffset(108, 7),
		Size = UDim2.new(1, -116, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, 2.5)
	local fondoVida: Frame = crear("Frame", {
		Position = UDim2.fromOffset(108, 30),
		Size = UDim2.new(1, -116, 0, 22),
		BackgroundColor3 = COLOR_FONDO_OSCURO,
		ClipsDescendants = true,
		Parent = panel,
	}, { esquinas(11), contorno(2.5, NEGRO) })
	barraVida = crear("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 80, 120),
		Parent = fondoVida,
	}, {
		esquinas(11),
		crear("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) }),
	})
	textoVida = texto({ Size = UDim2.fromScale(1, 1), Font = FUENTE_TEXTO, ZIndex = 2, Parent = fondoVida }, 2)

	-- Frascos de ⭐ Esencia Estelar (botón: también lanza el Estallido en móvil)
	local medidor: TextButton = crear("TextButton", {
		Position = UDim2.fromOffset(108, 56),
		Size = UDim2.new(1, -116, 0, 30),
		BackgroundTransparency = 1,
		Text = "",
		Parent = panel,
	})
	medidor.Activated:Connect(function()
		local callback = alPulsarEstallido
		if callback then
			callback()
		end
	end)
	for i = 1, NUM_FRASCOS do
		local frasco: Frame = crear("Frame", {
			Position = UDim2.fromOffset((i - 1) * 21, 5),
			Size = UDim2.fromOffset(16, 24),
			BackgroundColor3 = COLOR_FONDO_OSCURO,
			ClipsDescendants = true,
			Parent = medidor,
		}, { esquinas(6), contorno(2, NEGRO) })
		crear("Frame", {
			Name = "Liquido",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = COLOR_ORO,
			Parent = frasco,
		}, { esquinas(6) })
		table.insert(frascos, frasco)
	end
	textoEsencia = texto({
		Position = UDim2.fromOffset(NUM_FRASCOS * 21 + 4, 4),
		Size = UDim2.new(1, -(NUM_FRASCOS * 21 + 4), 0, 24),
		TextColor3 = COLOR_ORO,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "⭐ ESENCIA",
		Parent = medidor,
	}, 2)

	-- Nivel + experiencia
	textoNivel = texto({
		Position = UDim2.fromOffset(108, 87),
		Size = UDim2.fromOffset(46, 17),
		TextColor3 = COLOR_AMARILLO,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Nv. 1",
		Parent = panel,
	}, 2)
	local fondoExperiencia: Frame = crear("Frame", {
		Position = UDim2.fromOffset(158, 92),
		Size = UDim2.new(1, -166, 0, 8),
		BackgroundColor3 = COLOR_FONDO_OSCURO,
		ClipsDescendants = true,
		Parent = panel,
	}, { esquinas(4), contorno(2, NEGRO) })
	barraExperiencia = crear("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLOR_AMARILLO,
		Parent = fondoExperiencia,
	}, { esquinas(4) })

	-- Próximo poder que se desbloquea al subir de nivel
	textoProximo = texto({
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.new(1, -24, 0, 17),
		Font = FUENTE_TEXTO,
		TextColor3 = BLANCO,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Text = "",
		Parent = panel,
	}, 1.5)
end

-- ─── Columna izquierda (solo iconos), monedas, amigos ──────────────────────

local function botonIcono(icono: string, nombre: string, orden: number, padre: Instance, accion: () -> ()): TextButton
	local boton: TextButton = crear("TextButton", {
		Name = nombre,
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = COLOR_FONDO,
		BackgroundTransparency = 0.25,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = orden,
		Parent = padre,
	}, { esquinas(16), contorno(2.5, NEGRO) })
	texto({
		Text = icono,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		Parent = boton,
	})
	local escala: UIScale = crear("UIScale", { Parent = boton })
	boton.MouseEnter:Connect(function()
		TweenService:Create(escala, TweenInfo.new(0.12), { Scale = 1.08 }):Play()
	end)
	boton.MouseLeave:Connect(function()
		TweenService:Create(escala, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	boton.Activated:Connect(function()
		EfectosController.SonidoBoton()
		accion()
	end)
	return boton
end

local function invitarAmigos()
	local ok, puede = pcall(function()
		return SocialService:CanSendGameInviteAsync(jugador)
	end)
	if ok and puede then
		pcall(function()
			SocialService:PromptGameInvite(jugador)
		end)
	end
end

local LADO_BOTON = 54
local HUECO_BOTON = 8
local ALTO_COLUMNA = LADO_BOTON * 5 + HUECO_BOTON * 4

-- Parte superior del joystick por defecto de Roblox (móvil), en coordenadas de la interfaz.
local function arribaJoystick(): number?
	local touchGui = jugador.PlayerGui:FindFirstChild("TouchGui")
	if not touchGui then
		return nil
	end
	-- El círculo VISIBLE del joystick (ThumbstickStart en el dinámico). Su zona táctil invisible
	-- (ThumbstickFrame) es mucho más alta; nuestros botones van por encima (DisplayOrder mayor).
	for _, nombre in { "ThumbstickStart", "ThumbstickFrame" } do
		local objeto = touchGui:FindFirstChild(nombre, true)
		if objeto and objeto:IsA("GuiObject") and objeto.Visible and objeto.AbsoluteSize.X > 1 then
			return objeto.AbsolutePosition.Y - gui.AbsolutePosition.Y
		end
	end
	return nil
end

-- Debajo de la tarjeta (con hueco) y por encima del joystick. Botones de al menos 44 px reales y
-- 10 px entre ellos; si no caben en una columna se usan más (hasta una sola fila), rellenando por columnas para que
-- el orden sea siempre Clases, Mejoras, Tienda, Amigos, Lobby.
local MINIMO_BOTON_PX = 44
local HUECO_PX = 10
local function ajustarColumnaLateral(escala: number)
	local alto = gui.AbsoluteSize.Y
	local tarjeta = hudPanel
	local bordeTarjeta = if tarjeta
		then tarjeta.AbsolutePosition.Y + tarjeta.AbsoluteSize.Y - gui.AbsolutePosition.Y + 4 * escala + HUECO_PX
		else (10 + ALTO_TARJETA + 8) * escala
	local limiteInferior = alto - HUECO_PX
	local joystick = arribaJoystick()
	if joystick then
		limiteInferior = math.min(limiteInferior, joystick - HUECO_PX)
	end
	local disponible = math.max(limiteInferior - bordeTarjeta, MINIMO_BOTON_PX)

	local visibles = 0
	for _, hijo in columnaLateral:GetChildren() do
		if hijo:IsA("GuiButton") and hijo.Visible then
			visibles += 1
		end
	end
	visibles = math.max(visibles, 1)
	local lado = math.max(MINIMO_BOTON_PX, LADO_BOTON * escala)
	local columnas, filas = 1, visibles
	for c = 1, visibles do -- en pantallas muy bajas acaba en una fila bajo la tarjeta
		columnas = c
		filas = math.ceil(visibles / c)
		if filas * lado + (filas - 1) * HUECO_PX <= disponible then
			break
		end
	end
	-- Si ni en una fila cabe, se encoge un poco (nunca por debajo de 40 px)
	lado = math.max(40, math.min(lado, (disponible - (filas - 1) * HUECO_PX) / filas))

	local escalaCol = lado / LADO_BOTON
	local hueco = HUECO_PX / escalaCol -- en px de diseño: 10 px reales tras el UIScale
	rejillaColumna.FillDirectionMaxCells = filas
	rejillaColumna.CellPadding = UDim2.fromOffset(hueco, hueco)
	columnaLateral.Size = UDim2.fromOffset(columnas * LADO_BOTON + (columnas - 1) * hueco, filas * LADO_BOTON + (filas - 1) * hueco)
	escalaColumna.Scale = escalaCol
	local altoReal = filas * lado + (filas - 1) * HUECO_PX
	local arriba = math.clamp(alto * 0.5 - altoReal / 2, bordeTarjeta, math.max(bordeTarjeta, limiteInferior - altoReal))
	columnaLateral.Position = UDim2.fromOffset(10 * escala, arriba)
end

local function construirColumnaLateral()
	local columna: Frame = crear("Frame", {
		Name = "ColumnaLateral",
		Position = UDim2.fromOffset(10, 140), -- la coloca ajustarColumnaLateral()
		Size = UDim2.fromOffset(54, ALTO_COLUMNA),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	rejillaColumna = crear("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical, -- por columnas: el orden se lee de arriba abajo
		CellSize = UDim2.fromOffset(LADO_BOTON, LADO_BOTON),
		CellPadding = UDim2.fromOffset(HUECO_BOTON, HUECO_BOTON),
		Parent = columna,
	})
	columnaLateral = columna
	escalaColumna = crear("UIScale", { Parent = columna })
	botonClases = botonIcono("⚔️", "Clases", 1, columna, function()
		UIController.AbrirMenu()
	end)
	botonIcono("🏆", "Mejoras", 2, columna, function()
		UIController.AbrirMejoras()
	end)
	botonIcono("💎", "Tienda", 3, columna, function()
		UIController.AbrirTienda()
	end)
	botonIcono("👥", "Amigos", 4, columna, function()
		abrirVentana(ventanaAmigos)
	end)
	botonLobby = botonIcono("🏠", "Lobby", 5, columna, function()
		eventoLobby:FireServer()
	end)
	botonLobby.BackgroundColor3 = COLOR_ROSA
	botonLobby.Visible = false
end

local textoDerrotados: TextLabel
local ESPACIO_ARRIBA_DERECHA = 18 -- px de diseño entre las monedas, el botón de amigos y el radar

-- Ventana de amigos (la abren el icono lateral y el botón "x1"): explica el impulso e invita.
local function construirVentanaAmigos()
	ventanaAmigos = crearVentana("VentanaAmigos", 460, 330, Color3.fromRGB(110, 205, 255), 16, function()
		cerrarVentana(ventanaAmigos)
	end)
	local tarjeta = ventanaAmigos.tarjeta
	texto({
		Text = "👥 AMIGOS",
		Position = UDim2.fromOffset(70, 12),
		Size = UDim2.new(1, -140, 0, 44),
		TextColor3 = Color3.fromRGB(110, 205, 255),
		Parent = tarjeta,
	}, 4)
	local lista: Frame = crear("Frame", {
		Position = UDim2.fromOffset(24, 70),
		Size = UDim2.new(1, -48, 0, 150),
		BackgroundTransparency = 1,
		Parent = tarjeta,
	}, { crear("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	texto({ Text = "Juega con amigos y gana más monedas:", Size = UDim2.new(1, 0, 0, 24), Font = FUENTE_TEXTO, LayoutOrder = 1, Parent = lista }, 1.5)
	for i, linea in { "1 amigo = x2 monedas", "2 amigos = x3 monedas", "3 amigos = x4 monedas" } do
		texto({ Text = linea, Size = UDim2.new(1, 0, 0, 22), Font = FUENTE_TEXTO, TextColor3 = Color3.fromRGB(150, 230, 255), LayoutOrder = 1 + i, Parent = lista }, 1.5)
	end
	textoAmigos = texto({ Text = "", Size = UDim2.new(1, 0, 0, 24), TextColor3 = COLOR_AMARILLO, LayoutOrder = 10, Parent = lista }, 2)
	local invitar = botonCaricatura("INVITAR AMIGOS", Color3.fromRGB(40, 140, 230), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(280, 64),
		Parent = tarjeta,
	})
	invitar.Activated:Connect(invitarAmigos)
end

-- Arriba derecha: [moneda 120  👾 3  +] [👥 x1] y debajo el radar.
local function construirColumnaDerecha()
	columnaDerecha = crear("Frame", {
		Name = "ColumnaDerecha",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(300, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	escalable(columnaDerecha)

	local fila: Frame = crear("Frame", {
		Name = "Fila",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
		Parent = columnaDerecha,
	}, {
		crear("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, ESPACIO_ARRIBA_DERECHA),
		}),
	})

	-- Monedas y monstruos derrotados, cada número con su icono (+ abre la tienda)
	local caja: Frame = crear("Frame", {
		Name = "Monedas",
		Size = UDim2.fromOffset(196, 42),
		BackgroundColor3 = COLOR_FONDO_OSCURO,
		BackgroundTransparency = 0.25,
		LayoutOrder = 1,
		Parent = fila,
	}, { esquinas(14), contorno(2.5, NEGRO) })
	local contenido: Frame = crear("Frame", {
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.new(1, -54, 1, -12),
		BackgroundTransparency = 1,
		Parent = caja,
	}, {
		crear("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
		}),
	})
	iconoMoneda({ Size = UDim2.fromScale(1, 0.95), LayoutOrder = 1, Parent = contenido })
	textoMonedas = texto({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 26,
		TextColor3 = COLOR_AMARILLO,
		Text = "0",
		LayoutOrder = 2,
		Parent = contenido,
	}, 2)
	crear("Frame", { Size = UDim2.fromOffset(8, 1), BackgroundTransparency = 1, LayoutOrder = 3, Parent = contenido })
	texto({
		Text = "👾",
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		LayoutOrder = 4,
		Parent = contenido,
	})
	textoDerrotados = texto({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 26,
		TextColor3 = Color3.fromRGB(205, 160, 255),
		Text = "0",
		LayoutOrder = 5,
		Parent = contenido,
	}, 2)
	local mas = botonCaricatura("+", Color3.fromRGB(60, 200, 80), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		Parent = caja,
	})
	mas.Activated:Connect(function()
		UIController.AbrirTienda()
	end)

	-- Amigos: "👥 x1" abre la ventana de amigos
	botonAmigos = crear("TextButton", {
		Name = "Amigos",
		Size = UDim2.fromOffset(80, 42),
		BackgroundColor3 = Color3.fromRGB(40, 90, 150),
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Font = FUENTE_TITULO,
		Text = "👥 x1",
		TextColor3 = BLANCO,
		TextScaled = true,
		LayoutOrder = 2,
		Parent = fila,
	}, {
		esquinas(14),
		contorno(2.5, NEGRO),
		crear("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	botonAmigos.Activated:Connect(function()
		EfectosController.SonidoBoton()
		abrirVentana(ventanaAmigos)
	end)
end

local function actualizarAmigos()
	local valor = jugador:GetAttribute("AmigosConectados")
	local n = if typeof(valor) == "number" then valor else 0
	local multiplicador = math.min(Juego.MaxMultiplicadorAmigos, 1 + n)
	botonAmigos.Text = `👥 x{multiplicador}`
	textoAmigos.Text = `Amigos conectados: {n}  ·  ahora ganas x{multiplicador}`
end

-- Panel del tubo de Esencia Estelar del lobby: cada cliente muestra SUS datos.
local function actualizarPanelRecompensa()
	local enLobby = jugador:GetAttribute("EnCiudad") ~= true
	pildoraRecompensa.Visible = enLobby
	if not enLobby then
		return
	end
	local intervalo = Juego.Lobby.IntervaloRecompensa
	local listaEn = jugador:GetAttribute("RecompensaEn")
	local impulsosValor = jugador:GetAttribute("Impulsos")
	local impulsos = if typeof(impulsosValor) == "number" then impulsosValor else 0
	local restante = if typeof(listaEn) == "number" then math.max(0, listaEn - Workspace:GetServerTimeNow()) else intervalo
	local segundos = math.ceil(restante)
	local tiempo = if segundos > 0
		then string.format("⏱ %02d:%02d", segundos // 60, segundos % 60)
		else "⏱ ¡LISTO! Reclámalo en la consola"
	textoRecompensa.Text = `{tiempo}   ⭐ Impulsos {impulsos}/{Juego.Lobby.MaxImpulsos}`
end

-- ─── Retrato ────────────────────────────────────────────────────────────────

-- Usa el retrato que prepara el servidor (cara del jugador + traje de la clase ACTUAL, en el lobby
-- y en la ciudad). Si aún no está, copia el personaje en pantalla.
local function actualizarRetrato()
	-- Sin heroína elegida en esta sesión: la foto es el avatar normal del jugador
	local carpeta = ReplicatedStorage:FindFirstChild("Retratos")
	local elegida = jugador:GetAttribute("HeroinaElegida") == true
	local preparado = if carpeta and elegida then carpeta:FindFirstChild(tostring(jugador.UserId)) else nil
	local character: Model? = if preparado and preparado:IsA("Model") then preparado else jugador.Character
	if not character then
		return
	end
	for _, hijo in visorRetrato:GetChildren() do
		if not hijo:IsA("Camera") then
			hijo:Destroy()
		end
	end
	local archivable = character.Archivable
	character.Archivable = true
	local copia = character:Clone()
	character.Archivable = archivable
	if not copia then
		return
	end
	-- Fuera scripts, sonidos y efectos (los LocalScript dentro de PlayerGui SÍ se ejecutarían)
	for _, d in copia:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("BillboardGui") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	-- Dentro de un WorldModel las uniones (Motor6D, soldaduras de accesorios) se resuelven: el
	-- modelo de ReplicatedStorage no está simulado y sus piezas no estarían en su sitio.
	local mundo = Instance.new("WorldModel")
	mundo.Parent = visorRetrato
	copia.Parent = mundo
	local raizCopia = copia:FindFirstChild("HumanoidRootPart")
	if raizCopia and raizCopia:IsA("BasePart") then
		raizCopia.Anchored = true
	end
	RunService.Heartbeat:Wait() -- un paso para que las uniones coloquen las piezas
	local cabeza = copia:FindFirstChild("Head")
	if cabeza and cabeza:IsA("BasePart") then
		local objetivo = cabeza.Position + Vector3.new(0, 0.15, 0)
		camaraRetrato.CFrame = CFrame.lookAt((cabeza.CFrame * CFrame.new(0.6, 0.35, -4.2)).Position, objetivo)
	end
end

-- Pide un retrato nuevo tras un retraso (el servidor tarda un momento en vestir a la heroína).
local function pedirRetrato(retraso: number)
	retratoPendiente += 1
	local id = retratoPendiente
	task.delay(retraso, function()
		if id == retratoPendiente then
			actualizarRetrato()
		end
	end)
end

-- ─── Esencia Estelar ────────────────────────────────────────────────────────

local function actualizarEsencia()
	local valor = jugador:GetAttribute("Energia")
	local energia = if typeof(valor) == "number" then valor else 0
	local porFrasco = Poderes.EnergiaMaxima / NUM_FRASCOS
	for i, frasco in frascos do
		local llenado = math.clamp((energia - (i - 1) * porFrasco) / porFrasco, 0, 1)
		local liquido = frasco:FindFirstChild("Liquido") :: Frame?
		if liquido then
			TweenService:Create(liquido, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, llenado) }):Play()
		end
	end
	local lleno = energia >= Poderes.EnergiaMaxima
	textoEsencia.Text = if lleno then "¡PULSA R!" else "⭐ ESENCIA"
	textoEsencia.TextColor3 = if lleno then BLANCO else COLOR_ORO
end

-- ─── Radar ──────────────────────────────────────────────────────────────────

local function construirRadar()
	radar = crear("Frame", {
		Name = "Radar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 42 + ESPACIO_ARRIBA_DERECHA + 20), -- bajo monedas/amigos, con hueco para el rótulo "RADAR"
		Size = UDim2.fromOffset(RADIO_RADAR_PX * 2 + 12, RADIO_RADAR_PX * 2 + 12),
		BackgroundColor3 = Color3.fromRGB(20, 30, 50),
		BackgroundTransparency = 0.2,
		ClipsDescendants = false,
		Parent = columnaDerecha,
	}, { esquinas(999), contorno(4, NEGRO) })
	crear("UIStroke", { Thickness = 2, Color = Color3.fromRGB(80, 255, 160), Transparency = 0.3, Parent = crear("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = radar,
	}, { esquinas(999) }) })
	texto({
		Text = "RADAR",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -1),
		Size = UDim2.fromOffset(70, 16),
		TextColor3 = Color3.fromRGB(80, 255, 160),
		Parent = radar,
	}, 2)
	flechaRadar = texto({
		Text = "▲",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 5,
		Parent = radar,
	}, 2)
end

local function puntoRadar(indice: number): Frame
	local punto = puntosRadar[indice]
	if not punto then
		punto = crear("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(9, 9),
			ZIndex = 3,
			Parent = radar,
		}, { esquinas(999), contorno(1.5, NEGRO) })
		puntosRadar[indice] = punto
	end
	assert(punto)
	punto.Visible = true
	return punto
end

local function actualizarRadar()
	local character = jugador.Character
	local raiz = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local camara = Workspace.CurrentCamera
	if not (raiz and raiz:IsA("BasePart")) or not camara then
		return
	end
	local mirada = Vector3.new(camara.CFrame.LookVector.X, 0, camara.CFrame.LookVector.Z)
	local adelante = if mirada.Magnitude > 0.01 then mirada.Unit else Vector3.new(0, 0, -1)
	local derecha = adelante:Cross(Vector3.yAxis)
	local origen = raiz.Position
	local escala = RADIO_RADAR_PX / ALCANCE_RADAR
	local centro = RADIO_RADAR_PX + 6

	local usados = 0
	local function colocar(posicion: Vector3, color: Color3, tamano: number)
		local relativa = posicion - origen
		local plano = Vector2.new(relativa:Dot(derecha), -relativa:Dot(adelante)) * escala
		if plano.Magnitude > RADIO_RADAR_PX - 6 then
			plano = plano.Unit * (RADIO_RADAR_PX - 6) -- en el borde si está lejos
		end
		usados += 1
		local punto = puntoRadar(usados)
		punto.Position = UDim2.fromOffset(centro + plano.X, centro + plano.Y)
		punto.Size = UDim2.fromOffset(tamano, tamano)
		punto.BackgroundColor3 = color
	end

	for _, edificio in CollectionService:GetTagged("Edificio") do
		if edificio:IsA("Model") and edificio:IsDescendantOf(Workspace) then
			local caido = edificio:GetAttribute("Destruido") == true
			colocar(edificio:GetPivot().Position, if caido then Color3.fromRGB(110, 110, 120) else Color3.fromRGB(60, 255, 120), 14)
		end
	end
	for _, monstruo in CollectionService:GetTagged("Enemigo") do
		if monstruo:IsA("Model") and monstruo:IsDescendantOf(Workspace) then
			colocar(monstruo:GetPivot().Position, Color3.fromRGB(255, 50, 60), 9)
		end
	end
	for _, otra in Players:GetPlayers() do
		local otroPersonaje = otra.Character
		if otra ~= jugador and otroPersonaje then
			colocar(otroPersonaje:GetPivot().Position, Color3.fromRGB(120, 200, 255), 8)
		end
	end
	for i = usados + 1, #puntosRadar do
		puntosRadar[i].Visible = false -- se reutilizan: sin crear/destruir Frames cada vez
	end

	-- Flecha: hacia dónde mira la heroína respecto a la cámara
	local miradaPersonaje = raiz.CFrame.LookVector
	flechaRadar.Rotation = math.deg(math.atan2(miradaPersonaje:Dot(derecha), miradaPersonaje:Dot(adelante)))
end

-- ─── Tienda Robux ───────────────────────────────────────────────────────────

local function actualizarTienda()
	local enStudio = RunService:IsStudio()
	for _, articulo in TiendaRobux.Lista do
		local boton = botonesTienda[articulo.Clave]
		if boton then
			local precio = preciosReales[articulo.Clave] or articulo.PrecioReferencia
			local tieneArma = articulo.Arma == true and Armas.Tiene(jugador, articulo.Clave)
			if (articulo.Tipo == "Pase" and TiendaRobux.TienePase(jugador, articulo.Clave)) or tieneArma then
				boton.Text = "✓ TUYO"
				boton.BackgroundColor3 = Color3.fromRGB(60, 200, 110)
			elseif articulo.Id == 0 and not enStudio then
				boton.Text = "Próximamente"
				boton.BackgroundColor3 = COLOR_APAGADO
			elseif articulo.Id == 0 then
				boton.Text = "PROBAR GRATIS"
				boton.BackgroundColor3 = Color3.fromRGB(0, 190, 255)
			else
				boton.Text = `R$ {precio}`
				boton.BackgroundColor3 = COLOR_ORO
			end
		end
		-- Armas: segunda opción con monedas (nunca es obligatorio pagar)
		local botonMonedas = botonesMonedasArma[articulo.Clave]
		local arma = Armas.PorClave(articulo.Clave)
		if botonMonedas and arma then
			local nivel = Poderes.NivelDe(jugador)
			local monedasValor = jugador:GetAttribute("Monedas")
			local monedas = if typeof(monedasValor) == "number" then monedasValor else 0
			if Armas.Tiene(jugador, arma.Clave) then
				botonMonedas.Visible = false
			elseif nivel < arma.NivelMonedas then
				botonMonedas.Visible = true
				botonMonedas.Text = `🔒 o con monedas al Nv. {arma.NivelMonedas}`
				botonMonedas.BackgroundColor3 = COLOR_APAGADO
			else
				botonMonedas.Visible = true
				botonMonedas.Text = if monedas >= arma.CostoMonedas
					then `o {arma.CostoMonedas} monedas`
					else `🔒 Te faltan {arma.CostoMonedas - monedas} monedas`
				botonMonedas.BackgroundColor3 = if monedas >= arma.CostoMonedas then Color3.fromRGB(60, 200, 90) else COLOR_APAGADO
			end
		end
	end
end

local function cargarPreciosReales()
	for _, articulo in TiendaRobux.Lista do
		if articulo.Id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(
						articulo.Id,
						if articulo.Tipo == "Pase" then Enum.InfoType.GamePass else Enum.InfoType.Product
					)
				end)
				if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
					preciosReales[articulo.Clave] = info.PriceInRobux
					actualizarTienda()
				end
			end)
		end
	end
end

local ventanaTienda: Ventana

local function construirTienda()
	ventanaTienda = crearVentana("TiendaRobux", 760, 480, NEGRO, 14, function()
		UIController.CerrarTienda()
	end)
	panelTienda = ventanaTienda.fondo
	local tarjeta = ventanaTienda.tarjeta
	crear("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 245, 220), Color3.fromRGB(200, 170, 120)), Parent = tarjeta })
	tarjeta.BackgroundColor3 = BLANCO

	texto({
		Text = "💎 TIENDA ROBUX",
		Position = UDim2.fromOffset(70, 12),
		Size = UDim2.new(1, -140, 0, 46),
		TextColor3 = COLOR_ORO,
		Parent = tarjeta,
	}, 4)
	texto({
		Text = if RunService:IsStudio() then "Modo prueba de Studio: las compras no gastan Robux" else "Apoya Sugar Town y consigue ventajas",
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FUENTE_TEXTO,
		Parent = tarjeta,
	}, 1.5)

	local lista: ScrollingFrame = crear("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 92),
		Size = UDim2.new(1, -32, 1, -108),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = tarjeta,
	}, {
		crear("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
	})

	for i, articulo in TiendaRobux.Lista do
		if articulo.OcultoEnTienda then
			continue -- p. ej. "Revivir": solo se ofrece al ser derrotada
		end
		local fila: Frame = crear("Frame", {
			Size = UDim2.new(1, -8, 0, 84),
			BackgroundColor3 = COLOR_FONDO_OSCURO,
			BackgroundTransparency = 0.15,
			LayoutOrder = i,
			Parent = lista,
		}, { esquinas(16), contorno(3, if articulo.Tipo == "Pase" then COLOR_ORO else NEGRO) })
		texto({ Text = articulo.Icono, Position = UDim2.fromOffset(10, 14), Size = UDim2.fromOffset(56, 56), Parent = fila })
		texto({
			Text = if articulo.Tipo == "Pase" then `{articulo.Nombre}  · PASE` else articulo.Nombre,
			Position = UDim2.fromOffset(74, 10),
			Size = UDim2.new(1, -220, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = fila,
		}, 2)
		texto({
			Text = articulo.Descripcion,
			Position = UDim2.fromOffset(74, 42),
			Size = UDim2.new(1, -220, 0, 32),
			Font = FUENTE_TEXTO,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = fila,
		})
		local esArma = articulo.Arma == true
		local boton = botonCaricatura("", COLOR_ORO, {
			AnchorPoint = Vector2.new(1, if esArma then 0 else 0.5),
			Position = if esArma then UDim2.new(1, -12, 0, 8) else UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, if esArma then 40 else 50),
			Parent = fila,
		})
		boton.Activated:Connect(function()
			eventoTienda:FireServer(articulo.Clave)
		end)
		botonesTienda[articulo.Clave] = boton
		if esArma then
			local monedas = botonCaricatura("", Color3.fromRGB(60, 200, 90), {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -12, 1, -8),
				Size = UDim2.fromOffset(150, 30),
				Parent = fila,
			})
			monedas.Activated:Connect(function()
				eventoDesbloquearArma:FireServer(articulo.Clave)
			end)
			botonesMonedasArma[articulo.Clave] = monedas
		end
	end
	actualizarTienda()
end

function UIController.AbrirTienda()
	actualizarTienda()
	tiendaAbierta = true
	abrirVentana(ventanaTienda)
end

function UIController.CerrarTienda()
	tiendaAbierta = false
	cerrarVentana(ventanaTienda)
end

function UIController.AlUsarEstallido(callback: () -> ())
	alPulsarEstallido = callback
end

-- ─── Botones de acción (abajo derecha, en arco alrededor del botón de saltar) ─
-- Tamaños de diseño (px a escala 1). La posición se calcula en colocarAcciones().
local DIAMETRO_GOLPE = 118
local DIAMETRO_PODER = 78
local DIAMETRO_VOLAR = 66
local DIAMETRO_ARMA = 72
local esTactil = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Insignia con la tecla (solo en PC/mando: en móvil se oculta)
local function insignia(textoTecla: string, padre: GuiObject, ancho: number)
	local marco: Frame = crear("Frame", {
		Name = "Insignia",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(ancho, 0.26),
		BackgroundColor3 = COLOR_AMARILLO,
		ZIndex = 5,
		Visible = not esTactil,
		Parent = padre,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }), contorno(2) })
	texto({ Text = textoTecla, TextColor3 = COLOR_CONTORNO, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = marco })
end

local function crearRanura(ranura: Ranura, padre: Instance): Ranura_UI
	local boton: TextButton = crear("TextButton", {
		Name = ranura,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLOR_FONDO,
		AutoButtonColor = true,
		Text = "",
		Parent = padre,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.28, 0) }) })
	local trazo = contorno(3.5)
	trazo.Parent = boton

	local icono = texto({ Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.5), Parent = boton })
	local nombre = texto({
		Position = UDim2.fromScale(0.06, 0.62),
		Size = UDim2.fromScale(0.88, 0.3),
		Font = FUENTE_TEXTO,
		TextWrapped = true,
		Parent = boton,
	}, 1)
	insignia(TECLAS[ranura], boton, 0.42)

	local cortina: Frame = crear("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 3,
		Parent = boton,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.28, 0) }) })
	local cuenta = texto({ Size = UDim2.fromScale(1, 1), ZIndex = 4, Text = "", Parent = boton }, 3)

	-- Candado: el poder aún no está desbloqueado (muestra el nivel necesario). Bajo la insignia
	-- de la tecla (ZIndex 5) para que se siga leyendo E / Q.
	local candado: Frame = crear("Frame", {
		Name = "Candado",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(25, 15, 40),
		BackgroundTransparency = 0.05,
		ZIndex = 4,
		Visible = false,
		Parent = boton,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.28, 0) }) })
	local iconoCandado = texto({ Text = "🔒", Position = UDim2.fromScale(0, 0.08), Size = UDim2.fromScale(1, 0.48), ZIndex = 4, Parent = candado })
	local textoCandado = texto({
		Position = UDim2.fromScale(0.05, 0.58),
		Size = UDim2.fromScale(0.9, 0.32),
		TextColor3 = COLOR_AMARILLO,
		ZIndex = 4,
		Parent = candado,
	}, 1.5)

	boton.Activated:Connect(function()
		local callback = alPulsarPoder
		if callback then
			callback(ranura)
		end
	end)

	return {
		boton = boton,
		icono = icono,
		nombre = nombre,
		trazo = trazo,
		cortina = cortina,
		cuenta = cuenta,
		candado = candado,
		textoCandado = textoCandado,
		iconoCandado = iconoCandado,
		poderId = "",
	}
end

-- Botón redondo con icono y rótulo (GOLPE / VOLAR)
local function botonRedondo(nombre: string, icono: string, rotulo: string, color: Color3, tecla: string, padre: Instance): TextButton
	local boton: TextButton = crear("TextButton", {
		Name = nombre,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Text = "",
		Parent = padre,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	contorno(3.5).Parent = boton
	texto({ Name = "Icono", Text = icono, Position = UDim2.fromScale(0.15, 0.1), Size = UDim2.fromScale(0.7, 0.5), Parent = boton })
	texto({
		Name = "Rotulo",
		Text = rotulo,
		Position = UDim2.fromScale(0.1, 0.6),
		Size = UDim2.fromScale(0.8, 0.24),
		Font = FUENTE_TEXTO,
		Parent = boton,
	}, 1.5)
	insignia(tecla, boton, 0.42)
	local escalaBoton: UIScale = crear("UIScale", { Parent = boton })
	boton.Activated:Connect(function()
		escalaBoton.Scale = 0.88
		TweenService:Create(escalaBoton, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	return boton
end

-- Centro y radio (px absolutos) del botón de saltar de Roblox; en PC, un punto virtual en la esquina.
-- Devuelve también si hay botón de saltar (en PC no lo hay).
-- OJO: Roblox OCULTA el botón de saltar a ratos (volando, sentada...) y lo vuelve a mostrar en el
-- mismo sitio. Su hueco se reserva SIEMPRE en táctil, esté visible o no; si aún no existe, se usa
-- la posición por defecto de Roblox (para que al aparecer no caiga encima de GOLPE).
local function referenciaSalto(escala: number): (Vector2, number, boolean)
	local touchGui = jugador:FindFirstChild("PlayerGui") and jugador.PlayerGui:FindFirstChild("TouchGui")
	local salto = if touchGui then touchGui:FindFirstChild("JumpButton", true) else nil
	if salto and salto:IsA("GuiObject") and salto.AbsoluteSize.X > 1 then
		return salto.AbsolutePosition + salto.AbsoluteSize / 2, salto.AbsoluteSize.X / 2, true
	end
	if UserInputService.TouchEnabled then
		-- Misma fórmula que el TouchJumpController de Roblox
		local pantalla = gui.AbsoluteSize
		local pequena = math.min(pantalla.X, pantalla.Y) <= 500
		local lado = if pequena then 70 else 120
		local arribaIzq = gui.AbsolutePosition
			+ Vector2.new(pantalla.X - (lado * 1.5 - 10), if pequena then pantalla.Y - lado - 20 else pantalla.Y - lado * 1.75)
		return arribaIzq + Vector2.one * (lado / 2), lado / 2, true
	end
	local esquina = gui.AbsolutePosition + gui.AbsoluteSize
	return esquina - Vector2.new(78, 78) * escala, 34 * escala, false
end

-- Ángulos (grados, 0 = derecha, 90 = arriba) de E, Q y VOLAR: del arco más abierto al más cerrado.
-- En pantallas bajas se usa el primero que no choca con el radar, las monedas ni el borde.
local ARCOS = {
	{ e = 128, q = 92, v = 152 },
	{ e = 138, q = 104, v = 160 },
	{ e = 148, q = 116, v = 166 },
	{ e = 158, q = 128, v = 172 },
}

-- Distancia mínima (px) entre los bordes de dos botones de acción, para que cada toque
-- llegue al botón correcto (se mide entre círculos: centro a centro ≥ r1 + r2 + esto).
local SEPARACION_MINIMA = 10

-- ¿El círculo (en coordenadas de la interfaz) toca el rectángulo de este objeto?
local function chocaConObjeto(centro: Vector2, radio: number, objeto: GuiObject?): boolean
	if not objeto or not objeto.Visible then
		return false
	end
	local margen = Vector2.new(4, 4)
	local p1 = objeto.AbsolutePosition - gui.AbsolutePosition - margen
	local p2 = p1 + objeto.AbsoluteSize + margen * 2
	local cercano = Vector2.new(math.clamp(centro.X, p1.X, p2.X), math.clamp(centro.Y, p1.Y, p2.Y))
	return (cercano - centro).Magnitude < radio
end

-- Coloca GOLPE, E, Q y VOLAR en arco alrededor del botón de saltar (sin taparlo).
local function colocarAcciones()
	if not acciones then
		return
	end
	local escala = escalaPantalla()
	local centroSalto, radioSalto, haySalto = referenciaSalto(escala)
	local origen = centroSalto - gui.AbsolutePosition
	local rGolpe = DIAMETRO_GOLPE * escala / 2
	-- E y Q son cuadrados redondeados: sus esquinas salen un poco del círculo inscrito
	local rPoder = DIAMETRO_PODER * escala / 2 * 1.18
	local rVolar = DIAMETRO_VOLAR * escala / 2
	local function punto(angulo: number, distancia: number): Vector2
		local a = math.rad(angulo)
		return origen + Vector2.new(math.cos(a), -math.sin(a)) * distancia
	end
	local obstaculos: { GuiObject? } = {
		radar,
		columnaDerecha and columnaDerecha:FindFirstChild("Fila") :: GuiObject?,
	}

	local golpe = punto(180, radioSalto + rGolpe + SEPARACION_MINIMA + 2)
	if not haySalto then
		-- PC: sin botón de saltar, GOLPE va en la esquina y E, Q y VOLAR en arco a su alrededor
		local esquina = gui.AbsoluteSize
		golpe = esquina - Vector2.new(rGolpe + 18 * escala, rGolpe + 14 * escala)
	end
	local function desde(base: Vector2, angulo: number, distancia: number): Vector2
		local a = math.rad(angulo)
		return base + Vector2.new(math.cos(a), -math.sin(a)) * distancia
	end
	-- Candidatos: arcos alrededor del salto y, para pantallas muy bajas, E y Q encima de GOLPE
	-- y VOLAR a su izquierda.
	local candidatos: { { e: Vector2, q: Vector2, v: Vector2 } } = {}
	if not haySalto then
		-- Hueco extra para las insignias de tecla (Clic, E, Q, F) que asoman por arriba
		local cerca = rGolpe + rPoder + 20 * escala
		table.insert(candidatos, {
			e = desde(golpe, 172, cerca),
			q = desde(golpe, 98, cerca),
			v = desde(golpe, 136, cerca + rPoder + rVolar + 10 * escala),
		})
	end
	local distanciaPoder = radioSalto + rPoder + 46 * escala
	for _, arco in ARCOS do
		table.insert(candidatos, {
			e = punto(arco.e, distanciaPoder),
			q = punto(arco.q, distanciaPoder),
			v = punto(arco.v, radioSalto + rVolar + 132 * escala),
		})
	end
	-- Alternativas junto a GOLPE (pantallas muy bajas): siempre con SEPARACION_MINIMA entre círculos
	local junto = rGolpe + rPoder + SEPARACION_MINIMA + 2
	local lejosVolar = rGolpe + rVolar + rPoder * 2 + SEPARACION_MINIMA * 2 + 4
	for _, angulos in { { e = 150, q = 95, v = 178 }, { e = 160, q = 110, v = 180 }, { e = 180, q = 90, v = 135 } } do
		table.insert(candidatos, {
			e = desde(golpe, angulos.e, junto),
			q = desde(golpe, angulos.q, junto),
			v = desde(golpe, angulos.v, lejosVolar),
		})
	end

	-- Penalización de cada candidato: solaparse entre botones es lo peor (los toques fallan);
	-- luego chocar con el radar/monedas o salirse por arriba. Se elige el de menor penalización.
	local elegido: { [string]: Vector2 } = {}
	local mejorPenalizacion = math.huge
	for _, candidato in candidatos do
		local posiciones: { { centro: Vector2, radio: number, clave: string? } } = {
			{ centro = golpe, radio = rGolpe },
			{ centro = candidato.e, radio = rPoder, clave = "e" },
			{ centro = candidato.q, radio = rPoder, clave = "q" },
			{ centro = candidato.v, radio = rVolar, clave = "v" },
		}
		if haySalto then
			table.insert(posiciones, 1, { centro = origen, radio = radioSalto })
		end
		local penalizacion = 0
		for i, pa in posiciones do
			if pa.centro.Y - pa.radio < 0 or pa.centro.X - pa.radio < 0 then
				penalizacion += 10
			end
			for _, obstaculo in obstaculos do
				if pa.clave and chocaConObjeto(pa.centro, pa.radio, obstaculo) then
					penalizacion += 10
				end
			end
			for j = i + 1, #posiciones do
				local pb = posiciones[j]
				if (pa.centro - pb.centro).Magnitude < pa.radio + pb.radio + SEPARACION_MINIMA then
					penalizacion += 1000
				end
			end
		end
		if penalizacion < mejorPenalizacion then
			mejorPenalizacion = penalizacion
			for _, pa in posiciones do
				if pa.clave then
					elegido[pa.clave] = pa.centro
				end
			end
			if penalizacion == 0 then
				break
			end
		end
	end

	local function colocar(boton: GuiObject, diametro: number, centro: Vector2)
		local tam = diametro * escala
		boton.Size = UDim2.fromOffset(tam, tam)
		boton.Position = UDim2.fromOffset(centro.X, centro.Y)
	end
	colocar(botonCombo, DIAMETRO_GOLPE, golpe)
	if ranuras.Primario then
		colocar(ranuras.Primario.boton, DIAMETRO_PODER, elegido.e)
	end
	if ranuras.Secundario then
		colocar(ranuras.Secundario.boton, DIAMETRO_PODER, elegido.q)
	end
	colocar(botonVolar, DIAMETRO_VOLAR, elegido.v)

	-- ARMA: busca un hueco libre alrededor de VOLAR / E / GOLPE (sin tocar a nadie)
	local arma = botonArma
	if arma and arma.Visible then
		local rArma = DIAMETRO_ARMA * escala / 2
		local ocupados: { { centro: Vector2, radio: number } } = {
			{ centro = golpe, radio = rGolpe },
			{ centro = elegido.e, radio = rPoder },
			{ centro = elegido.q, radio = rPoder },
			{ centro = elegido.v, radio = rVolar },
		}
		if haySalto then
			table.insert(ocupados, { centro = origen, radio = radioSalto })
		end
		local opciones: { Vector2 } = {}
		for _, base in { { elegido.v, rVolar }, { elegido.e, rPoder }, { golpe, rGolpe } } do
			for _, angulo in { 90, 135, 180, 45, 225 } do
				table.insert(opciones, desde(base[1] :: Vector2, angulo, (base[2] :: number) + rArma + SEPARACION_MINIMA + 2))
			end
		end
		local mejor: Vector2 = opciones[1]
		local menor = math.huge
		for _, centro in opciones do
			local castigo = 0
			if centro.Y - rArma < 0 or centro.X - rArma < 0 then
				castigo += 10
			end
			for _, obstaculo in obstaculos do
				if chocaConObjeto(centro, rArma, obstaculo) then
					castigo += 10
				end
			end
			for _, otro in ocupados do
				if (centro - otro.centro).Magnitude < rArma + otro.radio + SEPARACION_MINIMA then
					castigo += 1000
				end
			end
			if castigo < menor then
				menor, mejor = castigo, centro
				if castigo == 0 then
					break
				end
			end
		end
		colocar(arma, DIAMETRO_ARMA, mejor)
	end
end

local function construirAcciones()
	acciones = crear("Frame", {
		Name = "Acciones",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	botonCombo = botonRedondo("Combo", "👊", "GOLPE", COLOR_ROSA, "Clic", acciones)
	botonCombo.Activated:Connect(function()
		local callback = alPulsarGolpe
		if callback then
			callback()
		end
	end)
	ranuras.Primario = crearRanura("Primario", acciones)
	ranuras.Secundario = crearRanura("Secundario", acciones)
	botonVolar = botonRedondo("Volar", "🦸", "VOLAR", Color3.fromRGB(90, 170, 255), "F", acciones)
	-- El área de toque es el rectángulo del botón: E, Q y VOLAR van por encima de GOLPE
	-- para que las esquinas vacías del círculo grande no les roben toques.
	botonCombo.ZIndex = 1
	for _, ranura in ranuras do
		ranura.boton.ZIndex = 2
	end
	botonVolar.ZIndex = 2
	botonVolar.Activated:Connect(function()
		local callback = alPulsarVolar
		if callback then
			callback()
		end
	end)

	-- ARMA (oculto hasta tener alguna)
	local arma = botonRedondo("Arma", "🍬", "ARMA", Color3.fromRGB(255, 170, 60), "T", acciones)
	arma.ZIndex = 2
	arma.Visible = false
	arma.Activated:Connect(function()
		local callback = alPulsarArma
		if callback then
			callback()
		end
	end)
	cortinaArma = crear("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 3,
		Parent = arma,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	cuentaArma = texto({ Size = UDim2.fromScale(1, 1), ZIndex = 4, Text = "", Parent = arma }, 3)
	-- Cambiar de arma (solo si tiene varias): pastilla "1/3" pegada abajo
	local cambio: TextButton = crear("TextButton", {
		Name = "CambiarArma",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1.02),
		Size = UDim2.fromScale(0.7, 0.34),
		BackgroundColor3 = COLOR_FONDO,
		AutoButtonColor = true,
		Font = FUENTE_TITULO,
		Text = "1/1",
		TextColor3 = COLOR_AMARILLO,
		TextScaled = true,
		ZIndex = 6,
		Visible = false,
		Parent = arma,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }), contorno(2) })
	cambio.Activated:Connect(function()
		EfectosController.SonidoBoton()
		local callback = alPulsarCambioArma
		if callback then
			callback()
		end
	end)
	botonArma = arma
	cambioArma = cambio
	colocarAcciones()
end

-- Rótulo del botón VOLAR según el estado (atributo "Volando" que pone el servidor)
local function actualizarBotonVolar()
	local character = jugador.Character
	local volando = character ~= nil and character:GetAttribute("Volando") == true
	local rotulo = botonVolar:FindFirstChild("Rotulo")
	if rotulo and rotulo:IsA("TextLabel") then
		rotulo.Text = if volando then "BAJAR" else "VOLAR"
	end
end

-- Contador "xN COMBO!" (arriba a la derecha del centro). Se oculta solo si no hay más aciertos.
local function construirContadorCombo()
	contadorCombo = crear("Frame", {
		Name = "ContadorCombo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.74, 0.34),
		Size = UDim2.fromOffset(260, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	escalable(contadorCombo)
	escalaCombo = crear("UIScale", { Parent = crear("Frame", {
		Name = "Contenido",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = contadorCombo,
	}) })
	local contenido = escalaCombo.Parent :: Frame
	textoCombo = texto({ Size = UDim2.new(1, 0, 0, 74), TextColor3 = COLOR_AMARILLO, Rotation = -6, Parent = contenido }, 5)
	textoBonoCombo = texto({
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 32),
		TextColor3 = COLOR_ORO,
		Text = "",
		Rotation = -6,
		Parent = contenido,
	}, 3)
end

function UIController.AlGolpear(callback: () -> ())
	alPulsarGolpe = callback
end

function UIController.AlUsarArma(callback: () -> ())
	alPulsarArma = callback
end

function UIController.AlCambiarArma(callback: () -> ())
	alPulsarCambioArma = callback
end

-- Muestra el arma equipada (nil = no tiene ninguna: el botón se oculta).
function UIController.MostrarArma(arma: { Nombre: string, Icono: string, Poder: Types.PoderConfig }?, indice: number, total: number)
	local boton = botonArma
	if not boton then
		return
	end
	local antes = boton.Visible
	boton.Visible = arma ~= nil
	if arma then
		armaPoderId = arma.Poder.Id
		local icono = boton:FindFirstChild("Icono")
		if icono and icono:IsA("TextLabel") then
			icono.Text = arma.Icono
		end
		boton.BackgroundColor3 = arma.Poder.Color
	end
	local cambio = cambioArma
	if cambio then
		cambio.Visible = total > 1
		cambio.Text = `{indice}/{total}`
	end
	if antes ~= boton.Visible then
		colocarAcciones()
	end
end

function UIController.AlVolar(callback: () -> ())
	alPulsarVolar = callback
end

-- Muestra el contador de combo. "bono" = este golpe dio monedas extra (las suma el servidor).
function UIController.MostrarCombo(conteo: number, bono: boolean, duracion: number)
	if conteo < 2 then
		return -- un solo golpe no es combo
	end
	comboActual += 1
	local id = comboActual
	textoCombo.Text = `x{conteo} COMBO!`
	textoCombo.TextColor3 = if conteo >= 20 then COLOR_ROSA elseif conteo >= 10 then COLOR_NARANJA else COLOR_AMARILLO
	textoBonoCombo.Text = if bono then "💰 ¡BONO DE COMBO!" else ""
	contadorCombo.Visible = true
	escalaCombo.Scale = if bono then 1.6 else 1.3
	TweenService:Create(escalaCombo, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(duracion, function()
		if id == comboActual then
			contadorCombo.Visible = false
		end
	end)
end

-- Arriba centro: píldora con la oleada, monstruos y edificios
local function construirPanelOleada()
	local panel: Frame = crear("Frame", {
		Name = "PanelOleada",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(220, 56),
		BackgroundColor3 = COLOR_FONDO,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }), contorno(3, COLOR_ROSA) })
	escalable(panel)
	tituloOleada = texto({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 26),
		TextColor3 = COLOR_ROSA,
		Parent = panel,
	}, 2.5)
	infoOleada = texto({
		Position = UDim2.fromOffset(14, 31),
		Size = UDim2.new(1, -28, 0, 19),
		Font = FUENTE_TEXTO,
		Parent = panel,
	}, 1.5)

	-- Píldora del lobby (debajo de la de la oleada; escala con ella)
	pildoraRecompensa = crear("Frame", {
		Name = "PildoraRecompensa",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(300, 28),
		BackgroundColor3 = COLOR_FONDO,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = panel,
	}, { crear("UICorner", { CornerRadius = UDim.new(0.5, 0) }), contorno(2.5, Color3.fromRGB(255, 120, 230)) })
	textoRecompensa = texto({
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -20, 1, -6),
		Font = FUENTE_TEXTO,
		Text = "",
		Parent = pildoraRecompensa,
	}, 1.5)
end

local function construirAvisoBloqueo()
	avisoBloqueo = texto({
		Name = "AvisoBloqueo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(460, 34),
		TextColor3 = COLOR_AMARILLO,
		ZIndex = 25,
		Visible = false,
		Parent = gui,
	}, 3)
	escalable(avisoBloqueo)
end

local function construirAnuncio()
	local contenedor: Frame = crear("Frame", {
		Name = "Anuncio",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.new(0.9, 0, 0, 150),
		BackgroundTransparency = 1,
		ZIndex = 9, -- por debajo de las ventanas (10+): un anuncio no tapa un menú abierto
		Visible = false,
		Parent = gui,
	})
	escalable(contenedor)
	anuncioEscala = crear("UIScale", { Parent = contenedor })
	anuncioTitulo = texto({ Size = UDim2.new(1, 0, 0, 96), ZIndex = 30, Parent = contenedor }, 6)
	anuncioSubtitulo = texto({
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 30,
		TextColor3 = BLANCO,
		Parent = contenedor,
	}, 3)
end

local function mostrarAnuncio(titulo: string, subtitulo: string, color: Color3)
	anuncioActual += 1
	local id = anuncioActual
	local contenedor = anuncioTitulo.Parent :: Frame
	anuncioTitulo.Text = titulo
	anuncioTitulo.TextColor3 = color
	anuncioSubtitulo.Text = subtitulo
	for _, etiqueta in { anuncioTitulo, anuncioSubtitulo } do
		etiqueta.TextTransparency = 0
		local trazo = etiqueta:FindFirstChildOfClass("UIStroke")
		if trazo then
			trazo.Transparency = 0
		end
	end
	contenedor.Visible = true
	anuncioEscala.Scale = 2.2
	TweenService:Create(anuncioEscala, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(2.8, function()
		if id ~= anuncioActual then
			return -- llegó otro anuncio
		end
		local info = TweenInfo.new(0.5)
		for _, etiqueta in { anuncioTitulo, anuncioSubtitulo } do
			TweenService:Create(etiqueta, info, { TextTransparency = 1 }):Play()
			local trazo = etiqueta:FindFirstChildOfClass("UIStroke")
			if trazo then
				TweenService:Create(trazo, info, { Transparency = 1 }):Play()
			end
		end
		task.wait(0.5)
		if id == anuncioActual then
			contenedor.Visible = false
		end
	end)
end

local function numeroAtributo(nombre: string): number
	local valor = ReplicatedStorage:GetAttribute(nombre)
	return if typeof(valor) == "number" then valor else 0
end

local function actualizarOleada()
	local estado = ReplicatedStorage:GetAttribute("EstadoPartida")
	local oleada = numeroAtributo("Oleada")
	local cuenta = numeroAtributo("CuentaAtras")
	local monstruos = numeroAtributo("MonstruosVivos")
	local enPie = numeroAtributo("EdificiosEnPie")
	local totales = numeroAtributo("EdificiosTotales")

	if estado == "Preparacion" then
		tituloOleada.Text = "¡PREPÁRATE!"
	elseif estado == "Derrota" then
		tituloOleada.Text = "CIUDAD CAÍDA"
	elseif estado == "Descanso" then
		tituloOleada.Text = `OLEADA {oleada} ✓`
	else
		tituloOleada.Text = `OLEADA {oleada}`
	end

	local partes = { `👾 {monstruos}`, `🏢 {enPie}/{totales}` }
	if cuenta > 0 then
		table.insert(partes, `⏱ {cuenta}`)
	end
	infoOleada.Text = table.concat(partes, "    ")
end

local ultimoNivelVisto: number? = nil
local function actualizarExperiencia()
	local nivel = jugador:GetAttribute("Nivel")
	if typeof(nivel) == "number" then
		if ultimoNivelVisto and nivel > ultimoNivelVisto then
			EfectosController.Sonido("SubirNivel") -- fanfarria al subir de nivel
		end
		ultimoNivelVisto = nivel
	end
	local experiencia = jugador:GetAttribute("Experiencia")
	local n: number = if typeof(nivel) == "number" then nivel else 1
	local xp: number = if typeof(experiencia) == "number" then experiencia else 0
	textoNivel.Text = `Nv. {n}`
	local proporcion = math.clamp(xp / (n * Juego.ExperienciaPorNivel), 0, 1)
	TweenService:Create(barraExperiencia, TweenInfo.new(0.3), { Size = UDim2.fromScale(proporcion, 1) }):Play()
end

-- Candados de E/Q según el nivel y la línea "próximo poder" de la tarjeta.
local function minutos(segundos: number): string
	local s = math.max(0, math.ceil(segundos))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Estado de cada ranura cada frame: bloqueada (candado + nivel), láser por tiempo (listo /
-- cuenta atrás activa / recarga con candado de reloj) o permanente.
local function actualizarEstadoRanuras()
	local config = configActual()
	local ahora = Workspace:GetServerTimeNow()
	for ranura, ui in ranuras do
		local poder = Poderes.Obtener(config.Id, ranura)
		local estado, restante = Poderes.EstadoUso(jugador, poder, ahora)
		local tapado = estado == "Bloqueado" or estado == "Recarga"
		ui.candado.Visible = tapado
		if estado == "Bloqueado" then
			ui.iconoCandado.Text = "🔒"
			ui.textoCandado.Text = `Nv. {Poderes.NivelMinimo(poder)}`
		elseif estado == "Recarga" then
			ui.iconoCandado.Text = "⏳"
			ui.textoCandado.Text = minutos(restante)
		end
		if estado == "Listo" then
			ui.nombre.Text = `⏱ {minutos(Poderes.LaserTemporal.Activo)}`
			ui.nombre.TextColor3 = COLOR_AMARILLO
		elseif estado == "Activo" then
			ui.nombre.Text = `⏱ {minutos(restante)}`
			ui.nombre.TextColor3 = if restante <= 10 then Color3.fromRGB(255, 110, 110) else Color3.fromRGB(120, 255, 150)
		else
			ui.nombre.Text = poder.Nombre
			ui.nombre.TextColor3 = BLANCO
		end
		ui.trazo.Color = if tapado then COLOR_APAGADO else poder.Color
	end
end

actualizarDesbloqueos = function()
	local config = configActual()
	local nivel = Poderes.NivelDe(jugador)
	actualizarEstadoRanuras()
	local proximo = Poderes.ProximoDesbloqueo(config.Id, nivel)
	local laser = Poderes.Obtener(config.Id, "Secundario")
	local laserTemporal = laser.Tipo == "Laser" and nivel >= Poderes.NivelMinimo(laser) and nivel < laser.NivelRequerido
	if not heroinaElegida() then
		textoProximo.Text = `<font color="#FFE150">Toca ⚔️ CLASES para elegir</font>`
	elseif laserTemporal then
		textoProximo.Text = `{laser.Icono} {laser.Nombre} sin límite de tiempo <font color="#FFE150">(al Nv. {laser.NivelRequerido})</font>`
	elseif proximo then
		-- Un solo "Nv." en la línea para que no parezca un segundo nivel de la heroína
		textoProximo.Text = `Próximo poder: {proximo.Icono} {proximo.Nombre} <font color="#FFE150">(al Nv. {Poderes.NivelMinimo(proximo)})</font>`
	else
		textoProximo.Text = `<font color="#7DFFB0">✨ ¡Todos los poderes desbloqueados!</font>`
	end
end

-- El botón de Clases late y brilla mientras no haya elegido heroína (indica dónde tocar).
local pulsoClases = 0
local function pulsarBotonClases(activo: boolean)
	pulsoClases += 1
	local id = pulsoClases
	local trazo = botonClases:FindFirstChildOfClass("UIStroke")
	local escala = botonClases:FindFirstChildOfClass("UIScale")
	if not activo then
		if trazo then
			trazo.Color = NEGRO
			trazo.Thickness = 2.5
		end
		if escala then
			escala.Scale = 1
		end
		return
	end
	task.spawn(function()
		while id == pulsoClases do
			local t = os.clock() * 4
			local onda = (math.sin(t) + 1) / 2
			if trazo then
				trazo.Color = COLOR_AMARILLO:Lerp(COLOR_ROSA, onda)
				trazo.Thickness = 3 + 2 * onda
			end
			if escala then
				escala.Scale = 1 + 0.1 * onda
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function actualizarClase()
	local config = configActual()
	local elegida = heroinaElegida()
	hudIcono.Text = config.Icono
	hudIcono.Visible = elegida
	hudNombre.Text = if elegida then `HEROÍNA DE {string.upper(config.Nombre)}` else "¡ELIGE TU HEROÍNA!"
	hudNombre.TextColor3 = if elegida then config.ColorPrincipal:Lerp(BLANCO, 0.2) else COLOR_AMARILLO
	anilloRetrato.Color = if elegida then config.ColorPrincipal else COLOR_APAGADO
	barraVida.BackgroundColor3 = config.ColorPrincipal
	-- La foto siempre se ve: avatar normal del jugador sin elegir, la heroína al elegir
	visorRetrato.Visible = true
	pulsarBotonClases(not elegida)
	pedirRetrato(0.8)

	for ranura, ui in ranuras do
		local poder = Poderes.Obtener(config.Id, ranura)
		ui.poderId = poder.Id
		ui.icono.Text = poder.Icono
		ui.nombre.Text = poder.Nombre
		ui.trazo.Color = poder.Color
	end
	actualizarDesbloqueos()
end

local function actualizarEnfriamientoArma(ahora: number)
	local cortina, cuenta = cortinaArma, cuentaArma
	if not cortina or not cuenta then
		return
	end
	local datos = enfriamientos[armaPoderId]
	local restante = if datos then datos.fin - ahora else 0
	if restante > 0 and datos then
		cortina.Size = UDim2.fromScale(1, restante / datos.duracion)
		cuenta.Text = if restante >= 1 then tostring(math.ceil(restante)) else string.format("%.1f", restante)
	elseif cuenta.Text ~= "" then
		cortina.Size = UDim2.fromScale(1, 0)
		cuenta.Text = ""
	end
end

local function actualizarEnfriamientos()
	actualizarEstadoRanuras()
	actualizarRescate()
	actualizarEnfriamientoArma(os.clock())
	local ahora = os.clock()
	for _, ui in ranuras do
		local datos = enfriamientos[ui.poderId]
		local restante = if datos then datos.fin - ahora else 0
		if restante > 0 and datos then
			ui.cortina.Size = UDim2.fromScale(1, restante / datos.duracion)
			ui.cuenta.Text = if restante >= 1 then tostring(math.ceil(restante)) else string.format("%.1f", restante)
		elseif ui.cuenta.Text ~= "" then
			ui.cortina.Size = UDim2.fromScale(1, 0)
			ui.cuenta.Text = ""
			-- Destello: el poder vuelve a estar listo
			ui.trazo.Thickness = 7
			TweenService:Create(ui.trazo, TweenInfo.new(0.3), { Thickness = 4 }):Play()
		end
	end
end

local function seguirVida(character: Model)
	for _, conexion in conexionesVida do
		conexion:Disconnect()
	end
	table.clear(conexionesVida)

	local encontrado = character:WaitForChild("Humanoid", 10)
	if not (encontrado and encontrado:IsA("Humanoid")) then
		return
	end
	local humanoid = encontrado :: Humanoid
	local function actualizar()
		local maximo = math.max(humanoid.MaxHealth, 1)
		local proporcion = math.clamp(humanoid.Health / maximo, 0, 1)
		TweenService:Create(barraVida, TweenInfo.new(0.2), { Size = UDim2.fromScale(proporcion, 1) }):Play()
		textoVida.Text = `{math.ceil(humanoid.Health)} / {math.floor(maximo)}`
	end
	table.insert(conexionesVida, humanoid.HealthChanged:Connect(actualizar))
	table.insert(conexionesVida, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(actualizar))
	actualizar()
end

local function actualizarMonedas()
	local monedas = jugador:GetAttribute("Monedas")
	local derrotados = jugador:GetAttribute("Derrotados")
	textoMonedas.Text = tostring(if typeof(monedas) == "number" then monedas else 0)
	textoDerrotados.Text = tostring(if typeof(derrotados) == "number" then derrotados else 0)
	textoMonedas.Rotation = -8
	TweenService:Create(textoMonedas, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
end

-- ─── Panel de mejoras ────────────────────────────────────────────────────────

local COLOR_COMPRAR = Color3.fromRGB(60, 200, 90)

local function actualizarMejoras()
	if not panelMejoras then
		return
	end
	local config = configActual()
	local monedasValor = jugador:GetAttribute("Monedas")
	local monedas = if typeof(monedasValor) == "number" then monedasValor else 0
	subtituloMejoras.Text = `Heroína de {config.Nombre} {config.Icono}  ·`
	monedasMejoras.Text = tostring(monedas)

	for tipo, fila in filasMejora do
		local datos = Mejoras.Lista[tipo]
		local nivel = Mejoras.Nivel(jugador, config.Id, tipo)
		local bono = math.floor(datos.BonoPorNivel * nivel * 100 + 0.5)
		fila.nivel.Text = `Nv. {nivel}/{datos.NivelMaximo}  (+{bono}%)`
		for i, pip in fila.pips do
			pip.BackgroundColor3 = if i <= nivel then config.ColorPrincipal else COLOR_FONDO_OSCURO
		end
		if nivel >= datos.NivelMaximo then
			fila.textoBoton.Text = "MÁX"
			fila.textoBoton.TextSize = 24
			fila.monedaBoton.Visible = false
			fila.boton.BackgroundColor3 = COLOR_APAGADO
		else
			local costo = Mejoras.Costo(tipo, nivel)
			if monedas >= costo then
				-- Alcanza: botón de color con la moneda y el precio
				fila.textoBoton.Text = tostring(costo)
				fila.textoBoton.TextSize = 24
				fila.monedaBoton.Visible = true
				fila.boton.BackgroundColor3 = COLOR_COMPRAR
			else
				-- No alcanza: gris, candado y cuánto falta
				fila.textoBoton.Text = `🔒 Te faltan {costo - monedas}`
				fila.textoBoton.TextSize = 17
				fila.monedaBoton.Visible = false
				fila.boton.BackgroundColor3 = COLOR_APAGADO
			end
		end
	end
end

local function crearFilaMejora(tipo: Types.TipoMejora, orden: number, padre: Instance)
	local datos = Mejoras.Lista[tipo]
	local fila: Frame = crear("Frame", {
		Size = UDim2.new(1, -8, 0, 96),
		BackgroundColor3 = COLOR_FONDO_OSCURO,
		BackgroundTransparency = 0.3,
		LayoutOrder = orden,
		Parent = padre,
	}, { esquinas(16) })

	texto({ Text = datos.Icono, Position = UDim2.fromOffset(10, 16), Size = UDim2.fromOffset(52, 52), Parent = fila })
	texto({
		Text = datos.Nombre,
		Position = UDim2.fromOffset(70, 8),
		Size = UDim2.new(0, 120, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = fila,
	}, 2)
	local nivel = texto({
		Position = UDim2.fromOffset(190, 10),
		Size = UDim2.new(1, -370, 0, 22),
		Font = FUENTE_TEXTO,
		TextColor3 = COLOR_AMARILLO,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = fila,
	}, 1)
	texto({
		Text = datos.Descripcion,
		Position = UDim2.fromOffset(70, 38),
		Size = UDim2.new(1, -250, 0, 18),
		Font = FUENTE_TEXTO,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = fila,
	})

	-- Indicadores de nivel (pips)
	local barra: Frame = crear("Frame", {
		Position = UDim2.fromOffset(70, 66),
		Size = UDim2.new(1, -250, 0, 14),
		BackgroundTransparency = 1,
		Parent = fila,
	}, {
		crear("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
		}),
	})
	local pips: { Frame } = {}
	for i = 1, datos.NivelMaximo do
		local pip: Frame = crear("Frame", {
			Size = UDim2.new(1 / datos.NivelMaximo, -4, 1, 0),
			BackgroundColor3 = COLOR_FONDO_OSCURO,
			LayoutOrder = i,
			Parent = barra,
		}, { esquinas(4), contorno(1.5) })
		table.insert(pips, pip)
	end

	-- Botón de compra: [moneda] precio (o "🔒 Te faltan X")
	local boton: TextButton = crear("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 56),
		BackgroundColor3 = COLOR_COMPRAR,
		AutoButtonColor = true,
		Text = "",
		Parent = fila,
	}, { esquinas(14), contorno(4) })
	local contenido: Frame = crear("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 0, 30),
		BackgroundTransparency = 1,
		Parent = boton,
	}, {
		crear("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
	local monedaBoton = iconoMoneda({ Size = UDim2.fromScale(1, 0.95), LayoutOrder = 1, Parent = contenido })
	local textoBoton = texto({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 24,
		LayoutOrder = 2,
		Parent = contenido,
	}, 2)
	boton.Activated:Connect(function()
		EfectosController.SonidoBoton()
		eventoComprar:FireServer(tipo)
	end)

	filasMejora[tipo] = { nivel = nivel, boton = boton, pips = pips, textoBoton = textoBoton, monedaBoton = monedaBoton }
end

local function construirPanelMejoras()
	ventanaMejoras = crearVentana("PanelMejoras", 600, 340, COLOR_NARANJA, 12, function()
		UIController.CerrarMejoras()
	end)
	panelMejoras = ventanaMejoras.fondo
	local tarjeta = ventanaMejoras.tarjeta

	texto({
		Text = "MEJORAR PODERES",
		Position = UDim2.fromOffset(70, 12),
		Size = UDim2.new(1, -140, 0, 44),
		TextColor3 = COLOR_NARANJA,
		Parent = tarjeta,
	}, 4)
	-- "Heroína de X 🛡️ · [moneda] 120"
	local filaSubtitulo: Frame = crear("Frame", {
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 0, 28),
		BackgroundTransparency = 1,
		Parent = tarjeta,
	}, {
		crear("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	subtituloMejoras = texto({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 22,
		Font = FUENTE_TEXTO,
		LayoutOrder = 1,
		Parent = filaSubtitulo,
	}, 1.5)
	iconoMoneda({ Size = UDim2.fromScale(1, 0.9), LayoutOrder = 2, Parent = filaSubtitulo })
	monedasMejoras = texto({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 24,
		TextColor3 = COLOR_AMARILLO,
		LayoutOrder = 3,
		Parent = filaSubtitulo,
	}, 2)

	-- Lista con scroll (si la pantalla es muy baja, nada queda cortado)
	local lista: ScrollingFrame = crear("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 100),
		Size = UDim2.new(1, -32, 1, -114),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = tarjeta,
	}, {
		crear("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
	})
	for i, tipo in Mejoras.Orden do
		crearFilaMejora(tipo, i, lista)
	end
end

function UIController.AbrirMejoras()
	actualizarMejoras()
	mejorasAbierto = true
	abrirVentana(ventanaMejoras)
end

function UIController.CerrarMejoras()
	mejorasAbierto = false
	cerrarVentana(ventanaMejoras)
end

-- ─── Derrota y rescate (lo decide RescateService en el servidor) ─────────────

local ventanaRescate: Ventana
local tiempoRescate: TextLabel
local botonRevivir: TextButton
local textoRevivir: TextLabel
local bannerDerribada: TextLabel
local botonRevivirYa: TextButton
local eventoDecision: RemoteEvent

local function construirRescate()
	eventoDecision = Remotes.Evento("DecisionRescate")
	-- Banner mientras espera a que una compañera la salve
	bannerDerribada = texto({
		Name = "BannerDerribada",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(620, 64),
		TextColor3 = COLOR_ROSA,
		RichText = true,
		ZIndex = 8,
		Visible = false,
		Parent = gui,
	}, 3)
	escalable(bannerDerribada)
	-- Mientras espera a una compañera también puede revivir YA pagando
	botonRevivirYa = botonCaricatura("", Color3.fromRGB(60, 200, 90), {
		Name = "BotonRevivirYa",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 44),
		Size = UDim2.fromOffset(340, 56),
		ZIndex = 8,
		Visible = false,
		Parent = gui,
	})
	escalable(botonRevivirYa)
	botonRevivirYa.Activated:Connect(function()
		EfectosController.SonidoBoton()
		eventoDecision:FireServer("Pagar")
	end)

	-- Ventana de decisión: sin X ni cierre al tocar fuera (hay que elegir una opción)
	ventanaRescate = crearVentana("VentanaRescate", 600, 360, COLOR_ROSA, 20, function() end)
	ventanaRescate.cerrar.Visible = false
	local tarjeta = ventanaRescate.tarjeta
	texto({
		Text = "¡TE DERROTARON!",
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 56),
		TextColor3 = COLOR_ROSA,
		Parent = tarjeta,
	}, 4)
	texto({
		Text = "¿Quieres seguir defendiendo Sugar Town?",
		Position = UDim2.fromOffset(20, 78),
		Size = UDim2.new(1, -40, 0, 28),
		Font = FUENTE_TEXTO,
		Parent = tarjeta,
	}, 1.5)
	tiempoRescate = texto({
		Position = UDim2.fromOffset(20, 110),
		Size = UDim2.new(1, -40, 0, 30),
		TextColor3 = COLOR_AMARILLO,
		Parent = tarjeta,
	}, 2)

	botonRevivir = crear("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 156),
		Size = UDim2.fromOffset(420, 76),
		BackgroundColor3 = Color3.fromRGB(60, 200, 90),
		AutoButtonColor = true,
		Text = "",
		Parent = tarjeta,
	}, { esquinas(18), contorno(4) })
	textoRevivir = texto({
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 1, -20),
		RichText = true,
		Parent = botonRevivir,
	}, 2.5)
	botonRevivir.Activated:Connect(function()
		EfectosController.SonidoBoton()
		eventoDecision:FireServer("Pagar")
	end)

	local botonLobbyRescate = botonCaricatura("🏠 VOLVER AL LOBBY", COLOR_ROSA, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 252),
		Size = UDim2.fromOffset(420, 70),
		Parent = tarjeta,
	})
	botonLobbyRescate.Activated:Connect(function()
		eventoDecision:FireServer("Lobby")
	end)
end

-- Cada frame: banner de derribada o ventana de decisión con su cuenta atrás.
actualizarRescate = function()
	local estado = jugador:GetAttribute("RescateEstado")
	local hasta = jugador:GetAttribute("RescateHasta")
	local restante = if typeof(hasta) == "number" then math.max(0, hasta - Workspace:GetServerTimeNow()) else 0
	local segundos = math.ceil(restante)

	bannerDerribada.Visible = estado == "Derribada"
	local articuloRevivir = TiendaRobux.PorClave("Revivir")
	local revivirDisponible = articuloRevivir ~= nil and (articuloRevivir.Id ~= 0 or RunService:IsStudio())
	botonRevivirYa.Visible = estado == "Derribada" and revivirDisponible
	if estado == "Derribada" then
		bannerDerribada.Text = `¡ESTÁS DERRIBADA!<br/><font size="20" color="#FFFFFF">Una compañera puede salvarte · {segundos} s</font>`
		if articuloRevivir and revivirDisponible then
			local precio = preciosReales[articuloRevivir.Clave] or articuloRevivir.PrecioReferencia
			botonRevivirYa.Text = if articuloRevivir.Id == 0 then "💖 REVIVIR YA (PRUEBA)" else `💖 REVIVIR YA · R$ {precio}`
		end
	end

	if estado == "Oferta" then
		if not ventanaRescate.abierta then
			-- Cierra las demás ventanas: esta decisión manda
			for _, v in ventanas do
				if v ~= ventanaRescate and v.abierta then
					v.alCerrar()
				end
			end
			abrirVentana(ventanaRescate)
		end
		tiempoRescate.Text = `Decide en {segundos} s · si no, vuelves al lobby`
		local articulo = TiendaRobux.PorClave("Revivir")
		local disponible = articulo ~= nil and (articulo.Id ~= 0 or RunService:IsStudio())
		if articulo and disponible then
			local precio = preciosReales[articulo.Clave] or articulo.PrecioReferencia
			local etiqueta = if articulo.Id == 0 then "PRUEBA GRATIS" else `R$ {precio}`
			textoRevivir.Text = `💖 REVIVIR <font color="#FFF2A0">({etiqueta})</font>`
			botonRevivir.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
			botonRevivir.Active = true
		else
			textoRevivir.Text = "💖 REVIVIR · Próximamente"
			botonRevivir.BackgroundColor3 = COLOR_APAGADO
			botonRevivir.Active = false
		end
	elseif ventanaRescate.abierta then
		cerrarVentana(ventanaRescate)
	end
end

-- ─── API pública ─────────────────────────────────────────────────────────────

-- Registra la función que se llama al pulsar una ranura de poder en pantalla.
function UIController.AlUsarPoder(callback: (Ranura) -> ())
	alPulsarPoder = callback
end

-- Aviso corto (abajo al centro).
function UIController.Aviso(mensaje: string)
	avisoActual += 1
	local id = avisoActual
	avisoBloqueo.Text = mensaje
	avisoBloqueo.TextTransparency = 0
	avisoBloqueo.Visible = true
	task.delay(1.6, function()
		if id == avisoActual then
			avisoBloqueo.Visible = false
		end
	end)
end

-- Aviso al pulsar un poder bloqueado.
function UIController.AvisoBloqueado(poder: Types.PoderConfig)
	avisoActual += 1
	local id = avisoActual
	avisoBloqueo.Text = `🔒 {poder.Icono} {poder.Nombre} se desbloquea en Nv. {Poderes.NivelMinimo(poder)}`
	avisoBloqueo.TextTransparency = 0
	avisoBloqueo.Visible = true
	task.delay(1.6, function()
		if id == avisoActual then
			avisoBloqueo.Visible = false
		end
	end)
end

function UIController.IniciarEnfriamiento(poderId: string, segundos: number)
	enfriamientos[poderId] = { fin = os.clock() + segundos, duracion = segundos }
end

function UIController.Init()
	eventoElegir = Remotes.Evento("ElegirHeroina")
	eventoComprar = Remotes.Evento("ComprarMejora")
	eventoTienda = Remotes.Evento("ComprarTienda")
	eventoDesbloquearArma = Remotes.Evento("DesbloquearArma")
	eventoLobby = Remotes.Evento("VolverLobby")

	gui = crear("ScreenGui", {
		Name = "SugarTownUI",
		ResetOnSpawn = false,
		-- Por encima de los controles táctiles de Roblox: un toque en GOLPE/E/Q/VOLAR nunca lo
		-- recibe el botón de saltar (los Frame transparentes no bloquean el joystick).
		DisplayOrder = 5,
		-- Zona segura: nada queda bajo los botones de Roblox, la muesca ni la barra de inicio
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = jugador:WaitForChild("PlayerGui"),
	})
	construirHud()
	construirColumnaDerecha()
	construirVentanaAmigos()
	construirAcciones()
	construirContadorCombo()
	construirPanelOleada()
	construirAnuncio()
	construirAvisoBloqueo()
	construirPanelMejoras()
	construirRescate()
	construirRadar()
	construirTienda()
	construirColumnaLateral()
	construirMenu()

	-- Escala según la pantalla (y al girar o cambiar el tamaño de la ventana)
	local function aplicarEscalas()
		local escala = escalaPantalla()
		for _, uiScale in escalasPantalla do
			uiScale.Scale = escala
		end
		ajustarColumnaLateral(escala)
		colocarAcciones()
		for _, v in ventanas do
			if v.abierta then
				ajustarVentana(v)
			end
		end
	end
	aplicarEscalas()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(aplicarEscalas)
end

function UIController.Start()
	actualizarClase()
	actualizarMonedas()
	jugador:GetAttributeChangedSignal("Arquetipo"):Connect(actualizarClase)
	jugador:GetAttributeChangedSignal("HeroinaElegida"):Connect(actualizarClase)
	jugador:GetAttributeChangedSignal("Monedas"):Connect(actualizarMonedas)
	jugador:GetAttributeChangedSignal("Derrotados"):Connect(actualizarMonedas)

	actualizarEsencia()
	jugador:GetAttributeChangedSignal("Energia"):Connect(actualizarEsencia)

	-- Retrato: el servidor lo regenera al cambiar de clase (ReplicatedStorage.Retratos.<UserId>)
	jugador.CharacterAdded:Connect(function()
		pedirRetrato(1.2)
	end)
	pedirRetrato(1.2)
	task.spawn(function()
		local carpeta = ReplicatedStorage:WaitForChild("Retratos")
		carpeta.ChildAdded:Connect(function(hijo)
			if hijo.Name == tostring(jugador.UserId) then
				pedirRetrato(0.1)
			end
		end)
		if carpeta:FindFirstChild(tostring(jugador.UserId)) then
			pedirRetrato(0.1)
		end
	end)

	-- Tienda: pases comprados y precios reales
	jugador.AttributeChanged:Connect(function(nombre)
		local relevante = string.sub(nombre, 1, #TiendaRobux.PrefijoPase) == TiendaRobux.PrefijoPase
			or string.sub(nombre, 1, #Armas.PrefijoAtributo) == Armas.PrefijoAtributo
			or nombre == "Monedas"
			or nombre == "Nivel"
		if tiendaAbierta and relevante then
			actualizarTienda()
		end
	end)
	cargarPreciosReales()

	-- Lobby / amigos
	local function actualizarBotonLobby()
		botonLobby.Visible = jugador:GetAttribute("EnCiudad") == true
		ajustarColumnaLateral(escalaPantalla())
	end
	actualizarBotonLobby()
	jugador:GetAttributeChangedSignal("EnCiudad"):Connect(actualizarBotonLobby)
	actualizarAmigos()
	jugador:GetAttributeChangedSignal("AmigosConectados"):Connect(actualizarAmigos)
	task.spawn(function()
		while true do
			actualizarPanelRecompensa()
			task.wait(1)
		end
	end)

	-- Radar a 10 Hz
	task.spawn(function()
		while true do
			actualizarRadar()
			task.wait(0.1)
		end
	end)

	-- El panel de mejoras se refresca con monedas, cambio de heroína o mejora comprada
	jugador.AttributeChanged:Connect(function(nombre)
		if
			mejorasAbierto
			and (
				nombre == "Monedas"
				or nombre == "Arquetipo"
				or string.sub(nombre, 1, #Mejoras.PrefijoAtributo) == Mejoras.PrefijoAtributo
			)
		then
			actualizarMejoras()
		end
	end)

	actualizarExperiencia()
	jugador:GetAttributeChangedSignal("Nivel"):Connect(actualizarExperiencia)
	jugador:GetAttributeChangedSignal("Nivel"):Connect(actualizarDesbloqueos)
	jugador:GetAttributeChangedSignal("Experiencia"):Connect(actualizarExperiencia)

	actualizarOleada()
	for _, atributo in { "EstadoPartida", "Oleada", "CuentaAtras", "MonstruosVivos", "EdificiosEnPie", "EdificiosTotales" } do
		ReplicatedStorage:GetAttributeChangedSignal(atributo):Connect(actualizarOleada)
	end

	Remotes.Evento("Anuncio").OnClientEvent:Connect(function(titulo: unknown, subtitulo: unknown, color: unknown)
		if typeof(titulo) == "string" and typeof(subtitulo) == "string" then
			mostrarAnuncio(
				titulo :: string,
				subtitulo :: string,
				if typeof(color) == "Color3" then color :: Color3 else COLOR_ROSA
			)
		end
	end)

	jugador.CharacterAdded:Connect(seguirVida)
	if jugador.Character then
		task.spawn(seguirVida, jugador.Character)
	end

	RunService.RenderStepped:Connect(actualizarEnfriamientos)

	-- El botón de saltar de Roblox aparece (o cambia de tamaño/posición) al reaparecer o girar la
	-- pantalla: recolocar el arco AL MOMENTO (y además cada segundo como red de seguridad).
	local function recolocar()
		task.defer(function()
			ajustarColumnaLateral(escalaPantalla())
			colocarAcciones()
		end)
	end
	local function vigilarSalto(boton: Instance)
		if boton.Name == "JumpButton" and boton:IsA("GuiObject") then
			boton:GetPropertyChangedSignal("AbsolutePosition"):Connect(recolocar)
			boton:GetPropertyChangedSignal("AbsoluteSize"):Connect(recolocar)
			recolocar()
		end
	end
	local function vigilarTouchGui(hijo: Instance)
		if hijo.Name ~= "TouchGui" then
			return
		end
		for _, d in hijo:GetDescendants() do
			vigilarSalto(d)
		end
		hijo.DescendantAdded:Connect(vigilarSalto)
		recolocar()
	end
	local playerGui = jugador:WaitForChild("PlayerGui")
	for _, hijo in playerGui:GetChildren() do
		vigilarTouchGui(hijo)
	end
	playerGui.ChildAdded:Connect(vigilarTouchGui)
	task.spawn(function()
		while true do
			task.wait(1)
			ajustarColumnaLateral(escalaPantalla())
			colocarAcciones()
			-- Ventanas abiertas: reajustar si la pantalla cambió (sin interrumpir la animación)
			for _, v in ventanas do
				local animando = v.animacion ~= nil and (v.animacion :: Tween).PlaybackState == Enum.PlaybackState.Playing
				if v.abierta and not animando and math.abs(v.escala.Scale - escalaVentana(v)) > 0.01 then
					ajustarVentana(v)
				end
			end
		end
	end)
	-- Rótulo VOLAR / BAJAR (las conexiones mueren con el personaje)
	local function seguirVuelo(character: Model)
		actualizarBotonVolar()
		character:GetAttributeChangedSignal("Volando"):Connect(actualizarBotonVolar)
	end
	jugador.CharacterAdded:Connect(seguirVuelo)
	if jugador.Character then
		seguirVuelo(jugador.Character)
	end

	-- Esc (o B en mando) cierra la última ventana abierta
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.ButtonB then
			return
		end
		for i = #ventanas, 1, -1 do
			local v = ventanas[i]
			if v.abierta then
				v.alCerrar()
				return
			end
		end
	end)

	UIController.AbrirMenu() -- menú inicial (se puede cerrar)
end

return UIController
