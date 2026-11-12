# Prueba sin ventana del hito 10: vacantes y candidatos.
# Criterio: al publicar una vacante llegan candidatos en los días siguientes; con
# publicidad llegan más; un candidato desaparece al caducar.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_vacancies.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_publish()
	_check_arrivals()
	_check_high_offer()
	_check_close_and_discard()
	_check_determinism_and_save()
	await _check_panel()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)


# Avanza el reloj hasta la próxima hora de llegada de candidatos.
func _to_next_arrival() -> void:
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)


func _ids(vacancy_id: int) -> Array[int]:
	var ids: Array[int] = []
	for candidate: Dictionary in Staff.get_vacancy(vacancy_id)["candidates"]:
		ids.append(candidate["id"])
	return ids


func _check_catalog() -> void:
	# El líder de equipo, el gerente, el ejecutivo, el recepcionista, el contador y la limpieza llegan en los hitos 31–33, 36 y 37 (sin niveles, sueldo fijo).
	var roles: Array[String] = ["programmer", "designer", "qa", "salesperson", "team_leader", "manager", "receptionist", "accountant", "cleaner", "executive"]
	var levels: Array[String] = ["intern", "junior", "semi_senior", "senior"]
	_expect(StaffCatalog.get_role_ids() == roles, "cargos: %s" % [StaffCatalog.get_role_ids()])
	_expect(StaffCatalog.get_level_ids() == levels, "niveles: %s" % [StaffCatalog.get_level_ids()])
	var table: Dictionary = {
		["programmer", "intern"]: 600, ["programmer", "senior"]: 3200, ["designer", "junior"]: 1000,
		["qa", "semi_senior"]: 1500, ["salesperson", "senior"]: 2500, ["team_leader", "intern"]: 4200, ["manager", "senior"]: 6000, ["executive", "intern"]: 9000, ["receptionist", "intern"]: 700, ["accountant", "senior"]: 1300, ["cleaner", "intern"]: 500,
	}
	for key: Array in table:
		_expect(StaffCatalog.get_salary(key[0], key[1]) == table[key], "sueldo de %s %s" % key)


func _check_publish() -> void:
	_new_game()
	var result: Dictionary = Staff.open_vacancy("programmer", "junior", 1200, false)
	_expect(result["ok"] and Staff.vacancies.size() == 1 and Economy.balance == 20000,
		"publicar sin publicidad es gratis: %s" % result["message"])
	result = Staff.open_vacancy("designer", "senior", 2700, true)
	_expect(result["ok"] and Economy.balance == 19900, "la publicidad cuesta $100: saldo %d" % Economy.balance)
	var last: Dictionary = Economy.movements.back()
	_expect(last["concept"] == Staff.CONCEPT_PUBLICITY and last["amount"] == -100, "movimiento de publicidad: %s" % last)
	# Son las 08:00: los primeros candidatos llegan hoy a las 09:00 y la publicidad dura 7 llegadas.
	_expect(Staff.publicity_days_left(Staff.get_vacancy(result["id"])) == 7, "días de publicidad")
	_expect(not Staff.open_vacancy("tester", "junior", 900, false)["ok"], "un cargo que no existe no se publica")
	# Sin dinero para la publicidad no se publica nada.
	Economy.import_state({"balance": 50})
	var before: int = Staff.vacancies.size()
	result = Staff.open_vacancy("qa", "junior", 900, true)
	_expect(not result["ok"] and Staff.vacancies.size() == before and Economy.balance == 50,
		"sin dinero no se publica con publicidad: %s" % result["message"])
	_expect(Staff.vacancies[0]["candidates"].is_empty(), "antes de las 09:00 no hay candidatos")


