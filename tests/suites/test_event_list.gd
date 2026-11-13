# Prueba del hito 44: lista de eventos.
# Criterio: con contador la inspección de impuestos no multa; con baterías no hay apagón;
# sin personal de limpieza aparece la oficina sucia. Además: el archivero baja la multa, un
# buen líder evita la reunión inútil y cada efecto nuevo hace lo que dice.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=event_list
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const SEED: int = 20261144
const DESIGN_EVENTS: Array[String] = ["friday_deploy", "birthday", "ac_war", "coffee", "useless_meeting", "scope_change",
	"late_payment", "referral", "blackout", "server_down", "broken_computer", "tax", "competitor", "award",
	"broken_bathroom", "dirty_office"]
## Área abierta del local de 6×8 (fuera de la Oficina Ejecutiva).
const OPEN_CELL := Vector2i(3, 3)
const DESK_CELL := Vector2i(4, 4)
const CHAIR_CELL := Vector2i(4, 5)
## Habitación de 2 casillas en la esquina noreste: (5, 0) y (5, 1).
const CORNER_CELL := Vector2i(5, 1)
const CORNER_TOP := Vector2i(5, 0)
const FAKE_TEAM: int = 77

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_rooms()
	_check_tax()
	_check_blackout()
	_check_dirty_office()
	_check_meeting()
	_check_lose_work()
	_check_scope_change()
	_check_late_payment()
	_check_products()
	_check_computer()
	_check_save()
	GameClock.stop()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game(stage: int = 0) -> void:
	GameClock.stop()
	GameClock.set_paused(false)
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Products.set_seed(SEED)
	Events.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = stage
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()


# Empleado de mentira (sin puesto ni sueldo salvo que se pida): basta para las condiciones.
func _add_employee(employee_id: int, role: String, salary: int = 0, leadership: float = 0.0) -> Dictionary:
	var employee: Dictionary = {"id": employee_id, "name": "Persona %d" % employee_id, "role": role, "level": "junior",
		"salary": salary, "schedule": StaffCatalog.get_role_schedule("programmer"), "energy": 80, "mood": 60, "stress": 20,
		"paid_until": 0, "owed": 0, "skills": {"leadership": leadership}}
	Staff.employees.append(employee)
	return employee


func _option_labels() -> Array[String]:
	var labels: Array[String] = []
	for option: Dictionary in Events.card.get("options", []):
		labels.append(String(option["label"]))
	return labels


func _option_money(index: int) -> int:
	var total: int = 0
	for effect: Dictionary in Events.card["options"][index]["effects"]:
		if effect["type"] == "money":
			total += int(effect["amount"])
	return total


# Contrato pequeño aceptado (sin equipos lo lleva el CEO) con trabajo hecho.
func _ceo_contract() -> Dictionary:
	var offer: Dictionary = Projects.create_offer("small")
	Projects.accept(int(offer["id"]))
	var contract: Dictionary = Projects.contracts[-1]
	contract["progress"]["design"] = float(contract["points"]["design"])
	contract["progress"]["programming"] = 30.0
	return contract


func _check_catalog() -> void:
	_new_game()
	var ids: Array[String] = []
	for event: Dictionary in Events._events_data()["events"]:
		ids.append(String(event["id"]))
	for event_id: String in DESIGN_EVENTS:
		_expect(ids.has(event_id), "está el evento %s" % event_id)
	# El inversionista (hito 58) es el único evento que no está en 10.2.
	_expect(ids.size() == DESIGN_EVENTS.size() + 1 and ids.has("investor"), "los 16 eventos de 10.2 y el inversionista: %d" % ids.size())
	var good: float = 0.0
	var bad: float = 0.0
	for event: Dictionary in Events._events_data()["events"]:
		if event["kind"] == "good":
			good += float(event["weight"])
		else:
			bad += float(event["weight"])
	_expect(good >= 5.0, "los buenos pesan más para no quedar perdidos entre los malos: %.1f contra %.1f" % [good, bad])
	for item: String in ["toilet", "sink", "coffee_maker", "backup_battery", "filing_cabinet"]:
		_expect(FurnitureCatalog.get_price(item) > 0, "mueble nuevo con precio: %s" % item)
	_expect(FurnitureCatalog.get_price("backup_battery") == 1500 and FurnitureCatalog.get_price("filing_cabinet") == 250,
		"baterías $1,500 y archivero $250")


# El Baño funciona con inodoro y lavamanos; la Sala de descanso con cafetera, y esta baja
# la probabilidad de quedarse sin café.
func _check_rooms() -> void:
	_new_game()
	_add_employee(901, "programmer")
	_expect(not Events.get_eligible_ids().has("broken_bathroom"), "sin baño no se daña el baño")
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	var result: Dictionary = _builder.apply([
		{"edge": Vector3i(4, 0, x), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 1, x), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 1, y), "kind": ConstructionCatalog.WALL},
	] as Array[Dictionary])
	_expect(result["ok"], "paredes del baño: %s" % result.get("message", ""))
	result = _builder.mark_room("bathroom", CORNER_CELL)
	_expect(result["ok"], "marcar el Baño: %s" % result.get("message", ""))
	_expect(not Projects.has_working_room("bathroom"), "baño sin muebles no funciona")
	_expect(_builder.place("toilet", CORNER_TOP, 2)["ok"] and _builder.place("sink", CORNER_CELL, 3)["ok"], "inodoro y lavamanos")
	_expect(Projects.has_working_room("bathroom"), "con inodoro y lavamanos el Baño funciona")
	_expect(Events.get_eligible_ids().has("broken_bathroom"), "con baño puede dañarse")
	var balance: int = Economy.balance
	Events.trigger("broken_bathroom")
	Events.choose(0)
	_expect(Economy.balance == balance - 400, "el plomero cuesta $400")
	_expect(is_equal_approx(Events.get_weight("coffee"), 1.0), "sin Sala de descanso el café pesa 1")
	result = _builder.mark_room("break_room", OPEN_CELL)
	_expect(result["ok"], "marcar la Sala de descanso: %s" % result.get("message", ""))
	_expect(_builder.place("coffee_maker", DESK_CELL, 2)["ok"] and Projects.has_working_room("break_room"),
		"con cafetera la Sala de descanso funciona")
	_expect(is_equal_approx(Events.get_weight("coffee"), 0.3), "con cafetera el café se acaba menos: %.2f" % Events.get_weight("coffee"))


func _check_tax() -> void:
	_new_game()
	_expect(Events.get_eligible_ids().has("tax"), "la inspección puede llegar")
	_expect(is_equal_approx(Events.get_weight("tax"), 1.0), "sin contador pesa el doble")
	Events.trigger("tax")
	_expect(_option_labels() == (["Pagar la multa"] as Array[String]) and _option_money(0) == -500,
		"sin ingresos, la multa mínima de $500: %s %d" % [_option_labels(), _option_money(0)])
	var balance: int = Economy.balance
	Events.choose(0)
	_expect(Economy.balance == balance - 500, "paga la multa")
	# 10 % de los ingresos de contratos del mes pasado.
	Economy.earn(20000, Projects.CONCEPT_DELIVERY)
	GameClock.fast_forward_hours(GameConstants.DAYS_PER_MONTH * GameConstants.HOURS_PER_DAY)
	Events.trigger("tax")
	_expect(_option_money(0) == -2000, "multa del 10 %% de $20,000: %d" % _option_money(0))
	Events.choose(0)
	_expect(_builder.place("filing_cabinet", Vector2i(4, 6), 0)["ok"], "comprar un archivero")
	Events.trigger("tax")
	_expect(_option_money(0) == -1000, "con archivero, la mitad: %d" % _option_money(0))
	Events.choose(0)
	# Con contador no hay multa.
	_add_employee(901, "accountant")
	_expect(is_equal_approx(Events.get_weight("tax"), 0.5), "con contador pesa la mitad")
	Events.trigger("tax")
	_expect(_option_labels() == (["El contador lo tiene todo en orden"] as Array[String]) and _option_money(0) == 0,
		"con contador no hay multa: %s" % [_option_labels()])
	balance = Economy.balance
	Events.choose(0)
	_expect(Economy.balance == balance, "no cobra nada")


