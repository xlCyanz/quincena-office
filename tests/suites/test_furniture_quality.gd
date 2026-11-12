# Prueba del hito 46: calidades de muebles.
# Criterio: una computadora pro rinde más que la básica; con silla ergonómica la energía
# baja más lento; mejorar cobra la diferencia.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=furniture_quality
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261146
const OPEN_CELL := Vector2i(3, 3)
## Puesto A: escritorio sencillo con la silla al sur.
const DESK_A := Vector2i(4, 4)
const CHAIR_A := Vector2i(4, 5)
## Puesto B: escritorio amplio (2 casillas) con la silla al sur de su primera casilla.
const DESK_B := Vector2i(0, 4)
const CHAIR_B := Vector2i(0, 5)
## Escritorio libre para probar la venta.
const FREE_DESK := Vector2i(5, 1)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_upgrade()
	_check_monitor()
	_check_production()
	_check_energy()
	_check_wide_desk()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()


# Área de trabajo con el puesto A (sencillo, básico) y un programador sentado en él.
func _station_a() -> Dictionary:
	_expect(_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)["ok"], "marcar el Área de trabajo")
	_expect(_builder.place("simple_desk", DESK_A, 2)["ok"], "escritorio A")
	_expect(_builder.install_computer("basic_computer", DESK_A)["ok"], "computadora A")
	_expect(_builder.place("basic_chair", CHAIR_A, 0)["ok"], "silla A")
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratar un programador")
	return employee


# Puesto B: escritorio amplio con computadora básica y silla ergonómica, y otro programador.
func _station_b() -> Dictionary:
	_expect(_builder.place("wide_desk", DESK_B, 2)["ok"], "escritorio amplio")
	_expect(_builder.install_computer("basic_computer", DESK_B)["ok"], "computadora B")
	_expect(_builder.place("ergonomic_chair", CHAIR_B, 0)["ok"], "silla ergonómica")
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratar el segundo programador")
	return employee


func _item_at(cell: Vector2i) -> Dictionary:
	return OfficeState.furniture[OfficeState.find_furniture_at(cell)]


func _check_catalog() -> void:
	var prices: Dictionary[String, int] = {"mid_computer": 1200, "pro_computer": 2500, "second_monitor": 300,
		"ergonomic_chair": 250, "wide_desk": 350}
	for id: String in prices:
		_expect(FurnitureCatalog.get_price(id) == prices[id], "%s cuesta %s" % [id, MoneyFormat.format(prices[id])])
	_expect(_near(FurnitureCatalog.get_production_bonus("basic_computer"), 0.0)
		and _near(FurnitureCatalog.get_production_bonus("mid_computer"), 0.15)
		and _near(FurnitureCatalog.get_production_bonus("pro_computer"), 0.3)
		and _near(FurnitureCatalog.get_production_bonus("second_monitor"), 0.05), "básica +0, media +15 %%, pro +30 %%, monitor +5 %%")
	_expect(_near(Production.get_computer_bonus("pro_computer"), 0.3), "Production lee el bono de la pro")
	_expect(FurnitureCatalog.get_upgrade("basic_computer") == "mid_computer" and FurnitureCatalog.get_upgrade("mid_computer") == "pro_computer"
		and FurnitureCatalog.get_upgrade("pro_computer").is_empty() and FurnitureCatalog.get_upgrade("basic_chair") == "ergonomic_chair"
		and FurnitureCatalog.get_upgrade("ergonomic_chair").is_empty(), "escalera de calidades")
	_expect(FurnitureCatalog.is_monitor("second_monitor") and not FurnitureCatalog.is_monitor("pro_computer"), "el monitor es monitor")
	_expect(FurnitureCatalog.get_work_energy("ergonomic_chair") == -4 and FurnitureCatalog.get_work_energy("basic_chair") == 0,
		"la ergonómica −4/h; la básica usa la de data/staff.json")
	_expect(FurnitureCatalog.get_mood_bonus("wide_desk") == 5 and FurnitureCatalog.get_mood_bonus("simple_desk") == 0, "amplio +5 de ánimo")
	_expect(FurnitureCatalog.get_footprint("wide_desk", Vector2i.ZERO, 0).size() == 2
		and bool(FurnitureCatalog.get_item("wide_desk")["accepts_computer"]), "el amplio ocupa 2 casillas y lleva computadora")