func _check_arrivals() -> void:
	_new_game()
	var plain: int = Staff.open_vacancy("programmer", "junior", 1200, false)["id"]
	var advertised: int = Staff.open_vacancy("programmer", "junior", 1200, true)["id"]
	var publicity_days: int = int(StaffCatalog.get_hiring("publicity_days"))
	var waiting_days: int = int(StaffCatalog.get_hiring("candidate_days"))
	var max_waiting: int = int(StaffCatalog.get_hiring("max_waiting"))
	var seen: Dictionary[int, int] = {}  # id del candidato -> día en que llegó
	var plain_total: int = 0
	var advertised_total: int = 0
	var advertised_first_week: int = 0
	for day: int in range(30):
		var plain_before: Array[int] = _ids(plain)
		var advertised_before: Array[int] = _ids(advertised)
		_to_next_arrival()
		var today: int = GameClock.get_day_count()
		for vacancy_id: int in [plain, advertised]:
			var vacancy: Dictionary = Staff.get_vacancy(vacancy_id)
			var candidates: Array[Dictionary] = vacancy["candidates"]
			_expect(candidates.size() <= max_waiting, "día %d: %d esperando" % [today, candidates.size()])
			var before: Array[int] = plain_before if vacancy_id == plain else advertised_before
			var arrived: int = 0
			for candidate: Dictionary in candidates:
				if not before.has(candidate["id"]):
					arrived += 1
					seen[candidate["id"]] = today
					_check_candidate(candidate, vacancy, today)
				# Nadie se queda más días de los que espera.
				_expect(today < int(candidate["arrived_day"]) + waiting_days,
					"día %d: %s sigue después de caducar" % [today, candidate["name"]])
			# Quien llegó hace menos días de los que espera sigue ahí.
			for id: int in before:
				if today < seen[id] + waiting_days:
					_expect(_ids(vacancy_id).has(id), "día %d: el candidato %d se fue antes de tiempo" % [today, id])
			var room: bool = before.size() - _count_expired(before, seen, today, waiting_days) + arrived < max_waiting
			if vacancy_id == plain:
				plain_total += arrived
				_expect(arrived <= 1, "día %d: sin publicidad llegaron %d" % [today, arrived])
			else:
				advertised_total += arrived
				if today < publicity_days:
					advertised_first_week += arrived
					_expect(arrived <= 2 and (arrived >= 1 or not room), "día %d: con publicidad llegaron %d" % [today, arrived])
				else:
					_expect(arrived <= 1, "día %d: terminada la publicidad llegaron %d" % [today, arrived])
	_expect(plain_total > 0, "a una vacante sin publicidad también llegan candidatos (%d)" % plain_total)
	_expect(advertised_first_week >= publicity_days, "con publicidad llega al menos uno por día (%d)" % advertised_first_week)
	_expect(advertised_total > plain_total, "con publicidad llegan más: %d contra %d" % [advertised_total, plain_total])


func _count_expired(ids: Array[int], seen: Dictionary[int, int], today: int, waiting_days: int) -> int:
	var count: int = 0
	for id: int in ids:
		if today >= seen[id] + waiting_days:
			count += 1
	return count


func _check_candidate(candidate: Dictionary, vacancy: Dictionary, today: int) -> void:
	var role: String = vacancy["role"]
	var level: String = vacancy["level"]
	var person: String = candidate["name"]
	_expect(candidate["role"] == role and candidate["level"] == level and candidate["arrived_day"] == today,
		"%s: cargo, nivel o día de llegada" % person)
	var table: int = StaffCatalog.get_salary(role, level)
	var asked: int = candidate["asked_salary"]
	_expect(asked % 50 == 0 and asked >= table * 0.9 - 25 and asked <= table * 1.2 + 25,
		"%s pide %d (tabla %d)" % [person, asked, table])
	var first_name: String = person.get_slice(" ", 0)
	_expect(StaffCatalog.get_first_names(candidate["sex"]).has(first_name), "%s: nombre de su sexo" % person)
	var ages: Vector2i = StaffCatalog.get_age_range(level)
	_expect(candidate["age"] >= ages.x and candidate["age"] <= ages.y, "%s: edad %d" % [person, candidate["age"]])
	var width: int = StaffCatalog.get_skill_range_width()
	for skill: String in StaffCatalog.get_skill_ids():
		var value: int = candidate["skills"][skill]
		var low: int = candidate["skill_low"][skill]
		var allowed: Vector2i = StaffCatalog.get_main_skill_range(level) \
			if skill == StaffCatalog.get_main_skill(role) else StaffCatalog.get_other_skill_range()
		_expect(value >= allowed.x and value <= allowed.y, "%s: %s = %d" % [person, skill, value])
		_expect(low >= 1 and low <= value and value <= low + width and low + width <= 100,
			"%s: rango de %s %d–%d no contiene %d" % [person, skill, low, low + width, value])
	var traits: Array[String] = candidate["traits"]
	var unique: Dictionary = {}
	for trait_id: String in traits:
		unique[trait_id] = true
	_expect(traits.size() >= 1 and traits.size() <= 3 and unique.size() == traits.size(), "%s: rasgos %s" % [person, traits])


func _check_high_offer() -> void:
	_new_game()
	# Ofrecer 20% más que la tabla atrae a veces a uno más (hasta 2 por día sin publicidad).
	var vacancy_id: int = Staff.open_vacancy("qa", "junior", 1100, false)["id"]
	var most: int = 0
	for day: int in range(30):
		var before: Array[int] = _ids(vacancy_id)
		_to_next_arrival()
		var arrived: int = 0
		for id: int in _ids(vacancy_id):
			if not before.has(id):
				arrived += 1
		most = maxi(most, arrived)
	_expect(most == 2, "con un sueldo alto algún día llegan 2 (máximo %d)" % most)


func _check_close_and_discard() -> void:
	_new_game()
	var vacancy_id: int = Staff.open_vacancy("salesperson", "semi_senior", 1600, true)["id"]
	_to_next_arrival()
	var ids: Array[int] = _ids(vacancy_id)
	_expect(not ids.is_empty() and Staff.get_waiting_count() == ids.size(), "hay candidatos esperando")
	_expect(Staff.discard_candidate(ids[0]) and not _ids(vacancy_id).has(ids[0]), "descartar a un candidato")
	_expect(not Staff.discard_candidate(ids[0]), "no se descarta dos veces")
	_expect(Staff.close_vacancy(vacancy_id) and Staff.vacancies.is_empty() and Staff.get_waiting_count() == 0,
		"cerrar la vacante se lleva a sus candidatos")
	_expect(not Staff.close_vacancy(vacancy_id), "no se cierra dos veces")


