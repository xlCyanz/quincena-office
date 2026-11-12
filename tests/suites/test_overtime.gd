# Prueba del hito 34: horas extra, turno de noche y horario individual.
# Criterio: un turno de 2 horas extra cobra 2 × 1.5 horas por día trabajado en la
# nómina; un turno de 22 a 6 cobra el recargo; el horario individual cambia la hora de
# llegada de esa persona.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=overtime
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261112
const WEEKDAYS: Array[int] = [0, 1, 2, 3, 4]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_schedule()
	_check_rules()
	_check_own_schedule()
	_check_targets()
	_check_pay()
	_check_firing()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un área de trabajo de tres puestos, dinero de sobra y los objetivos
# cumplidos.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for cell_x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(cell_x, 0), 2)["ok"], "escritorio en %d" % cell_x)
		_expect(builder.place("basic_chair", Vector2i(cell_x, 1), 0)["ok"], "silla en %d" % cell_x)
		_expect(builder.install_computer("basic_computer", Vector2i(cell_x, 0))["ok"], "computadora en %d" % cell_x)


func _hire(role: String, level: String) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(opened["id"])["candidates"][0]
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s %s (%s)" % [role, level, result["message"]])
	return employee


# Avanza hasta las 0:00 del día siguiente.
func _to_midnight() -> void:
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _check_schedule() -> void:
	var shift: WorkSchedule = WorkSchedule.make_shift(8, WEEKDAYS, 2)
	_expect(shift.start_hour == 8 and shift.end_hour == 19 and shift.overtime == 2, "8 a 17 con 2 horas extra sale a las 19")
	_expect(shift.get_duration() == 11, "la jornada dura 11 horas con el almuerzo")
	_expect(not shift.is_overtime_hour(8) and shift.is_overtime_hour(9) and shift.is_overtime_hour(10), "las extra son las 2 últimas")
	_expect(shift.describe() == "lun–vie 8:00–19:00 (2 h extra)", "texto del turno: %s" % shift.describe())
	_expect(shift.get_lunch_hour() == 12, "el almuerzo sigue a la 4.ª hora")
	_expect(shift.get_night_hours() == 0, "de día no hay horas de noche")
	var night: WorkSchedule = WorkSchedule.make_shift(22, WEEKDAYS)
	_expect(night.end_hour == 7 and night.overtime == 0, "22 a 7 sin horas extra")
	_expect(night.get_night_hours() == 7, "de 22 a 6 son 7 horas de noche sin el almuerzo: %d" % night.get_night_hours())
	_expect(WorkSchedule.is_night_hour(22) and WorkSchedule.is_night_hour(5) and not WorkSchedule.is_night_hour(6)
		and not WorkSchedule.is_night_hour(21), "la noche va de las 22 a las 6")
	_expect(WorkSchedule.make_shift(18, WEEKDAYS, 1).get_night_hours() == 5, "18 a 4 con 1 extra: de 23 a 3 (a las 22 almuerza)")
	var loaded: WorkSchedule = WorkSchedule.from_dict(shift.to_dict())
	_expect(loaded.overtime == 2 and loaded.end_hour == 19, "el turno guarda sus horas extra")
	_expect(WorkSchedule.from_dict({"days": [0], "start_hour": 8, "end_hour": 17}).overtime == 0, "un turno viejo no tiene extra")


func _check_rules() -> void:
	_new_game()
	_expect(Staff.shift_problem(8, WEEKDAYS, 4).is_empty(), "hasta 4 horas extra")
	_expect(Staff.shift_problem(8, WEEKDAYS, 5).contains("de 0 a 4"), "5 horas extra no")
	_expect(not Staff.shift_problem(8, WEEKDAYS, -1).is_empty(), "horas extra negativas no")
	var team: Dictionary = Staff.create_team()
	var result: Dictionary = Staff.set_team_shift(team["id"], 8, WEEKDAYS, 3)
	_expect(result["ok"] and WorkSchedule.from_dict(team["schedule"]).overtime == 3, "un turno con 3 horas extra: %s" % result["message"])
	_expect(String(result["message"]).contains("(3 h extra)"), "el aviso dice las horas extra")
	_expect(not Staff.set_team_shift(team["id"], 8, WEEKDAYS, 5)["ok"], "un turno con 5 horas extra no")
	_expect(not Staff.set_team_shift(team["id"], 8, [0, 1, 2, 3, 4, 5, 6], 0)["ok"], "sin día de descanso no")