func _check_blackout() -> void:
	_new_game()
	_expect(Events.get_eligible_ids().has("blackout"), "sin baterías puede haber apagón")
	_expect(_builder.place("backup_battery", Vector2i(4, 6), 0)["ok"], "comprar baterías de respaldo")
	_expect(not Events.get_eligible_ids().has("blackout") and not Events.trigger("blackout"), "con baterías no hay apagón")
	_builder.sell_furniture_at(Vector2i(4, 6))
	_expect(not OfficeState.has_furniture("backup_battery") and Events.get_eligible_ids().has("blackout"), "al venderlas vuelve")
	var contract: Dictionary = _ceo_contract()
	var before: float = _progress(contract)
	var expected: float = minf(before, Projects.get_nominal_rate(contract) * 8)
	Events.trigger("blackout")
	Events.choose(0)
	_expect(is_equal_approx(before - _progress(contract), expected),
		"se pierde el trabajo del día: %.1f de %.1f" % [before - _progress(contract), expected])


func _check_dirty_office() -> void:
	_new_game()
	_expect(not Events.get_eligible_ids().has("dirty_office"), "sin empleados no hay oficina sucia")
	_add_employee(901, "programmer")
	_expect(Events.get_eligible_ids().has("dirty_office"), "sin personal de limpieza aparece la oficina sucia")
	OfficeState.rooms[0]["dirt"] = 70.0
	var balance: int = Economy.balance
	Events.trigger("dirty_office")
	Events.choose(0)
	_expect(Economy.balance == balance - 300 and is_zero_approx(OfficeState.get_room_dirt(OfficeState.rooms[0])),
		"limpieza por un día: −$300 y todo limpio")
	Events.trigger("dirty_office")
	Events.choose(1)
	_expect(int(Staff.employees[0]["mood"]) == 52, "aguantar: ánimo −8")
	_add_employee(902, "cleaner")
	_expect(not Events.get_eligible_ids().has("dirty_office"), "con personal de limpieza no ocurre")


func _check_meeting() -> void:
	_new_game()
	_add_employee(901, "programmer")
	_expect(not Events.get_eligible_ids().has("useless_meeting"), "sin equipos no hay reunión")
	var team: Dictionary = {"id": FAKE_TEAM, "name": "Equipo Prueba", "members": [901], "leader_id": 0}
	Staff.teams.append(team)
	_expect(Events.get_eligible_ids().has("useless_meeting"), "un equipo sin líder pierde horas en reuniones")
	_add_employee(902, "team_leader", 0, 40.0)
	team["leader_id"] = 902
	_expect(Events.get_eligible_ids().has("useless_meeting"), "con un líder de liderazgo 40 también")
	Staff.get_employee(902)["skills"]["leadership"] = 60.0
	_expect(not Events.get_eligible_ids().has("useless_meeting"), "con un buen líder (≥60) no ocurre")
	Staff.get_employee(902)["skills"]["leadership"] = 59.0
	var contract: Dictionary = _ceo_contract()
	contract["team_id"] = FAKE_TEAM
	var before: float = _progress(contract)
	Events.trigger("useless_meeting")
	_expect(String(Events.card["text"]).begins_with("Equipo Prueba"), "nombra al equipo: %s" % Events.card["text"])
	Events.choose(0)
	_expect(is_equal_approx(before - _progress(contract), minf(before, Projects.get_nominal_rate(contract) * 2)),
		"el equipo pierde 2 horas")
	Staff.teams.erase(team)


