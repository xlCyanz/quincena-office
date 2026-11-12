# Prueba sin ventana del hito 35: plantillas de turno y agenda semanal (menú Horarios).
# Criterio: cambiar una plantilla cambia el turno de todos sus equipos; la agenda marca
# la hora en que un equipo no tiene líder presente.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_agenda.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261113
const WEEKDAYS: Array[int] = [0, 1, 2, 3, 4]
const DAY: int = 1
const TARDE: int = 2
const NOCHE: int = 3

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_defaults()
	_check_templates()
	_check_team_template()
	_check_rename_delete()
	_check_agenda()
	_check_save()
	await _check_ui()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Startup con un área de trabajo de tres puestos, dinero de sobra y los
# objetivos cumplidos.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 1
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


func _start(team: Dictionary) -> int:
	return WorkSchedule.from_dict(team["schedule"]).start_hour


func _check_defaults() -> void:
	_new_game()
	var names: Array[String] = []
	for template: Dictionary in Staff.shift_templates:
		names.append(template["name"])
	_expect(names == (["Diurno", "Tarde", "Noche"] as Array[String]), "empieza con Diurno, Tarde y Noche: %s" % [names])
	_expect(WorkSchedule.from_dict(Staff.get_template(DAY)["schedule"]).describe() == "lun–vie 8:00–17:00", "Diurno 8–17")
	_expect(WorkSchedule.from_dict(Staff.get_template(TARDE)["schedule"]).describe() == "lun–vie 14:00–23:00", "Tarde 14–23")
	_expect(WorkSchedule.from_dict(Staff.get_template(NOCHE)["schedule"]).describe() == "lun–vie 22:00–7:00", "Noche 22–7")
	var team: Dictionary = Staff.create_team()
	_expect(int(team["template_id"]) == DAY and Staff.get_template_of(team)["name"] == "Diurno", "un equipo nuevo sigue Diurno")
	_expect(_start(team) == 8, "y entra a las 8")


func _check_templates() -> void:
	_new_game()
	var first: Dictionary = Staff.create_team()
	var second: Dictionary = Staff.create_team()
	var own: Dictionary = Staff.create_team()
	Staff.set_team_shift(own["id"], 7, WEEKDAYS)
	_expect(int(own["template_id"]) == Staff.NO_TEMPLATE, "elegir el turno a mano lo suelta de la plantilla")
	var result: Dictionary = Staff.set_template_shift(DAY, 9, [0, 1, 2, 3], 2)
	_expect(result["ok"] and String(result["message"]).contains("Cambia el turno de 2 equipos"), "cambiar Diurno: %s" % result["message"])
	for team: Dictionary in [first, second]:
		var schedule: WorkSchedule = WorkSchedule.from_dict(team["schedule"])
		_expect(schedule.start_hour == 9 and schedule.days == ([0, 1, 2, 3] as Array[int]) and schedule.overtime == 2,
			"cambiar la plantilla cambia el turno de %s" % team["name"])
	_expect(_start(own) == 7, "el equipo con turno propio no cambia")
	_expect(not Staff.set_template_shift(DAY, 9, [0, 1, 2, 3, 4, 5, 6])["ok"], "una plantilla también necesita descanso")
	_expect(not Staff.set_template_shift(DAY, 9, WEEKDAYS, 5)["ok"], "y no más de 4 horas extra")
	_expect(not Staff.set_template_shift(99, 9, WEEKDAYS)["ok"], "una plantilla que no está")
	var created: Dictionary = Staff.create_template()
	_expect(created["name"] == "Turno 4" and _start(created) == 8, "una plantilla nueva: %s" % created["name"])
	_expect(Staff.set_template_shift(created["id"], 6, WEEKDAYS)["message"] == "Turno 4: lun–vie 6:00–15:00.", "sin equipos no los nombra")


func _check_team_template() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	var result: Dictionary = Staff.set_team_template(team["id"], NOCHE)
	_expect(result["ok"] and _start(team) == 22 and int(team["template_id"]) == NOCHE, "seguir Noche: %s" % result["message"])
	_expect(Staff.is_expected(Staff.employee_key(worker["id"]), 0, 22), "sus miembros llegan a las 22")
	result = Staff.set_team_template(team["id"], Staff.NO_TEMPLATE)
	_expect(result["ok"] and int(team["template_id"]) == Staff.NO_TEMPLATE and _start(team) == 22, "turno propio se queda con el turno")
	Staff.set_template_shift(NOCHE, 21, WEEKDAYS)
	_expect(_start(team) == 22, "y ya no sigue la plantilla")
	_expect(not Staff.set_team_template(team["id"], 99)["ok"], "una plantilla que no está")
	_expect(not Staff.set_team_template(99, DAY)["ok"], "un equipo que no está")