func _check_upgrade() -> void:
	_new_game()
	var employee: Dictionary = _station_a()
	var key: String = Staff.employee_key(employee["id"])
	# El puesto está ocupado: no se vende, pero sí se mejora.
	_expect(not _builder.quote_sell_furniture_at(DESK_A)["ok"], "el puesto ocupado no se vende")
	var balance: int = Economy.balance
	var result: Dictionary = _builder.upgrade(DESK_A)
	_expect(result["ok"] and Economy.balance == balance - 700, "básica → media cobra la diferencia ($700): %s" % result["message"])
	_expect(_item_at(DESK_A)["computer"] == "mid_computer" and Workstations.computer_of(OfficeState.furniture, key) == "mid_computer",
		"la computadora del puesto pasa a media")
	_expect(String(result["message"]).contains("Computadora media") and String(result["message"]).contains("$700"), result["message"])
	balance = Economy.balance
	_expect(_builder.upgrade(DESK_A)["ok"] and Economy.balance == balance - 1300, "media → pro cobra $1,300")
	result = _builder.quote_upgrade(DESK_A)
	_expect(not result["ok"] and String(result["message"]).contains("la mejor"), "la pro no se mejora: %s" % result["message"])
	# La silla básica pasa a ergonómica sin dejar de ser de quien la usa.
	balance = Economy.balance
	result = _builder.upgrade(CHAIR_A)
	_expect(result["ok"] and Economy.balance == balance - 190, "silla básica → ergonómica cobra $190: %s" % result["message"])
	_expect(_item_at(CHAIR_A)["id"] == "ergonomic_chair" and _item_at(CHAIR_A)["assigned_to"] == key
		and Staff.has_working_station(employee), "sigue sentado en su puesto")
	result = _builder.quote_upgrade(CHAIR_A)
	_expect(not result["ok"] and String(result["message"]).contains("no se puede mejorar"), "la ergonómica no se mejora: %s" % result["message"])
	# Lo que no se mejora.
	_expect(not _builder.quote_upgrade(Vector2i(5, 6))["ok"], "en el piso vacío no hay nada que mejorar")
	_builder.place("simple_desk", FREE_DESK, 2)
	result = _builder.quote_upgrade(FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("no tiene computadora"), "escritorio sin computadora: %s" % result["message"])
	_builder.place("small_plant", Vector2i(5, 6), 0)
	_expect(not _builder.quote_upgrade(Vector2i(5, 6))["ok"], "una planta no se mejora")
	# Sin dinero no se mejora.
	_builder.install_computer("basic_computer", FREE_DESK)
	Economy.charge(Economy.balance - 100, "Prueba")
	result = _builder.quote_upgrade(FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("No alcanza"), "sin dinero: %s" % result["message"])
	# La silla del CEO también se mejora.
	Economy.earn(10000, "Prueba")
	_expect(_builder.upgrade(Vector2i(1, 1))["ok"] and _item_at(Vector2i(1, 1))["assigned_to"] == "ceo", "la silla del CEO se mejora")
	_expect(RoomRules.function_problems(OfficeState.find_room("executive_office"), OfficeState.furniture).is_empty(),
		"la Oficina Ejecutiva sigue funcionando con la silla ergonómica")


