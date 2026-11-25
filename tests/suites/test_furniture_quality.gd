# Calidades de muebles: la computadora pro rinde más que la básica, la silla ergonómica gasta
# menos energía y mejorar cobra la diferencia.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=furniture_quality
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261146
const OPEN_CELL := Vector2i(3, 3)
## Puesto A: escritorio largo (su segunda casilla es DESK_A) con la silla al sur.
const DESK_A := Vector2i(4, 4)
const CHAIR_A := Vector2i(4, 5)
## Puesto B: otro escritorio sencillo con una silla ergonómica al sur.
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
	await _check_save()
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


# Área de trabajo con el puesto A (escritorio largo, básica) y un programador sentado en él.
func _station_a() -> Dictionary:
	_expect(_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)["ok"], "marcar el Área de trabajo")
	_expect(_builder.place("long_desk", DESK_A - Vector2i(1, 0), 2)["ok"], "escritorio A")
	_expect(_builder.install_computer("basic_computer", DESK_A)["ok"], "computadora A")
	_expect(_builder.place("basic_chair", CHAIR_A, 0)["ok"], "silla A")
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratar un programador")
	return employee


# Puesto B: escritorio sencillo con computadora básica y silla ergonómica, y otro programador.
func _station_b() -> Dictionary:
	_expect(_builder.place("simple_desk", DESK_B, 2)["ok"], "escritorio B")
	_expect(_builder.install_computer("basic_computer", DESK_B)["ok"], "computadora B")
	_expect(_builder.place("ergonomic_chair", CHAIR_B, 0)["ok"], "silla ergonómica")
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratar el segundo programador")
	return employee


func _item_at(cell: Vector2i) -> Dictionary:
	return OfficeState.furniture[OfficeState.find_furniture_at(cell)]


func _check_catalog() -> void:
	var prices: Dictionary[String, int] = {"pro_computer": 2500, "second_monitor": 300, "ergonomic_chair": 250, "long_desk": 350}
	for id: String in prices:
		_expect(FurnitureCatalog.get_price(id) == prices[id], "%s cuesta %s" % [id, MoneyFormat.format(prices[id])])
	_expect(_near(FurnitureCatalog.get_production_bonus("basic_computer"), 0.0)
		and _near(FurnitureCatalog.get_production_bonus("pro_computer"), 0.3)
		and _near(FurnitureCatalog.get_production_bonus("second_monitor"), 0.05), "básica +0, pro +30 %%, pantalla extra +5 %%")
	_expect(FurnitureCatalog.get_item("mid_computer").is_empty(), "la computadora media ya no existe")
	_expect(FurnitureCatalog.get_max_monitors("long_desk") == 2 and FurnitureCatalog.get_max_monitors("simple_desk") == 0
		and FurnitureCatalog.get_max_monitors("executive_desk") == 0, "solo el escritorio largo admite pantallas extra, 2")
	_expect(FurnitureCatalog.allows_monitors("pro_computer") and not FurnitureCatalog.allows_monitors("basic_computer"),
		"y solo con computadora pro")
	_expect(FurnitureCatalog.get_footprint("long_desk", Vector2i.ZERO, 0).size() == 2
		and bool(FurnitureCatalog.get_item("long_desk")["accepts_computer"]), "el largo ocupa 2 casillas y lleva computadora")
	_expect(_near(Production.get_computer_bonus("pro_computer"), 0.3), "Production lee el bono de la pro")
	_expect(FurnitureCatalog.get_upgrade("basic_computer") == "pro_computer"
		and FurnitureCatalog.get_upgrade("pro_computer").is_empty() and FurnitureCatalog.get_upgrade("basic_chair") == "ergonomic_chair"
		and FurnitureCatalog.get_upgrade("ergonomic_chair").is_empty(), "escalera de calidades")
	_expect(FurnitureCatalog.is_monitor("second_monitor") and not FurnitureCatalog.is_monitor("pro_computer"), "el monitor es monitor")
	_expect(FurnitureCatalog.get_work_energy("ergonomic_chair") == -4 and FurnitureCatalog.get_work_energy("basic_chair") == 0,
		"la ergonómica −4/h; la básica usa la de data/staff.json")
	_expect(FurnitureCatalog.get_work_energy("mesh_chair") == -5 and FurnitureCatalog.get_work_energy("manager_chair") == -4
		and FurnitureCatalog.get_work_energy("executive_chair") == -3 and FurnitureCatalog.get_work_energy("visitor_chair") == 0
		and FurnitureCatalog.get_work_energy("stool") == 0, "malla −5/h, gerencial −4/h, ejecutivo −3/h; visita y taburete la normal")
	_expect(_near(FurnitureCatalog.get_ambiance_points("executive_chair"), 2.0) and _near(FurnitureCatalog.get_ambiance_points("manager_chair"), 1.0),
		"el sillón ejecutivo y la gerencial dan ambiente")
	var seats_ok: bool = true
	for chair: String in ["mesh_chair", "manager_chair", "executive_chair", "visitor_chair", "stool"]:
		seats_ok = seats_ok and bool(FurnitureCatalog.get_item(chair).get("is_seat", false))
	_expect(seats_ok, "las sillas nuevas son asientos")
	_expect(FurnitureCatalog.get_item("wide_desk").is_empty() and not FurnitureCatalog.get_ids().has("wide_desk"),
		"el escritorio amplio ya no existe")


func _check_upgrade() -> void:
	_new_game()
	var employee: Dictionary = _station_a()
	var key: String = Staff.employee_key(employee["id"])
	# El puesto está ocupado: no se vende, pero sí se mejora.
	_expect(not _builder.quote_sell_furniture_at(DESK_A)["ok"], "el puesto ocupado no se vende")
	var balance: int = Economy.balance
	var result: Dictionary = _builder.upgrade(DESK_A)
	_expect(result["ok"] and Economy.balance == balance - 2000, "básica → pro cobra la diferencia ($2,000): %s" % result["message"])
	_expect(_item_at(DESK_A)["computer"] == "pro_computer" and Workstations.computer_of(OfficeState.furniture, key) == "pro_computer",
		"la computadora del puesto pasa a pro")
	_expect(String(result["message"]).contains("Computadora pro") and String(result["message"]).contains("$2000"), result["message"])
	result = _builder.quote_upgrade(DESK_A)
	_expect(not result["ok"] and String(result["message"]).contains("la mejor"), "la pro no se mejora: %s" % result["message"])
	balance = Economy.balance
	result = _builder.upgrade(CHAIR_A)
	_expect(result["ok"] and Economy.balance == balance - 190, "silla básica → ergonómica cobra $190: %s" % result["message"])
	_expect(_item_at(CHAIR_A)["id"] == "ergonomic_chair" and _item_at(CHAIR_A)["assigned_to"] == key
		and Staff.has_working_station(employee), "sigue sentado en su puesto")
	result = _builder.quote_upgrade(CHAIR_A)
	_expect(not result["ok"] and String(result["message"]).contains("no se puede mejorar"), "la ergonómica no se mejora: %s" % result["message"])
	_expect(not _builder.quote_upgrade(Vector2i(5, 6))["ok"], "en el piso vacío no hay nada que mejorar")
	_builder.place("simple_desk", FREE_DESK, 2)
	result = _builder.quote_upgrade(FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("no tiene computadora"), "escritorio sin computadora: %s" % result["message"])
	_builder.place("small_plant", Vector2i(5, 6), 0)
	_expect(not _builder.quote_upgrade(Vector2i(5, 6))["ok"], "una planta no se mejora")
	_builder.install_computer("basic_computer", FREE_DESK)
	Economy.charge(Economy.balance - 100, "Prueba")
	result = _builder.quote_upgrade(FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("No alcanza"), "sin dinero: %s" % result["message"])
	Economy.earn(10000, "Prueba")
	_expect(_builder.upgrade(Vector2i(1, 1))["ok"] and _item_at(Vector2i(1, 1))["assigned_to"] == "ceo", "la silla del CEO se mejora")
	_expect(RoomRules.function_problems(OfficeState.find_room("executive_office"), OfficeState.furniture).is_empty(),
		"la Oficina Ejecutiva sigue funcionando con la silla ergonómica")