func _check_lose_work() -> void:
	_new_game()
	_add_employee(901, "programmer")
	_add_employee(902, "designer")
	var contract: Dictionary = _ceo_contract()
	var design: float = float(contract["progress"]["design"])
	Events.trigger("ac_war")
	_expect(String(Events.card["text"]).contains("Persona 90"), "nombra a los dos: %s" % Events.card["text"])
	var rate: float = Projects.get_nominal_rate(contract)
	_expect(rate > 0.0, "el CEO tiene velocidad")
	Events.choose(0)
	_expect(is_equal_approx(float(contract["progress"]["programming"]), maxf(0.0, 30.0 - rate * 2))
		and is_equal_approx(float(contract["progress"]["design"]), design - maxf(0.0, rate * 2 - 30.0)),
		"mediar: el CEO pierde 2 horas, de la última fase hacia atrás: %s" % [contract["progress"]])
	Events.trigger("ac_war")
	Events.choose(1)
	_expect(int(Staff.employees[0]["mood"]) == 50 and int(Staff.employees[1]["mood"]) == 50, "dejarlo pasar: ánimo −10 a los dos")
	_add_employee(903, "programmer")
	Events.trigger("ac_war")
	Events.choose(1)
	var low: int = Staff.employees.filter(func(employee: Dictionary) -> bool: return int(employee["mood"]) < 60).size()
	var untouched: int = Staff.employees.filter(func(employee: Dictionary) -> bool: return int(employee["mood"]) == 60).size()
	_expect(untouched <= 1 and low >= 2, "solo a dos de tres")
	_expect(Events.describe_effects([{"type": "mood_some", "amount": -10, "count": 2}]) == "ánimo −10 a 2 personas", "describe mood_some")


func _check_scope_change() -> void:
	_new_game()
	_expect(not Events.get_eligible_ids().has("scope_change"), "sin contratos no cambian requisitos")
	var contract: Dictionary = _ceo_contract()
	var points: int = int(contract["total_points"])
	var pay: int = int(contract["pay"])
	var days: int = int(contract["days"])
	var deadline: int = int(contract["deadline_day"])
	Events.trigger("scope_change")
	_expect(String(Events.card["text"]).begins_with(String(contract["client"])), "nombra al cliente")
	_expect(Events.describe_effects(Events.card["options"][1]["effects"]) == "+20 % de trabajo, +15 % de pago, +3 días",
		"describe negociar: %s" % Events.describe_effects(Events.card["options"][1]["effects"]))
	_expect(_option_labels() == (["Aceptar", "Negociar", "Negarse"] as Array[String]), "tres opciones: %s" % [_option_labels()])
	Events.choose(1)
	var step: int = int(ContractCatalog.get_offers("pay_step"))
	_expect(absi(int(contract["total_points"]) - roundi(points * 1.2)) <= 3, "negociar: +20 %% de trabajo: %d → %d" % [points, contract["total_points"]])
	_expect(int(contract["pay"]) == roundi(pay * 1.15 / step) * step and int(contract["days"]) == days + 3
		and int(contract["deadline_day"]) == deadline + 3, "negociar: +15 % de pago y 3 días más")
	pay = int(contract["pay"])
	Events.trigger("scope_change")
	Events.choose(0)
	_expect(int(contract["pay"]) == pay, "aceptar: el mismo pago")
	var reputation: float = Projects.reputation
	Projects.add_reputation(1.0)
	reputation = Projects.reputation
	Events.trigger("scope_change")
	Events.choose(2)
	_expect(is_equal_approx(Projects.reputation, reputation - 0.2), "negarse: reputación −0.2")
	for phase: String in ContractCatalog.PHASES:
		contract["progress"][phase] = float(contract["points"][phase])
	_expect(not Events.get_eligible_ids().has("scope_change"), "un contrato terminado ya no cambia")


