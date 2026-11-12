# Prueba del hito 38: competencia por empleados.
# Criterio: un Senior mal pagado recibe ofertas más seguido que uno bien pagado; con un
# aumento que iguala se queda; si no, se va en el plazo.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=competition
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261116
const DESK_XS: Array[int] = [3, 4, 5]
const DESK_Y: int = 4

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_chances()
	_check_frequency()
	_check_offer()
	_check_match()
	_check_leaves()
	_check_let_go()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Startup con dinero de sobra, objetivos cumplidos y un Área de trabajo
# con tres puestos.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 1
	Economy.earn(100000, "Prueba")
	var builder := Builder.new()
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(3, 3))["ok"], "marcar el Área de trabajo")
	for x: int in DESK_XS:
		builder.place("simple_desk", Vector2i(x, DESK_Y), 2)
		builder.install_computer("basic_computer", Vector2i(x, DESK_Y))
		builder.place("basic_chair", Vector2i(x, DESK_Y + 1), 0)


# Un Senior (u otro cargo y nivel) con el sueldo de su nivel por ratio y sin rasgos.
func _hire(role: String = "programmer", level: String = "senior", ratio: float = 1.0) -> Dictionary:
	var employee: Dictionary = Staff.hire_directly(role, level)
	_expect(not employee.is_empty(), "contratar %s %s" % [role, level])
	if employee.is_empty():
		return employee
	employee["salary"] = roundi(StaffCatalog.get_salary(role, level) * ratio)
	employee["traits"] = [] as Array[String]
	return employee


# Sortea días hasta que llegue una oferta (como mucho max_days).
func _wait_offer(employee: Dictionary, max_days: int = 20000) -> bool:
	for day: int in range(max_days):
		Staff._maybe_get_offer(employee, GameClock.get_day_count())
		if not (employee["outside_offer"] as Dictionary).is_empty():
			return true
	return false


func _check_chances() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	_expect(is_equal_approx(Staff.get_offer_chance(senior), 0.01), "Senior con su sueldo: 1 %% al día (%f)" % Staff.get_offer_chance(senior))
	senior["salary"] = StaffCatalog.get_salary("programmer", "senior") - 100
	_expect(is_equal_approx(Staff.get_offer_chance(senior), 0.03), "mal pagado: ×3")
	senior["salary"] = roundi(StaffCatalog.get_salary("programmer", "senior") * 1.1)
	_expect(is_equal_approx(Staff.get_offer_chance(senior), 0.003), "bien pagado (110 %%): ×0.3")
	senior["salary"] = StaffCatalog.get_salary("programmer", "senior")
	senior["traits"] = ["loyal"] as Array[String]
	_expect(is_equal_approx(Staff.get_offer_chance(senior), 0.0025), "leal: ×0.25")
	senior["traits"] = ["ambitious"] as Array[String]
	_expect(is_equal_approx(Staff.get_offer_chance(senior), 0.02), "ambicioso: ×2")
	var semi: Dictionary = _hire("designer", "semi_senior")
	_expect(is_equal_approx(Staff.get_offer_chance(semi), 0.005), "SemiSenior: 0.5 %%")
	var junior: Dictionary = _hire("qa", "junior")
	_expect(Staff.get_offer_chance(junior) == 0.0, "a un Junior no le llegan ofertas")
	var leader: Dictionary = {"role": StaffCatalog.get_leader_role(), "level": "senior",
		"salary": StaffCatalog.get_salary(StaffCatalog.get_leader_role(), "senior"), "traits": []}
	_expect(is_equal_approx(Staff.get_offer_chance(leader), 0.01), "un líder cuenta como Senior")
	var receptionist: Dictionary = {"role": "receptionist", "level": "senior", "salary": 700, "traits": []}
	_expect(Staff.get_offer_chance(receptionist) == 0.0, "a la recepción no le llegan ofertas")


func _check_frequency() -> void:
	_new_game()
	var underpaid: Dictionary = _hire("programmer", "senior", 0.85)
	var well_paid: Dictionary = _hire("programmer", "senior", 1.2)
	var counts: Array[int] = [0, 0]
	var people: Array[Dictionary] = [underpaid, well_paid]
	for day: int in range(3000):
		for index: int in range(people.size()):
			Staff._maybe_get_offer(people[index], day)
			if not (people[index]["outside_offer"] as Dictionary).is_empty():
				counts[index] += 1
				people[index]["outside_offer"] = {}
	_expect(counts[0] > counts[1] * 4 and counts[0] > 60, "el mal pagado recibe más ofertas: %d contra %d en 3000 días" % [counts[0], counts[1]])
	# Un mal pagado recibe más o menos una por mes.
	_expect(counts[0] >= 60 and counts[0] <= 130, "unas 90 en 3000 días: %d" % counts[0])


