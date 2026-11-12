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
const SECONDS_PER_GAME_HOUR: float = 10.0

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

## Niveles fijos de zoom de la cámara, de lejos a cerca. Desde 1 son enteros para que
## el pixel art se vea nítido; los menores que 1 sirven para ver todo el solar.
const CAMERA_ZOOM_LEVELS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]

## Nivel de zoom de referencia (índice dentro de CAMERA_ZOOM_LEVELS). Al empezar, la
## cámara encuadra la oficina completa con el nivel más cercano en que cabe.
const CAMERA_START_ZOOM_INDEX: int = 3

## Margen alrededor de la oficina al encuadrarla, como fracción de la pantalla (deja
## sitio a los paneles de arriba y abajo).
const CAMERA_FIT_MARGIN: float = 0.2


## Velocidad al caminar de los personajes, en casillas por segundo real a 1x
## (se multiplica por la velocidad del reloj; en pausa nadie se mueve).
const CHARACTER_WALK_SPEED: float = 2.0