func _check_late_payment() -> void:
	_new_game()
	_expect(not Events.get_eligible_ids().has("late_payment"), "sin entregas no hay pago atrasado")
	var contract: Dictionary = _ceo_contract()
	for phase: String in ContractCatalog.PHASES:
		contract["progress"][phase] = float(contract["points"][phase])
	Projects.deliver(int(contract["id"]))
	var paid: int = int(Projects.history[-1]["paid"])
	_expect(paid > 0 and Events.get_eligible_ids().has("late_payment"), "tras una entrega puede atrasarse el pago")
	Events.trigger("late_payment")
	var amount: int = roundi(paid * 0.3)
	_expect(String(Events.card["text"]).contains(MoneyFormat.format(amount)), "retiene el 30 %%: %s" % Events.card["text"])
	_expect(_option_labels() == (["Esperar"] as Array[String]), "sin contador solo esperar")
	_expect(Events.describe_effects(Events.card["options"][0]["effects"]) == "te devuelven %s en 15 días" % MoneyFormat.format(amount),
		"describe: %s" % Events.describe_effects(Events.card["options"][0]["effects"]))
	var balance: int = Economy.balance
	Events.choose(0)
	_expect(Economy.balance == balance - amount and Events.scheduled.size() == 1, "retiene el monto")
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Events.CONCEPT_WITHHELD, 0) == -amount, "concepto Pago retenido")
	GameClock.fast_forward_hours(14 * GameConstants.HOURS_PER_DAY)
	_expect(Events.scheduled.size() == 1, "a los 14 días aún no paga")
	balance = Economy.balance
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(Events.scheduled.is_empty() and Economy.month_totals.values().any(func(totals: Dictionary) -> bool:
		return int(totals.get(Events.CONCEPT_LATE_PAYMENT, 0)) == amount), "a los 15 días paga lo retenido")
	# Con contador cobra en 3 días; la entrega ya no es de los últimos 7 días.
	_expect(not Events.get_eligible_ids().has("late_payment"), "una entrega vieja ya no se atrasa")
	contract = _ceo_contract()
	for phase: String in ContractCatalog.PHASES:
		contract["progress"][phase] = float(contract["points"][phase])
	Projects.deliver(int(contract["id"]))
	_add_employee(901, "accountant")
	Events.trigger("late_payment")
	_expect(_option_labels() == (["Esperar", "Mandar al contador a cobrar"] as Array[String]), "con contador: %s" % [_option_labels()])
	Events.choose(1)
	_expect(int(Events.scheduled[0]["day"]) == GameClock.get_day_count() + 3, "el contador cobra en 3 días")
	Staff.employees.clear()
	GameClock.fast_forward_hours(3 * GameConstants.HOURS_PER_DAY)
	_expect(Events.scheduled.is_empty(), "y paga")


