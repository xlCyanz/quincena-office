# Bus de señales global: los sistemas se avisan entre sí emitiendo y escuchando
# señales aquí, sin referencias directas entre ellos.
# @warning_ignore("unused_signal") evita la advertencia de "señal sin usar": aquí
# solo se declaran, las emiten otros scripts.
extends Node

## Empieza una nueva hora de juego (0 a 23). La emite GameClock.
@warning_ignore("unused_signal")
signal hour_changed(hour: int)

## Empieza un nuevo día: day va de 1 a DAYS_PER_MONTH y month empieza en 1.
## La emite GameClock justo antes del hour_changed de las 0:00.
@warning_ignore("unused_signal")
signal day_changed(day: int, month: int)

## Cambió el saldo de la cuenta empresarial. La emite Economy.
@warning_ignore("unused_signal")
signal balance_changed(balance: int)

## Cambió la oficina (pisos, paredes, puertas o muebles). La emite Builder después
## de cada compra o venta, para que se redibuje y se recalculen los caminos.
@warning_ignore("unused_signal")
signal office_changed