func _check_monitor() -> void:
	_new_game()
	_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)
	_builder.place("simple_desk", FREE_DESK, 2)
	var result: Dictionary = _builder.quote_install_monitor("second_monitor", FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("no tiene computadora"), "sin computadora no va el monitor: %s" % result["message"])
	_expect(not _builder.quote_install_monitor("second_monitor", Vector2i(5, 6))["ok"], "el monitor va sobre un escritorio")
	_builder.install_computer("basic_computer", FREE_DESK)
	var balance: int = Economy.balance
	result = _builder.install_monitor("second_monitor", FREE_DESK)
	_expect(result["ok"] and Economy.balance == balance - 300 and _item_at(FREE_DESK)["monitor"] == "second_monitor", "monitor $300: %s" % result["message"])
	_expect(not _builder.quote_install_monitor("second_monitor", FREE_DESK)["ok"], "uno por escritorio")
	_expect(_near(Workstations.get_desk_bonus(_item_at(FREE_DESK)), 0.05), "básica + monitor = +5 %%")
	_expect(Bank.get_assets_value() >= FurnitureCatalog.get_resale("second_monitor") + FurnitureCatalog.get_resale("basic_computer"),
		"el monitor cuenta como bien")
	_expect(Embargo.get_value(_item_at(FREE_DESK)) == FurnitureCatalog.get_resale("simple_desk") + FurnitureCatalog.get_resale("basic_computer")
		+ FurnitureCatalog.get_resale("second_monitor"), "y en el embargo")
	# Vender: primero el monitor, después la computadora, al final el escritorio.
	balance = Economy.balance
	result = _builder.sell_furniture_at(FREE_DESK)
	_expect(result["ok"] and Economy.balance == balance + 150 and String(_item_at(FREE_DESK)["monitor"]).is_empty()
		and _item_at(FREE_DESK)["computer"] == "basic_computer", "se vende primero el monitor: %s" % result["message"])
	_builder.sell_furniture_at(FREE_DESK)
	_expect(String(_item_at(FREE_DESK)["computer"]).is_empty(), "después la computadora")
	_builder.sell_furniture_at(FREE_DESK)
	_expect(OfficeState.find_furniture_at(FREE_DESK) < 0, "y al final el escritorio")


func _check_production() -> void:
	_new_game()
	var employee: Dictionary = _station_a()
	var key: String = Staff.employee_key(employee["id"])
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], employee["id"])
	var project: Dictionary = {"team_id": team["id"]}
	# Una hora en que trabaja (está en su horario y no almuerza).
	var at: int = Staff.get_absolute_hour()
	while not Staff.is_expected(key, Staff.get_weekday_at(at), posmod(at, GameConstants.HOURS_PER_DAY)):
		at += 1
	var basic: float = float(Projects.get_workers(project, at)[0]["rate"])
	var basic_nominal: float = Projects.get_nominal_rate(project)
	_builder.upgrade(DESK_A)
	_builder.upgrade(DESK_A)
	var pro: float = float(Projects.get_workers(project, at)[0]["rate"])
	_expect(pro > basic and _near(pro / basic, 1.3), "la pro rinde 30 %% más que la básica: %.2f → %.2f" % [basic, pro])
	_expect(_near(Projects.get_nominal_rate(project) / basic_nominal, 1.3), "y el ritmo nominal también")
	_builder.install_monitor("second_monitor", DESK_A)
	var with_monitor: float = float(Projects.get_workers(project, at)[0]["rate"])
	_expect(_near(with_monitor / basic, 1.35), "con segundo monitor, 35 %% más: %.2f" % with_monitor)
	_expect(_near(Workstations.bonus_of(OfficeState.furniture, key), 0.35)
		and _near(Workstations.bonuses_by_owner(OfficeState.furniture)[key], 0.35), "bono del puesto 0.35")
	_expect(_near(Projects.get_nominal_rate({"team_id": Projects.CEO_TEAM}),
		Production.get_rate(String(StaffCatalog.get_production("ceo_level")), 100.0, 0.0)), "el CEO con su básica no cambia")


