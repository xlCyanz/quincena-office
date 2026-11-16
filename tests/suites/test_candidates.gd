# Candidatos según la empresa: más estrellas, más sueldo ofrecido, mejor ambiente y el premio
# traen más o mejores candidatos.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=candidates
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261156
## Muestras para comparar habilidades.
const SAMPLES: int = 400

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_data()
	_check_first_batch()
	_check_arrivals()
	_check_quality()
	_check_skills()
	_check_ambiance()
	_check_award()
	_check_disabled()
	_check_save()
	await _check_ui()
	Staff.company_hiring_enabled = true
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	Staff.company_hiring_enabled = true
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()


# Abre una vacante de programador Junior y devuelve cuántos llegan el primer día.
func _first_day(salary: int = 1200, publicity: bool = false) -> int:
	var result: Dictionary = Staff.open_vacancy("programmer", "junior", salary, publicity)
	_expect(result["ok"], "vacante publicada: %s" % result["message"])
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	return (Staff.get_vacancy(result["id"])["candidates"] as Array).size()


func _main_skills(salary: int) -> Array[int]:
	var values: Array[int] = []
	for i: int in range(SAMPLES):
		var candidate: Dictionary = Staff._make_candidate({"role": "programmer", "level": "junior", "salary": salary}, 0)
		values.append(int(candidate["skills"]["programming"]))
	return values


func _mean(values: Array[int]) -> float:
	var total: int = 0
	for value: int in values:
		total += value
	return float(total) / maxi(1, values.size())


func _check_data() -> void:
	_expect(int(StaffCatalog.get_hiring("first_batch")) == 3 and int(StaffCatalog.get_hiring("first_batch_per_star")) == 1
		and int(StaffCatalog.get_hiring("neutral_stars")) == 3 and int(StaffCatalog.get_hiring("first_batch_min")) == 1,
		"primera tanda: 3 ± 1 por estrella, al menos 1")
	_expect(is_equal_approx(float(StaffCatalog.get_hiring("quality_per_salary")), 2.5)
		and is_equal_approx(float(StaffCatalog.get_hiring("quality_per_ambiance")), 0.02)
		and is_equal_approx(float(StaffCatalog.get_hiring("max_quality")), 0.8), "calidad por sueldo y ambiente")


func _check_first_batch() -> void:
	_new_game()
	var expected: Dictionary[float, int] = {1.0: 1, 2.0: 2, 3.0: 3, 3.9: 3, 4.0: 4, 5.0: 5}
	for reputation: float in expected:
		Projects.reputation = reputation
		_expect(Staff.get_first_batch() == expected[reputation], "con %.1f ★ llegan %d" % [reputation, Staff.get_first_batch()])


func _check_arrivals() -> void:
	_new_game()
	Projects.reputation = 1.0
	var low: int = _first_day()
	_new_game()
	Projects.reputation = 5.0
	var high: int = _first_day()
	_expect(low == 1 and high == 5, "con 1 ★ llega %d y con 5 ★ llegan %d" % [low, high])
	_new_game()
	Projects.reputation = 3.0
	_expect(_first_day(1200, true) == 4, "con publicidad uno más el primer día")
	# Después del primer día llegan como antes (0 o 1 sin publicidad).
	_new_game()
	Projects.reputation = 5.0
	var vacancy_id: int = Staff.open_vacancy("programmer", "junior", 1200, false)["id"]
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var vacancy: Dictionary = Staff.get_vacancy(vacancy_id)
	_expect(bool(vacancy["first_done"]), "la primera tanda ya llegó")
	var first: Array = (vacancy["candidates"] as Array).duplicate()
	(vacancy["candidates"] as Array).clear()
	var later: Array[int] = []
	for day: int in range(10):
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
		later.append((vacancy["candidates"] as Array).size())
		(vacancy["candidates"] as Array).clear()
	_expect(first.size() == 5 and later.max() <= 1, "después, 0 o 1 por día: %s" % [later])


func _check_quality() -> void:
	_new_game()
	_expect(is_zero_approx(Staff.get_work_area_ambiance()), "sin Áreas de trabajo, ambiente 0")
	_expect(is_zero_approx(Staff.get_candidate_quality("programmer", "junior", 1200)), "sueldo de la tabla: calidad 0")
	_expect(is_equal_approx(Staff.get_candidate_quality("programmer", "junior", 1440), 0.5), "120 %: +0.5")
	_expect(is_equal_approx(Staff.get_candidate_quality("programmer", "junior", 1080), -0.25), "90 %: −0.25")
	_expect(is_equal_approx(Staff.get_candidate_quality("programmer", "junior", 3000), 0.8), "con mucho más, hasta +0.8")
	_expect(is_equal_approx(Staff.get_candidate_quality("programmer", "junior", 300), -0.8), "con mucho menos, hasta −0.8")
	_expect(is_equal_approx(Staff.quality_position(0.0, 0.5), 0.5) and is_equal_approx(Staff.quality_position(1.0, 0.5), 1.0)
		and is_equal_approx(Staff.quality_position(1.0, -0.5), 0.5) and is_equal_approx(Staff.quality_position(0.3, 0.0), 0.3),
		"la calidad corre el rango")


