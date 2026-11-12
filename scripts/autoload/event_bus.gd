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

## Cambió la oficina (pisos, paredes, puertas o muebles). La emiten Builder después
## de cada compra o venta y Staff al asignar un puesto, para que se redibuje y se
## recalculen los caminos.
@warning_ignore("unused_signal")
signal office_changed

## Cambiaron las vacantes, sus candidatos o los empleados. La emite Staff.
@warning_ignore("unused_signal")
signal staff_changed

## Cambiaron las ofertas o los contratos. La emite Projects.
@warning_ignore("unused_signal")
signal projects_changed

## Cambiaron los productos propios (hito 41). La emite Products.
@warning_ignore("unused_signal")
signal products_changed

## Llegó, fue atendido o se fue un cliente que visita la Recepción (hito 36). La emite Projects.
@warning_ignore("unused_signal")
signal visits_changed

## Cambió la suciedad de alguna habitación (hito 37).
signal dirt_changed

## Un aviso para el jugador (por ejemplo, la nómina pagada). Lo muestra el Hud.
@warning_ignore("unused_signal")
signal notice(text: String)

## Cambió quién tiene que estar en la oficina fuera del cambio de hora (por ejemplo,
## el jugador mandó al CEO a casa). La emite Staff.
@warning_ignore("unused_signal")
signal presence_changed

## Se hizo (on_time = true) o no se pudo hacer a tiempo (false) un pago obligatorio:
## la nómina, el mantenimiento y, desde el hito 22, las cuotas. Lo escucha Bank para el
## historial de la calificación de crédito.
@warning_ignore("unused_signal")
signal payment_recorded(concept: String, on_time: bool)

## Cambió algo del banco (calificación, límite o, más adelante, préstamos). La emite Bank.
@warning_ignore("unused_signal")
signal bank_changed

## La partida terminó (embargo total). stats: {"days", "hired", "delivered",
## "best_reputation", "debt", "assets"}. La emite Bank; la escuchan SaveManager y la
## escena de juego.
@warning_ignore("unused_signal")
signal game_over(stats: Dictionary)

## La nómina de hoy no alcanza: shortfall es lo que falta. La emite Staff antes de
## castigar; quien ofrece cubrirla (Bank, con el préstamo de emergencia) pone
## response["held"] = true y Staff espera a emergency_loan_resolved.
@warning_ignore("unused_signal")
signal payroll_short(shortfall: int, response: Dictionary)

## El banco ofrece un préstamo de emergencia (Bank.emergency_offer). La escena de juego
## pausa el tiempo y abre la ventana.
@warning_ignore("unused_signal")
signal emergency_loan_offered(offer: Dictionary)

## El jugador aceptó o rechazó el préstamo de emergencia. La emite Bank.
@warning_ignore("unused_signal")
signal emergency_loan_resolved(accepted: bool)

## Pudo cambiar el valor de la empresa (dinero, muebles, terreno o deuda). La emite Company.
@warning_ignore("unused_signal")
signal company_value_changed(value: int)

## La empresa subió de etapa (hito 27): 0 = Emprendimiento … 4 = Corporación.
@warning_ignore("unused_signal")
signal stage_changed(stage: int)

## Se cumplió un objetivo guiado (hito 28), ya pagada su recompensa. La emite Company.
@warning_ignore("unused_signal")
signal objective_completed(objective_id: String)

## Cambió la lista de objetivos visibles (se cumplió uno o se cargó una partida).
@warning_ignore("unused_signal")
signal objectives_changed

## Se aceptó un contrato (hito 30: los vendedores lo cuentan para ascender). La emite Projects.
@warning_ignore("unused_signal")
signal contract_accepted

## Se entregó un contrato; worker_keys son los empleados que sumaron puntos en él
## (claves de Staff.employee_key). La emite Projects.
@warning_ignore("unused_signal")
signal contract_delivered(worker_keys: Array)


## Se abrió, se cerró o cambió la tarjeta de evento (hito 43). La emite Events.
@warning_ignore("unused_signal")
signal event_changed

## Llegó un evento: la escena de juego corta el salto de horas para que el jugador lo vea.
@warning_ignore("unused_signal")
signal event_started(card: Dictionary)