func _check_offer() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	var salary: int = senior["salary"]
	_notices.clear()
	_expect(_wait_offer(senior), "llega una oferta")
	var offer: Dictionary = senior["outside_offer"]
	var raise_amount: int = int(offer["salary"]) - salary
	_expect(raise_amount >= roundi(salary * 0.15) - 50 and raise_amount <= roundi(salary * 0.3) + 50 and raise_amount % 50 == 0,
		"ofrece +15 a +30 %%: %d sobre %d" % [raise_amount, salary])
	_expect(int(offer["until_day"]) == GameClock.get_day_count() + 5, "plazo de 5 días")
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("Otra empresa le ofrece a %s" % senior["name"])), "avisa: %s" % [_notices])


func _check_match() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	senior["mood"] = 50
	_wait_offer(senior)
	var offer_salary: int = senior["outside_offer"]["salary"]
	var result: Dictionary = Staff.give_raise(senior["id"], offer_salary - 50)
	_expect(result["ok"] and not (senior["outside_offer"] as Dictionary).is_empty() and result["message"].contains("con eso no se queda"),
		"un aumento menor no alcanza: %s" % result["message"])
	result = Staff.match_offer(senior["id"])
	_expect(result["ok"] and (senior["outside_offer"] as Dictionary).is_empty() and int(senior["salary"]) == offer_salary,
		"igualar la oferta lo retiene: %s" % result["message"])
	_expect(int(senior["mood"]) >= 75, "y le sube el ánimo: %d" % int(senior["mood"]))
	for day: int in range(7):
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(not Staff.get_employee(senior["id"]).is_empty(), "sigue en la empresa")
	_expect(not Staff.match_offer(senior["id"])["ok"], "sin oferta no hay nada que igualar")


func _check_leaves() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	var other: Dictionary = _hire("designer", "junior")
	_wait_offer(senior)
	var until_day: int = senior["outside_offer"]["until_day"]
	_notices.clear()
	while GameClock.get_day_count() < until_day - 1:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(not Staff.get_employee(senior["id"]).is_empty(), "el día antes del plazo sigue")
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(Staff.get_employee(senior["id"]).is_empty(), "al terminar el plazo se va")
	_expect(not Staff.get_employee(other["id"]).is_empty(), "los demás se quedan")
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("%s se fue a otra empresa" % senior["name"])), "avisa que se fue")
	var paid: int = -Economy.get_month_totals(GameClock.get_month()).get(Staff.CONCEPT_POACHED, 0)
	_expect(paid > 0, "cobra su liquidación: %d" % paid)
	_expect(OfficeState.find_furniture_assigned_to(Staff.employee_key(senior["id"])).is_empty(), "su silla queda libre")


func _check_let_go() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	_expect(not Staff.let_go(senior["id"])["ok"], "sin oferta no se lo deja ir")
	_wait_offer(senior)
	var result: Dictionary = Staff.let_go(senior["id"])
	_expect(result["ok"] and Staff.get_employee(senior["id"]).is_empty(), "dejarlo ir lo saca hoy: %s" % result["message"])


func _check_save() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	_wait_offer(senior)
	var offer: Dictionary = senior["outside_offer"].duplicate()
	var state: Dictionary = JSON.parse_string(JSON.stringify(Staff.export_state()))
	Staff.new_game()
	Staff.import_state(state)
	var loaded: Dictionary = Staff.get_employee(senior["id"])
	_expect(int(loaded["outside_offer"]["salary"]) == int(offer["salary"]) and int(loaded["outside_offer"]["until_day"]) == int(offer["until_day"]),
		"la oferta se guarda")
	for employee: Dictionary in state["employees"]:
		employee.erase("outside_offer")
	Staff.import_state(state)
	_expect((Staff.get_employee(senior["id"])["outside_offer"] as Dictionary).is_empty(), "una partida vieja carga sin ofertas")


func _check_ui() -> void:
	_new_game()
	var senior: Dictionary = _hire()
	var leaving: Dictionary = _hire("designer", "senior")
	_wait_offer(senior)
	_wait_offer(leaving)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(senior["id"])
	await get_tree().process_frame
	var offer_salary: int = senior["outside_offer"]["salary"]
	_expect(card.get_text().contains("Otra empresa le ofrece %s" % MoneyFormat.format(offer_salary)), "la ficha avisa: %s" % card.get_text())
	var match_button: Button = card.get_match_offer_button()
	_expect(match_button.is_visible_in_tree() and match_button.text == "Igualar (%s)" % MoneyFormat.format(offer_salary), "botón Igualar: %s" % match_button.text)
	match_button.pressed.emit()
	await get_tree().process_frame
	_expect(int(senior["salary"]) == offer_salary and not card.get_match_offer_button().is_visible_in_tree(), "Igualar lo retiene y el botón se va")
	card.open_employee(leaving["id"])
	await get_tree().process_frame
	card.get_let_go_button().pressed.emit()
	await get_tree().process_frame
	_expect(Staff.get_employee(leaving["id"]).is_empty() and not card.is_open(), "Dejar ir lo saca y cierra la ficha")
	game.queue_free()
	await get_tree().process_frame