func _check_energy() -> void:
	_new_game()
	var basic: Dictionary = _station_a()
	var ergonomic: Dictionary = _station_b()
	var basic_key: String = Staff.employee_key(basic["id"])
	var ergonomic_key: String = Staff.employee_key(ergonomic["id"])
	_expect(Staff.get_work_energy(basic_key) == -6 and Staff.get_work_energy(ergonomic_key) == -4, "−6/h y −4/h")
	Staff.set_ceo_at_work(false)
	while not (Staff.is_expected_now(basic_key) and Staff.is_expected_now(ergonomic_key)):
		GameClock.fast_forward_hours(1)
	basic["energy"] = 80
	ergonomic["energy"] = 80
	GameClock.fast_forward_hours(3)
	# Tres horas: puede caer el almuerzo en medio (+4 para los dos).
	var lost_basic: int = 80 - int(basic["energy"])
	var lost_ergonomic: int = 80 - int(ergonomic["energy"])
	_expect(lost_basic > lost_ergonomic and lost_basic - lost_ergonomic >= 4,
		"con silla ergonómica la energía baja más lento: −%d contra −%d" % [lost_basic, lost_ergonomic])
	_expect(lost_basic == 18 or lost_basic == 8, "la básica −6 por hora: −%d" % lost_basic)
	_expect(lost_ergonomic == 12 or lost_ergonomic == 4, "la ergonómica −4 por hora: −%d" % lost_ergonomic)
	# Mejorar la silla en su lugar cambia el ritmo.
	_builder.upgrade(CHAIR_A)
	_expect(Staff.get_work_energy(basic_key) == -4, "silla mejorada: −4/h")


func _check_wide_desk() -> void:
	_new_game()
	var simple: Dictionary = _station_a()
	var wide: Dictionary = _station_b()
	_expect(Staff.has_working_station(wide), "el escritorio amplio forma un puesto")
	_expect(Staff.get_desk_mood(Staff.employee_key(wide["id"])) == 5 and Staff.get_desk_mood(Staff.employee_key(simple["id"])) == 0,
		"amplio +5, sencillo 0")
	var before: int = Staff.get_mood_target(simple)
	# El mismo puesto con escritorio amplio (cambiado a mano para comparar).
	var desk: Dictionary = _item_at(DESK_A)
	desk["id"] = "wide_desk"
	var after: int = Staff.get_mood_target(simple)
	desk["id"] = "simple_desk"
	_expect(after == mini(100, before + 5), "el escritorio amplio sube la meta de ánimo: %d → %d" % [before, after])


func _check_save() -> void:
	_new_game()
	_station_a()
	_builder.upgrade(DESK_A)
	_builder.install_monitor("second_monitor", DESK_A)
	_builder.upgrade(CHAIR_A)
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(_item_at(DESK_A)["computer"] == "mid_computer" and _item_at(DESK_A)["monitor"] == "second_monitor"
		and _item_at(CHAIR_A)["id"] == "ergonomic_chair", "se guardan computadora, monitor y silla")
	# Una partida de antes del hito 46 no tiene monitor.
	var state: Dictionary = OfficeState.export_state()
	for item: Dictionary in state["furniture"]:
		item.erase("monitor")
	OfficeState.import_state(state)
	_expect(String(_item_at(DESK_A)["monitor"]).is_empty() and _near(Workstations.get_desk_bonus(_item_at(DESK_A)), 0.15),
		"sin monitor guardado queda vacío")


func _check_ui() -> void:
	_new_game()
	_station_a()
	_builder.upgrade(DESK_A)
	_builder.install_monitor("second_monitor", DESK_A)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var monitors: Array[String] = []
	for view: Node in game.get_node("OfficeGrid").find_children("*", "", true, false):
		if view is FurnitureView and not (view as FurnitureView).monitor_id.is_empty():
			monitors.append((view as FurnitureView).computer_id)
	_expect(monitors.has("mid_computer"), "el monitor se dibuja junto a la computadora: %s" % [monitors])
	var texts: Array[String] = []
	for button: Node in game.find_children("*", "Button", true, false):
		texts.append((button as Button).text)
	_expect(texts.has("Mejorar"), "el modo construcción tiene Mejorar")
	_expect(texts.has("PC pro $2500") and texts.has("Monitor $300") and texts.has("Silla ergo. $250") and texts.has("Esc. amplio $350"),
		"y los muebles nuevos con su precio")
	# La herramienta Mejorar muestra el costo en la vista previa.
	var controller: BuildController = null
	for node: Node in game.find_children("*", "", true, false):
		if node is BuildController:
			controller = node
	controller.tool = BuildController.TOOL_UPGRADE
	controller.set("_pointer", Vector2(DESK_A))
	controller.call("_update_preview", false)
	_expect(bool(controller.get("_preview_ok")), "la vista previa de mejorar está bien")
	game.queue_free()
	await get_tree().process_frame
