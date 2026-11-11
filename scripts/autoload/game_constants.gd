# Constantes de diseño ya decididas (ver docs/diseno.md, secciones 3, 6.1 y 13.1).
# No es un autoload: se usa por su nombre de clase, por ejemplo GameConstants.TILE_SIZE.
class_name GameConstants
extends RefCounted

## Tamaño de una casilla isométrica en píxeles (1 casilla = 1 m²).
const TILE_SIZE := Vector2i(64, 32)

## Tamaño del local inicial en casillas (6×8 m = 48 m²).
const STARTING_LOT_SIZE := Vector2i(6, 8)

## Dinero con el que empieza la partida.
const STARTING_CAPITAL: int = 20000

## Segundos reales que dura una hora de juego a velocidad 1x.
const SECONDS_PER_GAME_HOUR: float = 5.0

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

## Niveles fijos de zoom de la cámara, de lejos a cerca. Son enteros para que el
## pixel art se vea nítido (cada píxel del arte ocupa 1, 2 o 3 píxeles de pantalla).
const CAMERA_ZOOM_LEVELS: Array[float] = [1.0, 2.0, 3.0]

## Nivel de zoom con el que arranca la cámara (índice dentro de CAMERA_ZOOM_LEVELS).
const CAMERA_START_ZOOM_INDEX: int = 1

## Cuánto puede pasarse la vista más allá del borde del local, como fracción del
## tamaño de la pantalla (0.25 = hasta un cuarto de pantalla de margen).
const CAMERA_OVERSCROLL_RATIO: float = 0.25
