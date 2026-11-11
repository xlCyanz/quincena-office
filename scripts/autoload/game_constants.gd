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

## Días que tiene cada mes del juego.
const DAYS_PER_MONTH: int = 30

## Días del mes en que se paga la nómina.
const PAYROLL_DAYS: Array[int] = [15, 30]