func _check_own_schedule() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	Staff.set_team_shift(team["id"], 8, WEEKDAYS, 1)
	var key: String = Staff.employee_key(worker["id"])
	_expect(Staff.is_expected(key, 0, 8) and not Staff.is_expected(key, 0, 22), "con el turno del equipo llega a las 8")
	_expect(not Staff.has_own_schedule(worker), "empieza sin horario propio")
	var result: Dictionary = Staff.set_own_schedule(worker["id"], 22, [1, 2, 3], 2)
	_expect(result["ok"] and Staff.has_own_schedule(worker), "horario propio: %s" % result["message"])
	_expect(not Staff.is_expected(key, 0, 8) and not Staff.is_expected(key, 1, 8), "con su horario ya no llega a las 8")
	_expect(Staff.is_expected(key, 1, 22) and not Staff.is_expected(key, 0, 22), "llega a las 22 los días que eligió")
	_expect(Staff.get_schedule(worker).overtime == 2, "su horario tiene sus horas extra")
	_expect(Staff.get_team_of(worker["id"]) == team, "sigue en su equipo")
	# Cambiar el turno del equipo no toca a quien tiene horario propio.
	Staff.set_team_shift(team["id"], 9, WEEKDAYS, 0)
	_expect(Staff.get_schedule(worker).start_hour == 22, "el turno del equipo no cambia su horario propio")
	_expect(not Staff.set_own_schedule(worker["id"], 8, [0, 1, 2, 3, 4, 5, 6])["ok"], "su horario también necesita descanso")
	_expect(not Staff.set_own_schedule(worker["id"], 8, WEEKDAYS, 5)["ok"], "y no más de 4 horas extra")
	result = Staff.clear_own_schedule(worker["id"])
	_expect(result["ok"] and String(result["message"]).contains("al turno de %s" % team["name"]), "vuelve al turno: %s" % result["message"])
	_expect(Staff.get_schedule(worker).start_hour == 9 and Staff.is_expected(key, 0, 9), "y llega con su equipo")
	# Sin equipo, el horario propio reemplaza el del cargo y quitarlo vuelve a él.
	Staff.remove_from_team(worker["id"])
	Staff.set_own_schedule(worker["id"], 6, WEEKDAYS)
	_expect(Staff.is_expected(key, 0, 6), "sin equipo también tiene horario propio")
	result = Staff.clear_own_schedule(worker["id"])
	_expect(String(result["message"]).contains("al horario de su cargo") and Staff.get_schedule(worker).start_hour == 8,
		"vuelve al horario de su cargo: %s" % result["message"])
	_expect(not Staff.set_own_schedule(9999, 8, WEEKDAYS)["ok"] and not Staff.clear_own_schedule(9999)["ok"], "un empleado que no está")


func _check_targets() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var stress: int = Staff.get_stress_target(worker)
	var mood: int = Staff.get_mood_target(worker)
	Staff.set_own_schedule(worker["id"], 8, WEEKDAYS, 2)
	_expect(Staff.get_stress_target(worker) == stress + 10, "2 horas extra suben la meta de estrés 10: %d → %d" % [stress, Staff.get_stress_target(worker)])
	_expect(Staff.get_mood_target(worker) == mood, "de día el ánimo no cambia")
	Staff.set_own_schedule(worker["id"], 22, WEEKDAYS)
	_expect(Staff.get_stress_target(worker) == stress, "sin horas extra el estrés vuelve")
	_expect(Staff.get_mood_target(worker) == mood - 10, "con horas de noche la meta de ánimo baja 10")
	Staff.set_own_schedule(worker["id"], 21, WEEKDAYS, 4)
	_expect(Staff.get_stress_target(worker) == stress + 20 and Staff.get_mood_target(worker) == mood - 10, "de noche y con 4 extra")


