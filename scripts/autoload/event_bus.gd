# Bus de señales global: los sistemas se avisan por aquí sin referencias directas.
# @warning_ignore("unused_signal"): aquí solo se declaran; las emiten otros scripts.
extends Node

## Empieza una nueva hora de juego (0 a 23). La emite GameClock.
@warning_ignore("unused_signal")
signal hour_changed(hour: int)

## Empieza un nuevo día (day 1..DAYS_PER_MONTH, month desde 1); GameClock la emite antes del hour_changed de las 0:00.
@warning_ignore("unused_signal")
signal day_changed(day: int, month: int)

## Cambió el saldo de la cuenta empresarial. La emite Economy.
@warning_ignore("unused_signal")
signal balance_changed(balance: int)

## Cambió la oficina (pisos, paredes, puertas, muebles o puestos). La emiten Builder y Staff.
@warning_ignore("unused_signal")
signal office_changed

## Cambiaron las vacantes, sus candidatos o los empleados. La emite Staff.
@warning_ignore("unused_signal")
signal staff_changed

## Cambiaron las ofertas o los contratos. La emite Projects.
@warning_ignore("unused_signal")
signal projects_changed

## Cambiaron los productos propios. La emite Products.
@warning_ignore("unused_signal")
signal products_changed

## Llegó, fue atendido o se fue un cliente de la Recepción. La emite Projects.
@warning_ignore("unused_signal")
signal visits_changed

## Cambió la suciedad de alguna habitación.
signal dirt_changed

## Aviso para el jugador; lo muestra el Hud. Con destino al hacerle clic, usar send_notice.
@warning_ignore("unused_signal")
signal notice(text: String)

## Destino del aviso que se está emitiendo ({} o uno de target_*); solo vale durante notice.
var _notice_target: Dictionary = {}


## Manda un aviso que lleva a target al hacerle clic (target_employee, target_contract,
## target_product, target_room o target_menu).
func send_notice(target: Dictionary, text: String) -> void:
	_notice_target = target
	notice.emit(text)
	_notice_target = {}


## Destino del aviso que se está emitiendo ({} si no lleva a nada).
func get_notice_target() -> Dictionary:
	return _notice_target


func target_employee(employee_id: int) -> Dictionary:
	return {"type": "employee", "id": employee_id}


func target_contract(contract_id: int) -> Dictionary:
	return {"type": "contract", "id": contract_id}


func target_product(product_id: int) -> Dictionary:
	return {"type": "product", "id": product_id}


## Una habitación, por una de sus casillas.
func target_room(cell: Vector2i) -> Dictionary:
	return {"type": "room", "cell": cell}


## Un menú: "staff", "projects", "teams", "bank" o "company".
func target_menu(menu: String) -> Dictionary:
	return {"type": "menu", "menu": menu}

## Cambió quién debe estar en la oficina fuera del cambio de hora (p. ej., el CEO se fue a casa). La emite Staff.
@warning_ignore("unused_signal")
signal presence_changed

## Se hizo a tiempo (on_time) o no un pago obligatorio (nómina, mantenimiento, cuotas). Lo escucha Bank.
@warning_ignore("unused_signal")
signal payment_recorded(concept: String, on_time: bool)

## Cambió algo del banco (calificación, límite o préstamos). La emite Bank.
@warning_ignore("unused_signal")
signal bank_changed

## Fin de partida por embargo total. stats: {"days", "hired", "delivered", "best_reputation",
## "debt", "assets"}. La emite Bank.
@warning_ignore("unused_signal")
signal game_over(stats: Dictionary)

## La nómina de hoy no alcanza por shortfall. Quien ofrece cubrirla (Bank) pone response["held"] = true
## y Staff espera a emergency_loan_resolved.
@warning_ignore("unused_signal")
signal payroll_short(shortfall: int, response: Dictionary)

## El banco ofrece un préstamo de emergencia: la escena de juego pausa y abre la ventana.
@warning_ignore("unused_signal")
signal emergency_loan_offered(offer: Dictionary)

## El jugador aceptó o rechazó el préstamo de emergencia. La emite Bank.
@warning_ignore("unused_signal")
signal emergency_loan_resolved(accepted: bool)

## Pudo cambiar el valor de la empresa (dinero, muebles, terreno o deuda). La emite Company.
@warning_ignore("unused_signal")
signal company_value_changed(value: int)

## La empresa subió de etapa: 0 = Emprendimiento … 4 = Corporación.
@warning_ignore("unused_signal")
signal stage_changed(stage: int)

## Se cumplió un objetivo guiado, ya pagada su recompensa. La emite Company.
@warning_ignore("unused_signal")
signal objective_completed(objective_id: String)

## Cambió la lista de objetivos visibles (se cumplió uno o se cargó una partida).
@warning_ignore("unused_signal")
signal objectives_changed

## Se aceptó un contrato (los vendedores lo cuentan para ascender). La emite Projects.
@warning_ignore("unused_signal")
signal contract_accepted

## Se entregó un contrato; worker_keys (Staff.employee_key) son quienes sumaron puntos. La emite Projects.
@warning_ignore("unused_signal")
signal contract_delivered(worker_keys: Array)


## Se abrió, se cerró o cambió la tarjeta de evento. La emite Events.
@warning_ignore("unused_signal")
signal event_changed

## Llegó un evento: la escena de juego corta el salto de horas para que el jugador lo vea.
@warning_ignore("unused_signal")
signal event_started(card: Dictionary)

## Se habilitó un tipo de habitación fuera de las etapas (la Sala de reuniones) o se cargó una partida.
@warning_ignore("unused_signal")
signal rooms_unlocked

## La empresa salió a bolsa: la escena de juego muestra el cierre con estas estadísticas.
@warning_ignore("unused_signal")
signal went_public(stats: Dictionary)

## Cambió una opción del jugador (Settings).
@warning_ignore("unused_signal")
signal settings_changed(key: String)

## Acción de la interfaz que el tutorial puede pedir: "camera_moved", "build_opened",
## "speed_changed" o "bank_opened".
@warning_ignore("unused_signal")
signal ui_action(action: String)

## Cambió el estado del tutorial (activo, paso o terminado).
@warning_ignore("unused_signal")
signal tutorial_changed

## Se pidió la ayuda de un menú (botón «?»): clave de data/help.json.
@warning_ignore("unused_signal")
signal help_requested(topic: String)

## Cambió el espacio de la interfaz (pantalla, escala o alto de la barra): los paneles se reacomodan.
@warning_ignore("unused_signal")
signal ui_layout_changed

## Pide un efecto de sonido de data/audio.json (p. ej., "build" o "error"). Lo toca Audio.
@warning_ignore("unused_signal")
signal sound_requested(sound_id: String)

## Pide una pista de música de data/audio.json ("menu", "office" o "" para callar). La toca Audio.
@warning_ignore("unused_signal")
signal music_requested(track: String)