func _check_skills() -> void:
	_new_game()
	var main_range: Vector2i = StaffCatalog.get_main_skill_range("junior")
	var table: Array[int] = _main_skills(1200)
	var better: Array[int] = _main_skills(1440)
	var worse: Array[int] = _main_skills(960)
	_expect(_mean(better) > _mean(table) + 4.0 and _mean(table) > _mean(worse) + 4.0,
		"más sueldo, mejores habilidades: %.1f / %.1f / %.1f" % [_mean(worse), _mean(table), _mean(better)])
	var middle: int = main_range.x + roundi((main_range.y - main_range.x) * 0.5)
	_expect(better.min() >= middle and table.min() >= main_range.x and table.max() <= main_range.y
		and worse.max() <= middle, "dentro del rango del nivel: 120 %% desde %d, 80 %% hasta %d" % [better.min(), worse.max()])
	var asked: Dictionary = Staff._make_candidate({"role": "programmer", "level": "junior", "salary": 3000}, 0)
	var ratio: Array = StaffCatalog.get_hiring("asked_salary_ratio")
	_expect(int(asked["asked_salary"]) <= roundi(1200 * float(ratio[1])) + 50, "pide lo de siempre")


func _check_ambiance() -> void:
	_new_game()
	var y: int = GridEdge.AXIS_Y
	_builder.apply([{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR}, {"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL}])
	_expect(_builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "Área de trabajo")
	_expect(is_zero_approx(Staff.get_work_area_ambiance()), "sin adornos, ambiente 0")
	for cell: Vector2i in [Vector2i(3, 0), Vector2i(5, 0)]:
		_expect(_builder.place("large_plant", cell, 0)["ok"], "planta grande en %s" % cell)
	var ambiance: float = Staff.get_work_area_ambiance()
	_expect(ambiance > 0.0, "con plantas el ambiente sube: %.1f" % ambiance)
	_expect(is_equal_approx(Staff.get_candidate_quality("programmer", "junior", 1200), ambiance * 0.02),
		"el ambiente mejora a los candidatos: %.2f" % Staff.get_candidate_quality("programmer", "junior", 1200))
	var table: Array[int] = _main_skills(1200)
	_new_game()
	var plain: Array[int] = _main_skills(1200)
	_expect(_mean(table) > _mean(plain), "con ambiente llegan mejores: %.1f contra %.1f" % [_mean(table), _mean(plain)])


func _award_effects() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in Events._events_data()["events"]:
		if event["id"] == "award":
			for option: Dictionary in event["options"]:
				for effect: Dictionary in option["effects"]:
					if effect["type"] == "candidates":
						found.append(effect)
	return found


func _check_award() -> void:
	_new_game()
	var effects: Array[Dictionary] = _award_effects()
	_expect(effects.size() == 2 and int(effects[0]["days"]) == 7, "las dos respuestas del premio suman candidatos 7 días")
	Projects.reputation = 3.0
	var text: String = Events._apply({"type": "candidates", "days": 7}, {}, "Premio")
	_expect(text.contains("candidato más") and Staff.award_until == Staff.next_arrival_day() + 7, "el premio dura 7 días: %s" % text)
	_expect(_first_day() == 4, "primer día con el premio: 3 + 1")
	var vacancy: Dictionary = Staff.vacancies[0]
	var counts: Array[int] = []
	for day: int in range(9):
		(vacancy["candidates"] as Array).clear()
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
		counts.append((vacancy["candidates"] as Array).size())
	_expect(counts.slice(0, 6).min() >= 1 and counts.slice(7).max() <= 1, "al menos uno por día mientras dura: %s" % [counts])
	_expect(Staff.describe_hiring_outlook("programmer", "junior", 1200).find("premio") < 0, "terminado, ya no se anuncia")


func _check_disabled() -> void:
	_new_game()
	Staff.company_hiring_enabled = false
	Projects.reputation = 5.0
	_expect(_first_day() <= 1, "sin la regla nueva llega como antes")
	var better: Array[int] = _main_skills(3000)
	var table: Array[int] = _main_skills(1200)
	_expect(absf(_mean(better) - _mean(table)) < 3.0, "y el sueldo no cambia las habilidades")
	Staff.company_hiring_enabled = true


func _check_save() -> void:
	_new_game()
	Staff.boost_candidates(7)
	Staff.open_vacancy("programmer", "junior", 1200, false)
	var state: Dictionary = Staff.export_state()
	var until: int = Staff.award_until
	_new_game()
	_expect(Staff.award_until == 0, "partida nueva sin premio")
	Staff.import_state(state)
	_expect(Staff.award_until == until and not bool(Staff.vacancies[0]["first_done"]), "se guardan el premio y la primera tanda")
	var old: Dictionary = state.duplicate(true)
	old.erase("award_until")
	for saved: Dictionary in old["vacancies"]:
		saved.erase("first_done")
	Staff.import_state(old)
	_expect(Staff.award_until == 0 and bool(Staff.vacancies[0]["first_done"]), "una partida vieja carga sin primera tanda pendiente")


func _check_ui() -> void:
	_new_game()
	Projects.reputation = 5.0
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	var panel: StaffPanel = game.get_node("StaffPanel")
	panel.set_open(true)
	panel.select_role_and_level("programmer", "junior")
	var text: String = panel.get_outlook_label().text
	_expect(text.begins_with("Llegan 5 el primer día (5 ★)") and text.contains("normales"), "el formulario lo anuncia: %s" % text)
	panel.get_salary_buttons()[1].pressed.emit()
	text = panel.get_outlook_label().text
	_expect(text.contains("sueldo +4 %") and text.contains("+10 %"), "con más sueldo, mejores: %s" % text)
	game.queue_free()
	await get_tree().process_frame
