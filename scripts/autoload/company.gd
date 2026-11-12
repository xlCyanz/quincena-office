# La empresa en conjunto (diseño, 9 y 17.2). Hito 26: el valor de la empresa, un número
# siempre visible que funciona como puntuación: dinero + reventa de los muebles y las
# computadoras + terreno comprado (a lo que se pagó) − deuda con el banco (capital
# pendiente, cuotas atrasadas y recargos). Los productos se suman en la fase 5. Las
# etapas y los objetivos llegan en los hitos 27 y 28.
#
# No guarda estado propio: se calcula con Economy, OfficeState y Bank. Cuando algo de
# eso cambia avisa con EventBus.company_value_changed.
extends Node


func _ready() -> void:
	EventBus.balance_changed.connect(func(_balance: int) -> void: _notify())
	EventBus.bank_changed.connect(_notify)
	EventBus.office_changed.connect(_notify)


## Valor de la empresa.
func get_value() -> int:
	var total: int = 0
	for part: Dictionary in get_value_parts():
		total += int(part["amount"])
	return total


## Partes del valor, en orden: [{"label", "amount"}] (la deuda va en negativo).
func get_value_parts() -> Array[Dictionary]:
	return [
		{"label": "Dinero", "amount": Economy.balance},
		{"label": "Muebles y computadoras (reventa)", "amount": Bank.get_assets_value()},
		{"label": "Terreno comprado", "amount": OfficeState.land_paid},
		{"label": "Deuda con el banco", "amount": -Bank.get_seizable_debt()},
	]


func _notify() -> void:
	EventBus.company_value_changed.emit(get_value())
