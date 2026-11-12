# Prueba del hito 14: ofertas de contratos.
# Criterio: los puntos, plazos y pagos de cada oferta caen en los rangos de la tabla
# 13.4; aceptar un contrato con anticipo suma el 30% al saldo.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=contracts
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

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
	_check_new_game()
	_check_ranges()
	_check_salespeople()
	_check_expiry()
	_check_accept()
	_check_determinism_and_save()
	await _check_panel()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	# Sin objetivos guiados (hito 28): sus recompensas cambiarían el saldo y la reputación.
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Projects.set_seed(SEED)


# Avanza el reloj hasta la próxima hora de llegada de ofertas.
func _to_next_arrival() -> void:
	var arrival: int = int(ContractCatalog.get_offers("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)


# Un vendedor de mentira (sin sueldo) para probar su efecto en las ofertas.
func _add_fake_salesperson(employee_id: int) -> void:
	Staff.employees.append({"id": employee_id, "name": "Vendedor", "role": "salesperson", "level": "junior",
		"salary": 0, "schedule": StaffCatalog.get_role_schedule("salesperson"), "energy": 100, "mood": 70,
		"stress": 20, "paid_until": 0, "owed": 0})


func _check_catalog() -> void:
	var sizes: Array[String] = ["small", "medium", "large"]
	_expect(ContractCatalog.get_size_ids() == sizes, "tamaños: %s" % [ContractCatalog.get_size_ids()])
	_expect(ContractCatalog.get_size_range("small", "points") == Vector2i(150, 300)
		and ContractCatalog.get_days_range("small", 250) == Vector2i(17, 21)
		and ContractCatalog.get_size_range("large", "pay") == Vector2i(38000, 76000), "rangos de la tabla 13.4")
	_expect(ContractCatalog.get_type_ids().size() == 4, "cuatro tipos de proyecto")
	for type_id: String in ContractCatalog.get_type_ids():
		var split: Array[int] = ContractCatalog.get_split(type_id)
		_expect(split.size() == 3 and split[0] + split[1] + split[2] == 100, "%s reparte el 100%%: %s" % [type_id, split])
	_expect(float(ContractCatalog.get_offers("advance_ratio")) == 0.3, "anticipo del 30%")
	_expect(ProjectsPanel.stars(1.0) == "★☆☆☆☆" and ProjectsPanel.stars(4.4) == "★★★★☆", "estrellas")


func _check_new_game() -> void:
	_new_game()
	_expect(Projects.offers.size() == 1 and Projects.offers[0]["size"] == "small", "la partida empieza con una oferta pequeña")
	_expect(Projects.contracts.is_empty() and Projects.reputation == 1.0, "sin contratos y con 1 estrella")
	var small: Array[String] = ["small"]
	_expect(Projects.get_allowed_sizes() == small, "con 1 estrella solo llegan pequeños")
	_expect(Projects.get_contract_limit() == 1, "sin equipos, un contrato a la vez")


# Con 5 estrellas llegan los tres tamaños; cada oferta respeta su fila de la tabla.
func _check_ranges() -> void:
	_new_game()
	Projects.reputation = 5.0
	Company.stage = 1  # Startup: llegan medianos sin vendedor (hito 27).
	var seen: Dictionary[int, bool] = {}
	var sizes_seen: Dictionary[String, int] = {}
	var with_advance: int = 0
	for day: int in range(250):
		_to_next_arrival()
		_expect(Projects.offers.size() <= int(ContractCatalog.get_offers("max_offers")), "la bandeja no pasa del máximo")
		for offer: Dictionary in Projects.offers:
			if seen.has(offer["id"]):
				continue
			seen[offer["id"]] = true
			sizes_seen[offer["size"]] = sizes_seen.get(offer["size"], 0) + 1
			_check_offer(offer)
			if int(offer["advance"]) > 0:
				with_advance += 1
		# Se vacía la bandeja para que siempre haya lugar.
		for offer: Dictionary in Projects.offers.duplicate():
			Projects.reject(offer["id"])
	_expect(seen.size() > 80, "llegaron %d ofertas en 250 días" % seen.size())
	_expect(sizes_seen.get("small", 0) > sizes_seen.get("medium", 0) and sizes_seen.get("medium", 0) > sizes_seen.get("large", 0)
		and sizes_seen.get("large", 0) > 0, "los tamaños llegan según su peso: %s" % [sizes_seen])
	_expect(with_advance > seen.size() / 4 and with_advance < seen.size() * 3 / 4, "más o menos la mitad trae anticipo: %d de %d" % [
		with_advance, seen.size()])


func _check_offer(offer: Dictionary) -> void:
	var size: String = offer["size"]
	var points: Vector2i = ContractCatalog.get_size_range(size, "points")
	var total_for_days: int = offer["total_points"]
	var days: Vector2i = ContractCatalog.get_days_range(size, total_for_days)
	var pay: Vector2i = ContractCatalog.get_size_range(size, "pay")
	var total: int = offer["total_points"]
	var label: String = "oferta %d (%s)" % [offer["id"], size]
	_expect(total >= points.x and total <= points.y, "%s: %d puntos fuera de %s" % [label, total, points])
	_expect(int(offer["days"]) >= days.x and int(offer["days"]) <= days.y, "%s: %d días fuera de %s" % [label, offer["days"], days])
	_expect(int(offer["pay"]) >= pay.x and int(offer["pay"]) <= pay.y, "%s: pago %d fuera de %s" % [label, offer["pay"], pay])
	var parts: Dictionary = offer["points"]
	_expect(int(parts["design"]) + int(parts["programming"]) + int(parts["testing"]) == total, "%s: las fases suman el total" % label)
	var split: Array[int] = ContractCatalog.get_split(offer["type"])
	_expect(absi(int(parts["programming"]) - roundi(total * split[1] / 100.0)) <= 1, "%s: reparto del tipo" % label)
	var advance: int = offer["advance"]
	_expect(advance == 0 or advance == roundi(int(offer["pay"]) * 0.3), "%s: anticipo %d" % [label, advance])
	_expect(int(offer["expires_day"]) == int(offer["arrived_day"]) + 5, "%s: caduca a los 5 días" % label)
	_expect(ContractCatalog.get_clients().has(offer["client"]), "%s: cliente de la lista" % label)


# Con vendedores llegan más ofertas y, aun con 1 estrella, también medianas.
func _check_salespeople() -> void:
	_new_game()
	var arrivals_alone: int = _count_arrivals(40)
	_new_game()
	_add_fake_salesperson(900)
	_add_fake_salesperson(901)
	var allowed: Array[String] = ["small", "medium"]
	_expect(Projects.get_allowed_sizes() == allowed, "con un vendedor llegan medianos")
	var arrivals_with: int = _count_arrivals(40)
	_expect(arrivals_with >= 40, "con dos vendedores llega al menos una por día: %d" % arrivals_with)
	_expect(arrivals_alone < arrivals_with and arrivals_alone > 5, "sin vendedores llegan menos: %d contra %d" % [arrivals_alone, arrivals_with])
	Staff.employees.clear()


func _count_arrivals(days: int) -> int:
	var count: int = 0
	for day: int in range(days):
		for offer: Dictionary in Projects.offers.duplicate():
			Projects.reject(offer["id"])
		_to_next_arrival()
		count += Projects.offers.size()
	return count


func _check_expiry() -> void:
	_new_game()
	var first: Dictionary = Projects.offers[0]
	_expect(Projects.offer_days_left(first) == 5, "la primera oferta caduca en 5 días")
	# La partida empieza a las 8:00: la primera llamada llega a las 9:00 del día 1.
	for day: int in range(5):
		_to_next_arrival()
	_expect(not Projects.get_offer(first["id"]).is_empty() and Projects.offer_days_left(first) == 1, "el día 5 sigue")
	_to_next_arrival()
	_expect(Projects.get_offer(first["id"]).is_empty(), "el día 6 a las 9:00 caducó")


func _check_accept() -> void:
	_new_game()
	Projects.reputation = 5.0
	Company.stage = 1  # Startup: llegan medianos sin vendedor (hito 27).
	# Busca una oferta con anticipo y otra sin anticipo.
	var with_advance: Dictionary = {}
	var without: Dictionary = {}
	for day: int in range(60):
		for offer: Dictionary in Projects.offers:
			if offer["size"] == "small" and int(offer["advance"]) > 0 and with_advance.is_empty():
				with_advance = offer
			elif offer["size"] == "small" and int(offer["advance"]) == 0 and without.is_empty():
				without = offer
		if not with_advance.is_empty() and not without.is_empty() and Projects.offer_days_left(with_advance) > 0 \
				and Projects.offer_days_left(without) > 0:
			break
		with_advance = {}
		without = {}
		_to_next_arrival()
	_expect(not with_advance.is_empty() and not without.is_empty(), "hay ofertas con y sin anticipo")
	var before: int = Economy.balance
	var result: Dictionary = Projects.accept(with_advance["id"])
	var expected: int = roundi(int(with_advance["pay"]) * 0.3)
	_expect(result["ok"] and Economy.balance - before == expected, "aceptar con anticipo suma el 30%%: %d de %d" % [
		Economy.balance - before, with_advance["pay"]])
	_expect(Economy.movements[-1]["concept"] == Projects.CONCEPT_ADVANCE, "movimiento de anticipo")
	_expect(Projects.get_offer(with_advance["id"]).is_empty() and Projects.contracts.size() == 1, "pasa a contratos en curso")
	var contract: Dictionary = Projects.contracts[0]
	_expect(int(contract["deadline_day"]) == GameClock.get_day_count() + int(contract["days"])
		and Projects.contract_days_left(contract) == int(contract["days"]), "el plazo corre desde hoy")
	_expect(contract["progress"] == {"design": 0.0, "programming": 0.0, "testing": 0.0}, "sin avance")
	# Tope: uno por equipo, y sin equipos uno solo.
	var problem: String = Projects.accept_problem(without["id"])
	_expect(problem.contains("tope es 1"), "no se acepta un segundo contrato: %s" % problem)
	before = Economy.balance
	_expect(not Projects.accept(without["id"])["ok"] and Economy.balance == before, "el segundo no cobra nada")
	# Sin anticipo no entra dinero.
	Projects.contracts.clear()
	_expect(Projects.accept(without["id"])["ok"] and Economy.balance == before, "aceptar sin anticipo no cobra")
	# Los grandes exigen Sala de reuniones.
	Projects.contracts.clear()
	var large: Dictionary = {}
	for day: int in range(120):
		for offer: Dictionary in Projects.offers:
			if offer["size"] == "large":
				large = offer
		if not large.is_empty():
			break
		_to_next_arrival()
	_expect(not large.is_empty(), "llegó una oferta grande")
	_expect(Projects.accept_problem(large["id"]).contains("Sala de reuniones"), "un grande exige Sala de reuniones: %s" % Projects.accept_problem(large["id"]))
	# Rechazar la quita.
	var count: int = Projects.offers.size()
	_expect(Projects.reject(large["id"]) and Projects.offers.size() == count - 1 and not Projects.reject(large["id"]), "rechazar")


func _check_determinism_and_save() -> void:
	_new_game()
	for day: int in range(10):
		_to_next_arrival()
	var first_run: String = JSON.stringify(Projects.offers)
	_new_game()
	for day: int in range(10):
		_to_next_arrival()
	_expect(JSON.stringify(Projects.offers) == first_run, "con la misma semilla llegan las mismas ofertas")
	Projects.accept(Projects.offers[0]["id"])
	var before: String = JSON.stringify(Projects.export_state())
	_expect(SaveManager.save_game("slot_4"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_4"), "cargar")
	_expect(JSON.stringify(Projects.export_state()) == before, "los proyectos vuelven igual")
	# Lo que llega después también es igual tras cargar.
	_to_next_arrival()
	var after_load: String = JSON.stringify(Projects.offers)
	SaveManager.load_game("slot_4")
	_to_next_arrival()
	_expect(JSON.stringify(Projects.offers) == after_load, "cargar no cambia lo que iba a llegar")
	Projects.import_state({})
	_expect(Projects.offers.is_empty() and Projects.contracts.is_empty() and Projects.reputation == 1.0, "partida vieja sin proyectos")


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	var build_panel: BuildPanel = game.get_node("BuildPanel")
	_expect(panel.get_open_button().get_parent() == build_panel.get_menu_bar() and panel.get_open_button().text == "Proyectos (1)",
		"botón en la barra con las ofertas: %s" % panel.get_open_button().text)
	await _click(staff_panel.get_open_button())
	await _click(panel.get_open_button())
	_expect(panel.is_open() and not staff_panel.is_open() and not GameClock.is_paused, "Proyectos se abre, cierra Personal y no pausa")
	var offer: Dictionary = Projects.offers[0]
	var text: String = panel.get_list_text()
	for expected: String in ["Reputación ★☆☆☆☆", "En curso (0 de 1)", "Ofertas (1)", Projects.describe_title(offer),
			Projects.describe_points(offer), "Pago %s" % MoneyFormat.format(offer["pay"]), "Atraso −5% por día (máx. 50%)", "caduca en 5 días"]:
		_expect(text.contains(expected), "el panel muestra «%s»: %s" % [expected, text])
	await _click(panel.get_accept_button(offer["id"]))
	_expect(Projects.contracts.size() == 1, "aceptar desde el panel")
	_expect(panel.get_status_text().begins_with("Contrato aceptado"), "aviso: %s" % panel.get_status_text())
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("En curso (1 de 1)") and panel.get_list_text().contains("quedan %d días" % offer["days"]),
		"contrato en curso: %s" % panel.get_list_text())
	_to_next_arrival()
	_to_next_arrival()
	await get_tree().process_frame
	if not Projects.offers.is_empty():
		var other: Dictionary = Projects.offers[0]
		_expect(panel.get_accept_button(other["id"]).disabled and panel.get_list_text().contains("tope es 1"),
			"con el tope lleno no se acepta otra")
		await _click(panel.get_reject_button(other["id"]))
		_expect(Projects.get_offer(other["id"]).is_empty(), "rechazar desde el panel")
	await _click(staff_panel.get_open_button())
	_expect(staff_panel.is_open() and not panel.is_open(), "Personal cierra Proyectos")
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
