# Constantes de diseño ya decididas (ver docs/diseno.md, secciones 3, 6.1 y 13.1).
# No es un autoload: se usa por su nombre de clase, por ejemplo GameConstants.TILE_SIZE.
class_name GameConstants
extends RefCounted

## Tamaño de una casilla isométrica en píxeles (1 casilla = 1 m²).
const TILE_SIZE := Vector2i(64, 32)

## Tamaño del solar en casillas (40×40 m): el mapa fijo que rodea al local y el tope
## de crecimiento al comprar terreno (diseño, 13.1).
const MAX_SITE_SIZE := Vector2i(40, 40)

## Tamaño del local inicial en casillas (6×8 m = 48 m²).
const STARTING_LOT_SIZE := Vector2i(6, 8)

## Dinero con el que empieza la partida.
const STARTING_CAPITAL: int = 20000

## Mantenimiento mensual del local, en dólares por m², cobrado el día 1 de cada mes.
const MAINTENANCE_PER_M2: int = 5

## Segundos reales que dura una hora de juego a velocidad 1x.
const SECONDS_PER_GAME_HOUR: float = 60.0

## Horas que tiene un día de juego (reloj de 24 horas).
const HOURS_PER_DAY: int = 24

## Días que tiene cada mes del juego.
const DAYS_PER_MONTH: int = 30

## Días que tiene una semana del juego (el día 1 de la partida es lunes).
const DAYS_PER_WEEK: int = 7

## Hora a la que empieza una partida nueva (el inicio de la jornada).
const START_HOUR: int = 8

## Velocidades del reloj, sin contar la pausa (1x, 2x y 4x).
const CLOCK_SPEEDS: Array[float] = [1.0, 2.0, 4.0]

## Días del mes en que se paga la nómina.
const PAYROLL_DAYS: Array[int] = [15, 30]

## Niveles fijos de zoom de la cámara, de lejos a cerca. Los menores que 1 sirven para
## ver todo el solar con sus alrededores; la rueda pasa de uno a otro con una animación.
const CAMERA_ZOOM_LEVELS: Array[float] = [0.25, 0.375, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0]

## Niveles de antes (hasta el hito 67): una partida vieja guarda solo el índice en esta lista.
const CAMERA_LEGACY_ZOOM_LEVELS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]

## Nivel de zoom de referencia (índice dentro de CAMERA_ZOOM_LEVELS, el 2.0). Al empezar, la
## cámara encuadra la oficina completa con el nivel más cercano en que cabe.
const CAMERA_START_ZOOM_INDEX: int = 7

## Cámara suave: qué tan rápido llega el zoom (y el encuadre) a su destino (1/s; con 12
## recorre el 95 % en un cuarto de segundo).
const CAMERA_SMOOTH_SPEED: float = 12.0

## Inercia al soltar un arrastre: frenado (1/s), velocidad mínima para seguir (píxeles de
## pantalla por segundo), tope y cuánto puede pasar entre el último movimiento y soltar.
const CAMERA_INERTIA_FRICTION: float = 5.0
const CAMERA_INERTIA_MIN_SPEED: float = 40.0
const CAMERA_INERTIA_MAX_SPEED: float = 3000.0
const CAMERA_INERTIA_RELEASE_MS: int = 80

## Movimiento con el teclado (WASD o flechas) y con el ratón en el borde de la ventana,
## en píxeles de pantalla por segundo, y ancho del borde que mueve la cámara.
const CAMERA_KEY_PAN_SPEED: float = 900.0
const CAMERA_EDGE_PAN_SPEED: float = 700.0
const CAMERA_EDGE_PAN_PX: float = 12.0

## Margen alrededor de la oficina al encuadrarla, como fracción de la pantalla (deja
## sitio a los paneles de arriba y abajo).
const CAMERA_FIT_MARGIN: float = 0.2


## Velocidad al caminar de los personajes, en casillas por segundo real a 1x
## (se multiplica por la velocidad del reloj; en pausa nadie se mueve).
const CHARACTER_WALK_SPEED: float = 1.0
## Con prisa (llega tarde, el candidato al que llaman a la entrevista) camina este tanto más rápido.
const CHARACTER_HURRY_FACTOR: float = 2.0
## Una persona por casilla: quien encuentra ocupada la siguiente espera; tras
## CHARACTER_REPATH_WAIT segundos (a 1x) busca otro camino que esquive a los que están
## parados, y tras CHARACTER_PASS_WAIT pasa igual (para que dos de frente en un pasillo
## de una casilla no se queden trabados para siempre).
const CHARACTER_REPATH_WAIT: float = 0.6
const CHARACTER_PASS_WAIT: float = 4.0
