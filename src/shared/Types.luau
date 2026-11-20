--!strict
-- Tipos Luau compartidos entre servidor y cliente.

export type ArquetipoId = "Fuerza" | "Velocidad" | "Estrategia"

export type ConfigEstela = {
	ColorInicio: Color3, -- color pegado a la heroína
	ColorFin: Color3, -- color al final de la estela
	Ancho: number, -- grosor en studs (distancia entre los dos Attachment)
	Duracion: number, -- segundos que tarda la estela en desvanecerse (Trail.Lifetime)
}

-- Piezas de cuerpo R15 (ids de artículos del catálogo de avatares). La cabeza NO se cambia.
export type CuerpoCatalogo = {
	Torso: number,
	BrazoIzquierdo: number,
	BrazoDerecho: number,
	PiernaIzquierda: number,
	PiernaDerecha: number,
}

-- Traje de heroína hecho con artículos públicos del catálogo (ids de asset; 0 = sin esa pieza).
export type CatalogoAtuendo = {
	Cuerpo: CuerpoCatalogo,
	Pelo: number, -- accesorio de pelo (rígido)
	Accesorio: number, -- accesorio de cabeza pequeño (rígido, tipo Hat)
	Body: number, -- ropa en capas: body / mono (TShirt)
	Guantes: number, -- ropa en capas: guantes largos (Jacket)
	BotaIzquierda: number, -- ropa en capas: zapato izquierdo
	BotaDerecha: number, -- ropa en capas: zapato derecho
}

export type AtuendoConfig = {
	Catalogo: CatalogoAtuendo,
}

export type HeroinaConfig = {
	Id: ArquetipoId,
	Nombre: string,
	Descripcion: string,
	Icono: string, -- emoji usado en la UI
	ColorPrincipal: Color3,
	VidaMaxima: number,
	VelocidadVuelo: number, -- studs/s en vuelo normal
	VelocidadTurbo: number, -- studs/s manteniendo Shift
	FuerzaImpulso: number, -- aceleración máxima (studs/s²); debe superar Workspace.Gravity (196.2)
	Estela: ConfigEstela,
	Atuendo: AtuendoConfig,
}

-- Golpe del combo cuerpo a cuerpo (Config/Combate)
export type GolpeConfig = {
	Id: string,
	Nombre: string,
	Dano: number,
	Alcance: number, -- studs desde la heroína hasta la superficie del monstruo
	Recuperacion: number, -- segundos hasta el siguiente golpe
	Empuje: number, -- velocidad de empuje (studs/s); 0 = no empuja
	Sonido: string, -- clave de Config/Sonidos
	Animacion: string, -- clave de la animación procedural del cliente
}

-- Ranura de habilidad: Primario = Clic / E, Secundario = Q
export type Ranura = "Primario" | "Secundario"

-- Comportamiento del poder (lo implementan CombateService y EfectosController)
export type TipoPoder = "Rayo" | "Onda" | "Rafaga" | "Impulso" | "Escudo" | "Pulso" | "Laser" | "Dulce" | "Martillo" | "Estrellas"

-- Configuración plana de un poder: los campos que un tipo no usa valen 0.
export type PoderConfig = {
	Id: string,
	Nombre: string,
	Icono: string,
	Tipo: TipoPoder,
	Color: Color3,
	Enfriamiento: number, -- segundos
	Dano: number, -- daño por impacto
	Alcance: number, -- studs (rayo/proyectil) o distancia del impulso
	Radio: number, -- studs: grosor del impacto o radio de área
	Duracion: number, -- segundos del efecto (visual, escudo o ralentización)
	Cantidad: number, -- nº de proyectiles
	Dispersion: number, -- grados de dispersión de los proyectiles
	Empuje: number, -- velocidad de empuje (studs/s) aplicada a enemigos
	Ralentizacion: number, -- multiplicador de WalkSpeed (0.5 = mitad de velocidad)
	NivelRequerido: number, -- nivel de la jugadora a partir del cual se puede usar
	Carga: number, -- segundos de carga antes de disparar (láser); 0 = instantáneo
}

export type PoderesHeroina = {
	Primario: PoderConfig,
	Secundario: PoderConfig,
}

export type TipoTecho = "Cupula" | "Antena" | "Plano" | "Piramide"

export type EdificioConfig = {
	Id: string,
	Nombre: string,
	Posicion: Vector2, -- (X, Z) relativa al centro de la ciudad
	Tamano: Vector3,
	Color: Color3,
	ColorAcento: Color3, -- franjas neón
	Techo: TipoTecho,
	VidaMaxima: number,
}

-- Ataque especial de un monstruo (con aviso previo: círculo/franja roja en el suelo).
export type TipoAtaqueEspecial = "Gelatina" | "Embestida" | "GolpeSuelo"

export type AtaqueEspecialConfig = {
	Tipo: TipoAtaqueEspecial,
	Nombre: string,
	Enfriamiento: number, -- segundos entre ataques especiales
	Aviso: number, -- segundos entre el aviso rojo y el golpe (tiempo para esquivar)
	AlcanceMin: number, -- distancia horizontal (studs) desde el monstruo a la heroína para usarlo
	AlcanceMax: number,
	Dano: number, -- daño base (se escala con la oleada y el nº de jugadoras)
	Radio: number, -- radio del impacto (Gelatina/GolpeSuelo) o media anchura de la franja (Embestida)
	Ralentizacion: number, -- multiplicador de velocidad de la heroína (1 = no ralentiza)
	DuracionEfecto: number, -- segundos de ralentización
	Empuje: number, -- velocidad con la que sale despedida la heroína (studs/s)
}

export type MonstruoConfig = {
	Id: string,
	Nombre: string,
	Color: Color3,
	ColorOjos: Color3,
	Escala: number, -- 1 = ~14 studs de alto
	Vida: number,
	Dano: number, -- por golpe
	Velocidad: number, -- WalkSpeed
	RangoAtaque: number, -- studs (se suma al tamaño del monstruo)
	CadenciaAtaque: number, -- segundos entre golpes
	RadioPersecucion: number, -- distancia a la que prefiere perseguir heroínas antes que edificios
	Recompensa: number, -- monedas
	Experiencia: number,
	AparecenDesdeOleada: number,
	Peso: number, -- probabilidad relativa de aparecer
	Especial: AtaqueEspecialConfig,
}

export type TipoMejora = "Dano" | "Vuelo"

export type MejoraConfig = {
	Id: TipoMejora,
	Nombre: string,
	Icono: string,
	Descripcion: string,
	NivelMaximo: number,
	CostoBase: number, -- monedas para el nivel 1
	CostoPorNivel: number, -- coste extra por cada nivel ya comprado
	BonoPorNivel: number, -- 0.1 = +10% por nivel
}

export type SonidoConfig = {
	Id: string, -- rbxasset://... o rbxassetid://...
	Volumen: number,
	Tono: number, -- PlaybackSpeed
}

-- Ajuste de dificultad según cuántas heroínas hay en la ciudad (Config/Juego → Oleadas.AjusteJugadoras).
export type AjusteDificultad = {
	Cantidad: number,
	Vida: number,
	Dano: number,
}

return {}