func _check_monitor() -> void:
	_new_game()
	_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)
	_builder.place("simple_desk", Vector2i(5, 3), 2)
	_builder.install_computer("pro_computer", Vector2i(5, 3))
	var result: Dictionary = _builder.quote_install_monitor("second_monitor", Vector2i(5, 3))
	_expect(not result["ok"] and String(result["message"]).contains("escritorio largo"), "en el sencillo no cabe: %s" % result["message"])
	_expect(not _builder.quote_install_monitor("second_monitor", Vector2i(5, 6))["ok"], "la pantalla va sobre un escritorio")
	# En el largo: con computadora, y que sea pro.
	_expect(_builder.place("long_desk", FREE_DESK - Vector2i(1, 0), 2)["ok"], "escritorio largo")
	result = _builder.quote_install_monitor("second_monitor", FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("no tiene computadora"), "sin computadora no va: %s" % result["message"])
	_builder.install_computer("basic_computer", FREE_DESK)
	result = _builder.quote_install_monitor("second_monitor", FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("computadora pro"), "con la básica no va: %s" % result["message"])
	_expect(_builder.upgrade(FREE_DESK)["ok"], "mejorar a pro")
	var balance: int = Economy.balance
	result = _builder.install_monitor("second_monitor", FREE_DESK)
	_expect(result["ok"] and Economy.balance == balance - 300 and _item_at(FREE_DESK)["monitor"] == "second_monitor"
		and FurnitureCatalog.get_monitor_count(_item_at(FREE_DESK)) == 1, "pantalla extra $300: %s" % result["message"])
	_expect(_near(Workstations.get_desk_bonus(_item_at(FREE_DESK)), 0.35), "pro + 1 pantalla = +35 %%")
	_expect(_builder.install_monitor("second_monitor", FREE_DESK)["ok"] and FurnitureCatalog.get_monitor_count(_item_at(FREE_DESK)) == 2,
		"la segunda pantalla extra")
	result = _builder.quote_install_monitor("second_monitor", FREE_DESK)
	_expect(not result["ok"] and String(result["message"]).contains("todas sus pantallas"), "hasta dos: %s" % result["message"])
	_expect(_near(Workstations.get_desk_bonus(_item_at(FREE_DESK)), 0.4), "pro + 2 pantallas = +40 %%")
	_expect(Embargo.get_value(_item_at(FREE_DESK)) == FurnitureCatalog.get_resale("long_desk") + FurnitureCatalog.get_resale("pro_computer")
		+ 2 * FurnitureCatalog.get_resale("second_monitor"), "las dos cuentan en el embargo")
	_expect(Bank.get_assets_value() >= 2 * FurnitureCatalog.get_resale("second_monitor") + FurnitureCatalog.get_resale("pro_computer"),
		"y como bienes")
	# Vender: primero las pantallas, de a una; después la computadora y al final el escritorio.
	balance = Economy.balance
	result = _builder.sell_furniture_at(FREE_DESK)
	_expect(result["ok"] and Economy.balance == balance + 150 and FurnitureCatalog.get_monitor_count(_item_at(FREE_DESK)) == 1
		and _item_at(FREE_DESK)["computer"] == "pro_computer", "se vende primero una pantalla: %s" % result["message"])
	_builder.sell_furniture_at(FREE_DESK)
	_expect(String(_item_at(FREE_DESK)["monitor"]).is_empty() and FurnitureCatalog.get_monitor_count(_item_at(FREE_DESK)) == 0
		and _item_at(FREE_DESK)["computer"] == "pro_computer", "después la otra")
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
	# Una hora en que trabaja (en su horario y fuera del almuerzo).
	var at: int = Staff.get_absolute_hour()
	while not Staff.is_expected(key, Staff.get_weekday_at(at), posmod(at, GameConstants.HOURS_PER_DAY)):
		at += 1
	var basic: float = float(Projects.get_workers(project, at)[0]["rate"])
	var basic_nominal: float = Projects.get_nominal_rate(project)
	_builder.upgrade(DESK_A)
	var pro: float = float(Projects.get_workers(project, at)[0]["rate"])
	_expect(pro > basic and _near(pro / basic, 1.3), "la pro rinde 30 %% más que la básica: %.2f → %.2f" % [basic, pro])
	_expect(_near(Projects.get_nominal_rate(project) / basic_nominal, 1.3), "y el ritmo nominal también")
	_builder.install_monitor("second_monitor", DESK_A)
	var with_monitor: float = float(Projects.get_workers(project, at)[0]["rate"])
	_expect(_near(with_monitor / basic, 1.35), "con una pantalla extra, 35 %% más: %.2f" % with_monitor)
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
	_builder.upgrade(CHAIR_A)
	_expect(Staff.get_work_energy(basic_key) == -4, "silla mejorada: −4/h")