# Sala de servidores con un rack y un producto pequeño lanzado.
func _launched_product() -> Dictionary:
	var walls: Array[Dictionary] = []
	for x: int in [3, 5]:
		walls.append({"edge": Vector3i(x, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL})
	walls.append({"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.DOOR})
	_builder.apply(walls)
	_builder.mark_room(OfficeState.SERVER_ROOM, Vector2i(4, 1))
	_builder.place("air_conditioner", Vector2i(3, 0), 2)
	_builder.place("server_rack", Vector2i(5, 0), 0)
	var product: Dictionary = Products.get_product(Products.start("mobile_app", "small")["id"])
	for phase: String in ContractCatalog.PHASES:
		product["progress"][phase] = float(product["points"][phase])
	product["design_done"] = float(product["points"]["design"])
	product["design_skill"] = float(product["points"]["design"]) * 0.5
	var result: Dictionary = Products.launch(int(product["id"]))
	_expect(result["ok"], "lanzar el producto: %s" % result["message"])
	return product


func _check_products() -> void:
	_new_game(2)
	_add_employee(901, "programmer", 3000)
	_expect(not Events.get_eligible_ids().has("competitor") and not Events.get_eligible_ids().has("server_down"),
		"sin productos lanzados no hay competidor ni caída")
	var product: Dictionary = _launched_product()
	var eligible: Array[String] = Events.get_eligible_ids()
	_expect(eligible.has("competitor") and eligible.has("server_down") and eligible.has("friday_deploy"), "con un producto: %s" % [eligible])
	Events.trigger("competitor")
	_expect(String(Events.card["text"]).contains(String(product["name"])), "nombra al producto")
	Events.choose(0)
	_expect(is_equal_approx(float(product["bug_loss"]), 0.25), "el competidor quita 25 %% de los usuarios: %.2f" % product["bug_loss"])
	Events.trigger("server_down")
	_expect(String(Events.card["text"]).contains("el CEO"), "sin equipos lo levanta el CEO: %s" % Events.card["text"])
	Events.choose(1)
	_expect(is_equal_approx(float(product["bug_loss"]), 0.35), "esperar al proveedor: −10 %%: %.2f" % product["bug_loss"])
	_expect(is_equal_approx(Events.get_weight("friday_deploy"), 1.0), "descansados pesa 1")
	Staff.employees[0]["energy"] = 30
	_expect(is_equal_approx(Events.get_weight("friday_deploy"), 2.0), "cansados, el doble")
	Events.trigger("friday_deploy")
	# Horas extra del programador: 3,000 / 30 / 8 × 1.5 × 3 h = 56.25.
	_expect(_option_money(0) == -56, "las horas extra cuestan lo de 3 horas a 1.5×: %d" % _option_money(0))
	var balance: int = Economy.balance
	Events.choose(0)
	_expect(Economy.balance == balance - 56 and int(Staff.employees[0]["stress"]) == 25, "todos se quedan: pagan y se estresan")
	Events.trigger("friday_deploy")
	Events.choose(1)
	_expect(is_equal_approx(float(product["bug_loss"]), 0.5), "se arregla el lunes: −15 %%: %.2f" % product["bug_loss"])
	for index: int in range(4):
		Events.trigger("competitor")
		Events.choose(0)
	_expect(is_equal_approx(float(product["bug_loss"]), ProductCatalog.get_production_bugs("max_loss")), "la pérdida tiene tope")
	_expect(not Events.get_eligible_ids().has("friday_deploy") or Staff.employees.any(func(employee: Dictionary) -> bool:
		return employee["role"] == "programmer"), "el despliegue pide un programador")
	Staff.employees.clear()
	_expect(not Events.get_eligible_ids().has("friday_deploy"), "sin programador no hay despliegue de viernes")


func _check_computer() -> void:
	_new_game()
	_expect(not Events.get_eligible_ids().has("broken_computer"), "sin empleados con computadora no se daña ninguna")
	_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)
	_builder.place("simple_desk", DESK_CELL, 2)
	_builder.install_computer("basic_computer", DESK_CELL)
	_builder.place("basic_chair", CHAIR_CELL, 0)
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratar un programador con puesto")
	Events.trigger("broken_computer")
	_expect(String(Events.card["text"]).contains(String(employee["name"])), "nombra a quien la usa")
	_expect(_option_money(0) == -100 and _option_money(1) == -FurnitureCatalog.get_price("basic_computer"),
		"reparar $100 o comprar otra al precio de la computadora: %d / %d" % [_option_money(0), _option_money(1)])
	var balance: int = Economy.balance
	Events.choose(1)
	_expect(Economy.balance == balance - FurnitureCatalog.get_price("basic_computer"), "comprar otra cobra su precio")


func _check_save() -> void:
	_new_game()
	var contract: Dictionary = _ceo_contract()
	for phase: String in ContractCatalog.PHASES:
		contract["progress"][phase] = float(contract["points"][phase])
	Projects.deliver(int(contract["id"]))
	Events.trigger("late_payment")
	Events.choose(0)
	var due: Dictionary = Events.scheduled[0].duplicate()
	contract = _ceo_contract()
	Events.trigger("scope_change")
	var text: String = Events.card["text"]
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Events.scheduled.is_empty(), "partida nueva sin pagos pendientes")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(Events.scheduled.size() == 1 and int(Events.scheduled[0]["day"]) == int(due["day"])
		and int(Events.scheduled[0]["amount"]) == int(due["amount"]), "el pago retenido se guarda: %s" % [Events.scheduled])
	_expect(Events.card.get("event_id", "") == "scope_change" and Events.card["text"] == text
		and Events.card["target"]["contract_id"] is int, "la tarjeta guarda su objetivo: %s" % [Events.card.get("target", {})])
	var loaded: Dictionary = Projects.contracts[-1]
	var points: int = int(loaded["total_points"])
	Events.choose(0)
	_expect(int(loaded["total_points"]) > points, "tras cargar el efecto cae sobre el mismo contrato")
	Events.import_state({"card": {}})
	_expect(Events.scheduled.is_empty(), "partida de antes del hito 44: sin pagos pendientes")


func _progress(project: Dictionary) -> float:
	var total: float = 0.0
	for phase: String in ContractCatalog.PHASES:
		total += float(project["progress"][phase])
	return total
