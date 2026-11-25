# Constantes de diseño ya decididas (docs/diseno.md). No es un autoload: GameConstants.TILE_SIZE.
class_name GameConstants
extends RefCounted

## Tamaño de una casilla isométrica en píxeles (1 casilla = 1 m²).
const TILE_SIZE := Vector2i(64, 32)

## Tamaño del solar en casillas: el mapa fijo alrededor del local y el tope del terreno.
const MAX_SITE_SIZE := Vector2i(40, 40)

## Tamaño del local inicial en casillas (6×8 m = 48 m²).
const STARTING_LOT_SIZE := Vector2i(6, 8)

## Dinero con el que empieza la partida.
const STARTING_CAPITAL: int = 20000

## Mantenimiento mensual del local en dólares por m², cobrado el día 1.
const MAINTENANCE_PER_M2: int = 5

## Segundos reales que dura una hora de juego a velocidad 1x.
const SECONDS_PER_GAME_HOUR: float = 60.0

## Horas de un día de juego.
const HOURS_PER_DAY: int = 24

## Días de cada mes del juego.
const DAYS_PER_MONTH: int = 30

## Días de una semana (el día 1 de la partida es lunes).
const DAYS_PER_WEEK: int = 7

## Hora a la que empieza una partida nueva.
const START_HOUR: int = 8

## Horas en que la pantalla de presentaciones está prendida: desde x hasta antes de y.
const PRESENTATION_SCREEN_HOURS := Vector2i(8, 18)

## Segundos reales por cuadro de la animación de la pantalla prendida.
const PRESENTATION_SCREEN_FRAME_SECONDS: float = 0.25

## Distancia en casillas desde el medio de una puerta a la que se abre al acercarse alguien.
const DOOR_OPEN_REACH: float = 0.9

## Velocidades del reloj, sin la pausa.
const CLOCK_SPEEDS: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0]

## Días del mes en que se paga la nómina.
const PAYROLL_DAYS: Array[int] = [15, 30]

## Niveles fijos de zoom, de lejos a cerca (menos de 1 para ver el solar entero).
const CAMERA_ZOOM_LEVELS: Array[float] = [0.25, 0.375, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0]

## Niveles viejos: una partida vieja guarda solo el índice en esta lista.
const CAMERA_LEGACY_ZOOM_LEVELS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]

## Nivel de zoom de referencia (el 2.0); al empezar se encuadra con el más cercano en que cabe la oficina.
const CAMERA_START_ZOOM_INDEX: int = 7

## Cámara suave: velocidad hacia el destino (1/s; con 12 recorre el 95 % en un cuarto de segundo).
const CAMERA_SMOOTH_SPEED: float = 12.0

## Inercia al soltar un arrastre: frenado (1/s), velocidad mínima y tope (px de pantalla/s) y
## tiempo máximo entre el último movimiento y soltar.
const CAMERA_INERTIA_FRICTION: float = 5.0
const CAMERA_INERTIA_MIN_SPEED: float = 40.0
const CAMERA_INERTIA_MAX_SPEED: float = 3000.0
const CAMERA_INERTIA_RELEASE_MS: int = 80

## Movimiento con teclado o con el ratón en el borde, en px de pantalla/s, y ancho de ese borde.
const CAMERA_KEY_PAN_SPEED: float = 900.0
const CAMERA_EDGE_PAN_SPEED: float = 700.0
const CAMERA_EDGE_PAN_PX: float = 12.0

## Margen al encuadrar la oficina, como fracción de la pantalla (sitio para los paneles).
const CAMERA_FIT_MARGIN: float = 0.2


## Velocidad al caminar en casillas por segundo real a 1x (se multiplica por la del reloj).
const CHARACTER_WALK_SPEED: float = 1.0
## Con prisa (llega tarde o lo llaman a la entrevista) camina este tanto más rápido.
const CHARACTER_HURRY_FACTOR: float = 2.0
## Una persona por casilla: con la siguiente ocupada espera, tras CHARACTER_REPATH_WAIT s (a 1x) busca
## otro camino y tras CHARACTER_PASS_WAIT pasa igual (dos de frente en un pasillo de una casilla).
const CHARACTER_REPATH_WAIT: float = 0.6
const CHARACTER_PASS_WAIT: float = 4.0