# El escritorio amplio ya no existe: una partida vieja lo carga como sencillo en la casilla
# con la silla delante, y el puesto sigue funcionando.
func _check_wide_desk() -> void:
	_new_game()
	var employee: Dictionary = _station_a()
	var state: Dictionary = OfficeState.export_state()
	for item: Dictionary in state["furniture"]:
		if String(item["id"]) == "long_desk" and int(item["cell"][0]) == DESK_A.x - 1 and int(item["cell"][1]) == DESK_A.y:
			# Como estaba guardado: amplio de 2 casillas, con la silla delante de la segunda.
			item["id"] = "wide_desk"
	OfficeState.import_state(state)
	var desk: int = OfficeState.find_furniture_at(DESK_A)
	_expect(desk >= 0 and String(OfficeState.furniture[desk]["id"]) == "simple_desk"
		and not String(OfficeState.furniture[desk]["computer"]).is_empty(), "el amplio guardado pasa a sencillo con su computadora")
	_expect(OfficeState.find_furniture_at(DESK_A - Vector2i(1, 0)) < 0, "la otra casilla queda libre")
	_expect(Staff.has_working_station(employee), "el puesto sigue funcionando")
	for item: Dictionary in OfficeState.furniture:
		_expect(String(item["id"]) != "wide_desk", "no queda ningún escritorio amplio")


func _check_save() -> void:
	_new_game()
	_station_a()
	_builder.upgrade(DESK_A)
	_builder.install_monitor("second_monitor", DESK_A)
	_builder.upgrade(CHAIR_A)
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_builder.install_monitor("second_monitor", DESK_A)
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar con dos pantallas")
	_expect(_item_at(DESK_A)["computer"] == "pro_computer" and _item_at(DESK_A)["monitor"] == "second_monitor"
		and FurnitureCatalog.get_monitor_count(_item_at(DESK_A)) == 2
		and _item_at(CHAIR_A)["id"] == "ergonomic_chair", "se guardan computadora, pantallas y silla")
	# Una partida vieja no tiene monitor.
	var state: Dictionary = OfficeState.export_state()
	for item: Dictionary in state["furniture"]:
		item.erase("monitor")
		item.erase("monitors")
	OfficeState.import_state(state)
	_expect(String(_item_at(DESK_A)["monitor"]).is_empty() and _near(Workstations.get_desk_bonus(_item_at(DESK_A)), 0.3),
		"sin monitor guardado queda vacío")
	# Partida vieja: computadora media y un monitor sobre un escritorio sencillo.
	_new_game()
	_builder.place("simple_desk", FREE_DESK, 2)
	_builder.install_computer("basic_computer", FREE_DESK)
	state = OfficeState.export_state()
	for item: Dictionary in state["furniture"]:
		if int(item["cell"][0]) == FREE_DESK.x and int(item["cell"][1]) == FREE_DESK.y:
			item["computer"] = "mid_computer"
			item["monitor"] = "second_monitor"
			item.erase("monitors")
	var before: int = Economy.balance
	OfficeState.import_state(state)
	await get_tree().process_frame
	_expect(_item_at(FREE_DESK)["computer"] == "basic_computer", "la computadora media pasa a básica")
	_expect(String(_item_at(FREE_DESK)["monitor"]).is_empty() and Economy.balance == before + 300,
		"el monitor que ya no cabe se quita y se devuelve: %d → %d" % [before, Economy.balance])


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
	_expect(monitors.has("pro_computer"), "el escritorio con pantalla extra se dibuja: %s" % [monitors])
	var texts: Array[String] = []
	for button: Node in game.find_children("*", "Button", true, false):
		texts.append((button as Button).text)
	_expect(texts.has("Mejorar"), "el modo construcción tiene Mejorar")
	_expect(texts.has("PC pro $2500") and texts.has("Pantalla $300") and texts.has("Silla ergo. $250") and texts.has("Esc. largo $350")
		and not texts.has("Esc. amplio $350") and not texts.has("PC media $1200"),
		"y los muebles nuevos con su precio")
	var controller: BuildController = null
	for node: Node in game.find_children("*", "", true, false):
		if node is BuildController:
			controller = node
	controller.tool = BuildController.TOOL_UPGRADE
	controller.set("_pointer", Vector2(CHAIR_A))
	controller.call("_update_preview", false)
	_expect(bool(controller.get("_preview_ok")), "la vista previa de mejorar está bien")
	game.queue_free()
	await get_tree().process_frame