func _check_pay() -> void:
	_new_game()
	var day_worker: Dictionary = _hire("programmer", "junior")
	var night_worker: Dictionary = _hire("designer", "junior")
	Staff.set_own_schedule(day_worker["id"], 8, WEEKDAYS, 2)
	Staff.set_own_schedule(night_worker["id"], 22, WEEKDAYS)
	var day_hour: float = Staff.get_hour_pay(day_worker)
	var night_hour: float = Staff.get_hour_pay(night_worker)
	_expect(is_equal_approx(day_hour, float(day_worker["salary"]) / 30.0 / 8.0), "la hora normal es sueldo / 30 / 8")
	_to_midnight()
	for employee: Dictionary in [day_worker, night_worker]:
		employee["overtime_pay"] = 0.0
		employee["night_pay"] = 0.0
	# Un día hábil entero: 2 horas extra a 1.5 y 7 horas de noche a +20 %.
	var weekday: int = GameClock.get_weekday()
	var previous_work: bool = WEEKDAYS.has(posmod(weekday - 1, GameConstants.DAYS_PER_WEEK))
	_expect(WEEKDAYS.has(weekday) and previous_work, "la prueba empieza en un día hábil después de otro (%d)" % weekday)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(is_equal_approx(float(day_worker["overtime_pay"]), 2.0 * 1.5 * day_hour), "2 horas extra a 1.5 = %.2f: %.2f" % [
		3.0 * day_hour, float(day_worker["overtime_pay"])])
	_expect(is_equal_approx(float(day_worker["night_pay"]), 0.0), "de día no hay recargo")
	_expect(is_equal_approx(float(night_worker["night_pay"]), 7.0 * 0.2 * night_hour), "7 horas de noche a +20 %% = %.2f: %.2f" % [
		1.4 * night_hour, float(night_worker["night_pay"])])
	_expect(is_equal_approx(float(night_worker["overtime_pay"]), 0.0), "el turno de noche sin extra no las cobra")
	_expect(Staff.get_extra_earned(day_worker) == roundi(3.0 * day_hour), "lo ganado de horas extra")
	# Hasta la nómina del 15: cada día hábil suma lo mismo.
	var expected_overtime: float = float(day_worker["overtime_pay"])
	var expected_night: float = float(night_worker["night_pay"])
	while GameClock.get_day() < GameConstants.PAYROLL_DAYS[0]:
		weekday = GameClock.get_weekday()
		if WEEKDAYS.has(weekday):
			expected_overtime += 3.0 * day_hour
			expected_night += 2.0 * 0.2 * night_hour
		if WEEKDAYS.has(posmod(weekday - 1, GameConstants.DAYS_PER_WEEK)):
			expected_night += 5.0 * 0.2 * night_hour
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var totals: Dictionary[String, int] = Economy.get_month_totals(GameClock.get_month())
	_expect(absi(int(totals.get(Staff.CONCEPT_OVERTIME, 0))) == roundi(expected_overtime), "la nómina paga las horas extra: %s, se esperaba %d" % [
		totals, roundi(expected_overtime)])
	_expect(absi(int(totals.get(Staff.CONCEPT_NIGHT, 0))) == roundi(expected_night), "y el recargo nocturno: %d" % roundi(expected_night))
	_expect(totals.has(Staff.CONCEPT_PAYROLL), "los sueldos van aparte, como Nómina")
	_expect(is_equal_approx(float(day_worker["overtime_pay"]), 0.0) and int(day_worker["owed"]) == 0, "después de pagar no queda nada")
	# Sin dinero, las horas extra quedan debidas y se cobran con su concepto al alcanzar.
	day_worker["overtime_pay"] = 30.0
	Economy.spend(Economy.balance, "Prueba")
	Staff._run_payroll()
	_expect(int(day_worker["owed_overtime"]) == 30 and int(day_worker["owed"]) >= 30, "sin dinero quedan debidas")
	var before: int = absi(int(Economy.get_month_totals(GameClock.get_month()).get(Staff.CONCEPT_OVERTIME, 0)))
	Economy.earn(50000, "Prueba")
	_expect(int(day_worker["owed"]) == 0 and int(day_worker["owed_overtime"]) == 0, "al llegar el dinero se pagan")
	var after: int = absi(int(Economy.get_month_totals(GameClock.get_month()).get(Staff.CONCEPT_OVERTIME, 0)))
	_expect(after - before == 30, "con su concepto: %d" % (after - before))


func _check_firing() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	worker["overtime_pay"] = 20.4
	worker["night_pay"] = 9.6
	_expect(Staff.get_firing_cost(worker) == Staff.get_earned(worker) + 30 + int(worker["owed"]), "despedir cobra también las horas extra")


func _check_save() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	Staff.set_team_shift(team["id"], 7, WEEKDAYS, 3)
	var other: Dictionary = _hire("designer", "junior")
	Staff.set_own_schedule(other["id"], 22, WEEKDAYS, 1)
	other["overtime_pay"] = 12.5
	other["night_pay"] = 3.25
	other["owed"] = 40
	other["owed_overtime"] = 10
	other["owed_night"] = 5
	var state: Dictionary = JSON.parse_string(JSON.stringify(Staff.export_state()))
	Staff.new_game()
	Staff.import_state(state)
	var loaded: Dictionary = Staff.get_employee(other["id"])
	_expect(Staff.has_own_schedule(loaded) and Staff.get_schedule(loaded).start_hour == 22 and Staff.get_schedule(loaded).overtime == 1,
		"el horario propio se guarda")
	_expect(is_equal_approx(float(loaded["overtime_pay"]), 12.5) and is_equal_approx(float(loaded["night_pay"]), 3.25), "lo ganado de extra se guarda")
	_expect(int(loaded["owed_overtime"]) == 10 and int(loaded["owed_night"]) == 5, "lo debido de extra se guarda")
	_expect(WorkSchedule.from_dict(Staff.get_team(team["id"])["schedule"]).overtime == 3, "el turno guarda sus horas extra")
	_expect(Staff.get_schedule(Staff.get_employee(worker["id"])).end_hour == 19, "y su salida")
	# Una partida de antes del hito 34 carga sin horas extra ni horario propio.
	for saved: Dictionary in state["employees"]:
		for field: String in ["own_schedule", "overtime_pay", "night_pay", "owed_overtime", "owed_night"]:
			saved.erase(field)
	for saved: Dictionary in state["teams"]:
		(saved["schedule"] as Dictionary).erase("overtime")
	Staff.import_state(state)
	loaded = Staff.get_employee(other["id"])
	_expect(not Staff.has_own_schedule(loaded) and float(loaded["overtime_pay"]) == 0.0 and int(loaded["owed_overtime"]) == 0,
		"una partida vieja no tiene horas extra")
	_expect(Staff.get_schedule(Staff.get_employee(worker["id"])).overtime == 0, "ni turnos con horas extra")
	# Lo debido de extra nunca pasa de lo debido.
	state["employees"][1]["owed"] = 4
	state["employees"][1]["owed_overtime"] = 10
	Staff.import_state(state)
	_expect(int(Staff.get_employee(other["id"])["owed_overtime"]) == 4, "lo debido de extra se ajusta a lo debido")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	var panel: TeamsPanel = game.get_node("TeamsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	var more: Button = panel.get_team_control(team["id"], "more_overtime")
	var less: Button = panel.get_team_control(team["id"], "less_overtime")
	_expect(more != null and less != null and less.disabled, "el turno tiene −/+ de horas extra")
	more.pressed.emit()
	await get_tree().process_frame
	_expect(WorkSchedule.from_dict(Staff.get_team(team["id"])["schedule"]).overtime == 1, "+ suma una hora extra al turno")
	_expect(panel.get_status_text().contains("(1 h extra)"), "el aviso lo dice: %s" % panel.get_status_text())
	(panel.get_team_control(team["id"], "later") as Button).pressed.emit()
	await get_tree().process_frame
	var schedule: WorkSchedule = WorkSchedule.from_dict(Staff.get_team(team["id"])["schedule"])
	_expect(schedule.start_hour == 9 and schedule.overtime == 1, "mover la entrada mantiene las horas extra")
	panel.set_open(false)
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(worker["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Sigue el turno de su equipo"), "la ficha dice que sigue a su equipo: %s" % card.get_text())
	_expect(not card.get_shift_editor().visible, "sin horario propio no muestra sus controles")
	card.get_own_schedule_button().pressed.emit()
	await get_tree().process_frame
	_expect(Staff.has_own_schedule(worker) and Staff.get_schedule(worker).start_hour == 9, "Usar uno propio copia el del equipo")
	_expect(card.get_shift_editor().visible and card.get_text().contains("Horario propio"), "y muestra sus controles")
	(card.get_shift_editor().get_control("later") as Button).pressed.emit()
	(card.get_shift_editor().get_control("more_overtime") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(Staff.get_schedule(worker).start_hour == 10 and Staff.get_schedule(worker).overtime == 2, "los controles cambian su horario")
	_expect(card.get_text().contains("10:00–21:00 (2 h extra)"), "la ficha muestra su horario: %s" % card.get_text())
	(card.get_shift_editor().get_control("day_6") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(Staff.get_schedule(worker).days.has(6), "un día más")
	(card.get_shift_editor().get_control("day_5") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(not Staff.get_schedule(worker).days.has(5), "sin descanso no se aplica")
	_expect(card.get_own_schedule_button().text == "Usar el del equipo", "el botón vuelve al del equipo")
	panel.set_open(true)
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("horario propio"), "Equipos marca el horario propio: %s" % panel.get_list_text())
	panel.set_open(false)
	card.get_own_schedule_button().pressed.emit()
	await get_tree().process_frame
	_expect(not Staff.has_own_schedule(worker) and not card.get_shift_editor().visible, "volver al del equipo")
	game.queue_free()
	await get_tree().process_frame