# Misma semilla, mismos candidatos; y guardar y cargar no cambia lo que viene.
func _check_determinism_and_save() -> void:
	var runs: Array[String] = []
	for run: int in range(2):
		_new_game()
		Staff.open_vacancy("programmer", "senior", 3200, true)
		for day: int in range(5):
			_to_next_arrival()
		runs.append(JSON.stringify(Staff.export_state()))
	_expect(runs[0] == runs[1], "con la misma semilla llegan los mismos candidatos")

	var clock: Dictionary = GameClock.export_state()
	var staff_json: String = JSON.stringify(Staff.export_state())
	for day: int in range(3):
		_to_next_arrival()
	var continued: String = JSON.stringify(Staff.export_state())
	GameClock.import_state(clock)
	Staff.import_state(JSON.parse_string(staff_json))
	_expect(JSON.stringify(Staff.export_state()) == staff_json, "exportar e importar el personal no cambia nada")
	for day: int in range(3):
		_to_next_arrival()
	_expect(JSON.stringify(Staff.export_state()) == continued, "tras cargar llegan los mismos candidatos que sin cargar")

	# Con SaveManager: la vacante y sus candidatos vuelven al cargar.
	_expect(SaveManager.save_game("slot_1"), "guardar la partida")
	var saved: String = JSON.stringify(Staff.export_state())
	_new_game()
	_expect(Staff.vacancies.is_empty(), "una partida nueva empieza sin vacantes")
	_expect(SaveManager.load_game("slot_1") and JSON.stringify(Staff.export_state()) == saved,
		"cargar la partida recupera las vacantes y los candidatos")
	SaveManager.take_scene_state()
	# Una partida de la fase 1 (sin personal) carga sin vacantes.
	var path: String = SaveManager.save_dir.path_join("slot_2.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.save_dir.path_join("slot_1.json")))
	data.erase("staff")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_expect(SaveManager.load_game("slot_2") and Staff.vacancies.is_empty(), "una partida sin personal carga sin vacantes")
	SaveManager.take_scene_state()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(SaveManager.save_dir.path_join("slot_1.json"))


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var panel: StaffPanel = game.get_node("StaffPanel")
	var build_panel: BuildPanel = game.get_node("BuildPanel")
	_expect(panel.get_open_button().get_parent() == build_panel.get_menu_bar() and panel.get_open_button().text == "Personal",
		"el botón Personal está en la barra de menús")
	await _click(panel.get_open_button())
	_expect(panel.is_open() and not GameClock.is_paused, "Personal se abre sin pausar el tiempo")
	_expect(panel.get_list_text().contains("No hay vacantes"), "lista vacía: %s" % panel.get_list_text())

	panel.select_role_and_level("designer", "semi_senior")
	_expect(panel.get_salary_offer() == 1700, "el sueldo arranca en el de la tabla: %d" % panel.get_salary_offer())
	await _click(panel.get_salary_buttons()[1])
	await _click(panel.get_salary_buttons()[1])
	await _click(panel.get_salary_buttons()[0])
	_expect(panel.get_salary_offer() == 1750, "botones −/+ de $50: %d" % panel.get_salary_offer())
	await _click(panel.get_publicity_check())
	await _click(panel.get_publish_button())
	_expect(Staff.vacancies.size() == 1 and Staff.vacancies[0]["salary"] == 1750 and Economy.balance == 19900,
		"publicar desde el panel con publicidad")
	_expect(panel.get_status_text().begins_with("Vacante publicada"), "aviso: %s" % panel.get_status_text())
	_expect(not panel.get_publicity_check().button_pressed, "la casilla de publicidad se desmarca al publicar")
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Diseñador SemiSenior · $1,750 al mes · publicidad 7 días"),
		"vacante en la lista: %s" % panel.get_list_text())

	_to_next_arrival()
	await get_tree().process_frame
	var vacancy: Dictionary = Staff.vacancies[0]
	var first: Dictionary = vacancy["candidates"][0]
	_expect(panel.get_list_text().contains(first["name"]) and panel.get_list_text().contains("se va en 3 días"),
		"candidato en la lista: %s" % panel.get_list_text())
	_expect(panel.get_open_button().text == "Personal (%d)" % Staff.get_waiting_count(),
		"el botón cuenta los candidatos: %s" % panel.get_open_button().text)
	var count: int = Staff.get_waiting_count()
	await _click(panel.get_discard_button(first["id"]))
	_expect(Staff.get_waiting_count() == count - 1, "descartar desde el panel")
	await get_tree().process_frame
	await _click(panel.get_vacancy_close_button(vacancy["id"]))
	_expect(Staff.vacancies.is_empty(), "cerrar la vacante desde el panel")

	# Al entrar en modo construcción el panel se cierra.
	await _click(build_panel.get_open_button())
	_expect(not panel.is_open(), "el modo construcción cierra Personal")
	build_panel.set_build_mode(false)
	game.queue_free()
	await get_tree().process_frame


func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