func _check_rename_delete() -> void:
	_new_game()
	_expect(Staff.rename_template(DAY, "  Mañana  ")["ok"] and Staff.get_template(DAY)["name"] == "Mañana", "renombrar sin espacios")
	_expect(not Staff.rename_template(DAY, "   ")["ok"], "sin nombre no")
	_expect(not Staff.rename_template(DAY, "x".repeat(30))["ok"], "un nombre muy largo no")
	var team: Dictionary = Staff.create_team()
	Staff.set_template_shift(DAY, 10, WEEKDAYS)
	var result: Dictionary = Staff.delete_template(DAY)
	_expect(result["ok"] and Staff.get_template(DAY).is_empty(), "borrar la plantilla: %s" % result["message"])
	_expect(int(team["template_id"]) == Staff.NO_TEMPLATE and _start(team) == 10, "sus equipos se quedan con ese turno")
	var next: Dictionary = Staff.create_team()
	_expect(int(next["template_id"]) == TARDE, "un equipo nuevo sigue la primera que queda")
	_expect(not Staff.delete_template(DAY)["ok"], "no se borra dos veces")


func _check_agenda() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var leader: Dictionary = _hire("team_leader", "senior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	var rows: Array[Dictionary] = Staff.get_agenda(0)
	_expect(rows.size() == 1 and rows[0]["label"] == team["name"], "una fila por equipo")
	var cells: Array = rows[0]["cells"]
	_expect(cells.size() == 24 and cells[7] == Staff.AGENDA_OFF and cells[12] == Staff.AGENDA_LUNCH and cells[17] == Staff.AGENDA_OFF,
		"libre fuera del turno y almuerzo a las 12")
	_expect(cells[8] == Staff.AGENDA_GAP and cells[16] == Staff.AGENDA_GAP, "sin líder, cada hora de trabajo es un hueco")
	_expect(Staff.get_agenda_gaps(0) == (["%s sin líder de 8:00 a 12:00" % team["name"], "%s sin líder de 13:00 a 17:00" % team["name"]] as Array[String]),
		"huecos del día: %s" % [Staff.get_agenda_gaps(0)])
	_expect(Staff.get_agenda(5)[0]["cells"].count(Staff.AGENDA_OFF) == 24, "el sábado no trabaja")
	Staff.add_to_team(team["id"], leader["id"])
	_expect(Staff.get_agenda_gaps(0).is_empty() and Staff.get_agenda(0)[0]["cells"][8] == Staff.AGENDA_WORK, "con su líder no hay huecos")
	# El líder con otro horario deja huecos donde no coincide.
	Staff.set_own_schedule(leader["id"], 14, WEEKDAYS)
	rows = Staff.get_agenda(0)
	_expect(rows.size() == 2 and rows[1]["kind"] == "employee" and rows[1]["label"] == leader["name"], "quien tiene horario propio tiene su fila")
	_expect(rows[1]["cells"][14] == Staff.AGENDA_WORK and rows[1]["cells"][18] == Staff.AGENDA_LUNCH, "con su horario")
	_expect(Staff.get_agenda_gaps(0) == (["%s sin líder de 8:00 a 12:00" % team["name"], "%s sin líder de 13:00 a 14:00" % team["name"]] as Array[String]),
		"huecos donde el líder no está: %s" % [Staff.get_agenda_gaps(0)])
	# Coincide con el rendimiento real.
	_expect(is_equal_approx(Staff.get_team_factor(team, 9), 0.75) and is_equal_approx(Staff.get_team_factor(team, 15), 1.0),
		"el hueco es la hora en que rinde 75 %")
	# En Emprendimiento rinde igual sin líder: no hay huecos.
	Company.stage = 0
	_expect(Staff.get_agenda_gaps(0).is_empty(), "en Emprendimiento no hay huecos")
	Company.stage = 1
	# Un equipo vacío no marca huecos.
	Staff.remove_from_team(worker["id"])
	Staff.remove_from_team(leader["id"])
	_expect(Staff.get_agenda_gaps(0).is_empty(), "un equipo sin miembros no tiene huecos")
	# El turno de noche cruza la medianoche: el lunes trabaja de 22 a 24 y el martes de 0 a 7.
	Staff.set_team_template(team["id"], NOCHE)
	var monday: Array = Staff.get_agenda(0)[0]["cells"]
	var tuesday: Array = Staff.get_agenda(1)[0]["cells"]
	_expect(monday[0] == Staff.AGENDA_OFF and monday[22] == Staff.AGENDA_WORK and monday[23] == Staff.AGENDA_WORK, "lunes de 22 a 24")
	_expect(tuesday[1] == Staff.AGENDA_WORK and tuesday[2] == Staff.AGENDA_LUNCH and tuesday[6] == Staff.AGENDA_WORK
		and tuesday[7] == Staff.AGENDA_OFF, "martes de 0 a 7 con almuerzo a las 2")


func _check_save() -> void:
	_new_game()
	var follows: Dictionary = Staff.create_team()
	var own: Dictionary = Staff.create_team()
	Staff.set_team_shift(own["id"], 6, WEEKDAYS)
	Staff.rename_template(TARDE, "Vespertino")
	Staff.set_template_shift(DAY, 9, WEEKDAYS, 1)
	var created: Dictionary = Staff.create_template()
	var state: Dictionary = JSON.parse_string(JSON.stringify(Staff.export_state()))
	Staff.new_game()
	Staff.import_state(state)
	_expect(Staff.shift_templates.size() == 4 and Staff.get_template(TARDE)["name"] == "Vespertino", "las plantillas se guardan")
	_expect(WorkSchedule.from_dict(Staff.get_template(DAY)["schedule"]).overtime == 1, "con su turno")
	_expect(int(Staff.get_team(follows["id"])["template_id"]) == DAY and int(Staff.get_team(own["id"])["template_id"]) == Staff.NO_TEMPLATE,
		"y quién sigue cuál")
	_expect(Staff.create_template()["id"] == int(created["id"]) + 1, "los ids siguen después de cargar")
	# Un equipo cuya plantilla falta se queda con su turno.
	state["shift_templates"].remove_at(0)
	Staff.import_state(state)
	_expect(int(Staff.get_team(follows["id"])["template_id"]) == Staff.NO_TEMPLATE and _start(Staff.get_team(follows["id"])) == 9,
		"sin su plantilla, turno propio")
	# Una partida de antes del hito 35 empieza con las plantillas de siempre.
	state.erase("shift_templates")
	state.erase("next_template_id")
	for team: Dictionary in state["teams"]:
		team.erase("template_id")
	Staff.import_state(state)
	_expect(Staff.shift_templates.size() == 3 and Staff.get_template(DAY)["name"] == "Diurno", "partida vieja: plantillas por defecto")
	_expect(int(Staff.get_team(follows["id"])["template_id"]) == Staff.NO_TEMPLATE and _start(Staff.get_team(follows["id"])) == 9,
		"y sus equipos con turno propio")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	var other: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	var panel: TeamsPanel = game.get_node("TeamsPanel")
	_expect(panel.get_open_button().text == "Horarios", "el botón se llama Horarios")
	panel.set_open(true)
	await get_tree().process_frame
	_expect(panel.get_view() == TeamsPanel.VIEW_TEAMS, "abre en Equipos")
	var choice: OptionButton = panel.get_team_control(team["id"], "template")
	_expect(choice != null and choice.get_item_text(choice.selected) == "Diurno" and choice.get_item_text(choice.item_count - 1) == "Turno propio",
		"cada equipo elige plantilla o turno propio")
	# Con plantilla, sus controles cambian la plantilla (y el otro equipo).
	(panel.get_team_control(team["id"], "later") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(_start(Staff.get_template(DAY)) == 9 and _start(other) == 9, "el turno del equipo edita la plantilla: %s" % panel.get_status_text())
	choice = panel.get_team_control(team["id"], "template")
	choice.select(choice.item_count - 1)
	choice.item_selected.emit(choice.item_count - 1)
	await get_tree().process_frame
	_expect(int(team["template_id"]) == Staff.NO_TEMPLATE, "elegir Turno propio")
	(panel.get_team_control(team["id"], "later") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(_start(team) == 10 and _start(other) == 9, "con turno propio solo cambia ese equipo")
	# Plantillas.
	panel.get_view_button(TeamsPanel.VIEW_TEMPLATES).pressed.emit()
	await get_tree().process_frame
	_expect(panel.get_view() == TeamsPanel.VIEW_TEMPLATES and panel.get_create_button().text == "Crear plantilla", "vista Plantillas")
	var info: Label = panel.get_template_control(DAY, "info")
	_expect(info != null and info.text.contains("la siguen %s" % other["name"]), "dice qué equipos la siguen: %s" % (info.text if info else ""))
	(panel.get_template_control(TARDE, "more_overtime") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(WorkSchedule.from_dict(Staff.get_template(TARDE)["schedule"]).overtime == 1, "editar el turno de una plantilla")
	var name_edit: LineEdit = panel.get_template_control(TARDE, "name")
	name_edit.text = "Vespertino"
	name_edit.text_submitted.emit("Vespertino")
	await get_tree().process_frame
	_expect(Staff.get_template(TARDE)["name"] == "Vespertino", "renombrar desde el panel")
	panel.get_create_button().pressed.emit()
	await get_tree().process_frame
	_expect(Staff.shift_templates.size() == 4, "crear una plantilla")
	(panel.get_template_control(4, "delete") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(Staff.shift_templates.size() == 3, "borrar una plantilla")
	# Agenda.
	panel.get_view_button(TeamsPanel.VIEW_AGENDA).pressed.emit()
	await get_tree().process_frame
	_expect(not panel.get_create_button().visible, "la agenda no crea nada")
	panel.get_agenda_day_button(0).pressed.emit()
	await get_tree().process_frame
	var gaps: Array[String] = panel.get_agenda_gaps()
	_expect(gaps.size() == 2 and gaps[0] == "%s sin líder de 10:00 a 14:00" % team["name"], "la agenda marca los huecos sin líder: %s" % [gaps])
	_expect(panel.get_list_text().contains("Huecos: ") and panel.get_list_text().contains("rinde 75 %"), "y los escribe: %s" % panel.get_list_text())
	panel.get_agenda_day_button(6).pressed.emit()
	await get_tree().process_frame
	_expect(panel.get_agenda_gaps().is_empty() and panel.get_list_text().contains("Sin huecos este día."), "el domingo no hay huecos")
	panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame
