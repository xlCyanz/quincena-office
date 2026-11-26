# Tienda e inventario: comprar deja los muebles en el inventario, colocarlos desde ahí no cuesta, Guardar
# los devuelve, el inventario se guarda con la partida y la Tienda se abre a pantalla completa.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=inventory
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261126
const OPEN_CELL := Vector2i(3, 3)
const DESK := Vector2i(4, 4)
const CHAIR := Vector2i(4, 5)
const SLOT: String = "slot_4"

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_buy()
	_check_place()
	_check_store()
	_check_save()
	await _check_ui()
	DirAccess.remove_absolute(SaveManager.save_dir.path_join(SLOT + ".json"))
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)


func _check_buy() -> void:
	_new_game()
	_expect(OfficeState.inventory.is_empty(), "una partida nueva empieza con el inventario vacío")
	var money: int = Economy.balance
	var price: int = FurnitureCatalog.get_price("simple_desk")
	var result: Dictionary = _builder.buy("simple_desk", 3)
	_expect(result["ok"] and Economy.balance == money - 3 * price, "comprar 3 escritorios cobra 3 precios: %d → %d" % [
		money, Economy.balance])
	_expect(OfficeState.get_stock("simple_desk") == 3, "los 3 quedan en el inventario: %d" % OfficeState.get_stock("simple_desk"))
	var assets: int = Bank.get_assets_value()
	_builder.buy("small_plant", 1)
	_expect(Bank.get_assets_value() == assets + FurnitureCatalog.get_resale("small_plant"),
		"lo del inventario cuenta en los activos por su reventa")
	_expect(not _builder.buy("nothing", 1)["ok"] and not _builder.buy("simple_desk", 0)["ok"], "no se compra lo que no existe ni 0")
	Economy.spend(Economy.balance, "Prueba")
	money = Economy.balance
	result = _builder.buy("simple_desk", 1)
	_expect(not result["ok"] and Economy.balance == money and OfficeState.get_stock("simple_desk") == 3,
		"sin dinero no se compra ni cambia el inventario")


func _check_place() -> void:
	_new_game()
	Economy.earn(100000, "Prueba")
	_expect(_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)["ok"], "marcar el Área de trabajo")
	_builder.buy("simple_desk", 1)
	_builder.buy("basic_computer", 1)
	_builder.buy("basic_chair", 1)
	var money: int = Economy.balance
	var quote: Dictionary = _builder.quote_place("simple_desk", DESK, 2)
	_expect(quote["ok"] and quote["cost"] == 0 and String(quote["message"]).contains("del inventario"),
		"colocar desde el inventario no cuesta: %s" % quote["message"])
	_expect(_builder.place("simple_desk", DESK, 2)["ok"] and OfficeState.get_stock("simple_desk") == 0, "el escritorio sale del inventario")
	_expect(_builder.install_computer("basic_computer", DESK)["ok"] and OfficeState.get_stock("basic_computer") == 0,
		"la computadora se instala desde el inventario")
	_expect(_builder.place("basic_chair", CHAIR, 0)["ok"], "la silla se pone desde el inventario")
	_expect(Economy.balance == money, "armar el puesto con lo comprado no cobró nada: %d → %d" % [money, Economy.balance])
	quote = _builder.quote_place("simple_desk", Vector2i(6, 1), 0)
	_expect(quote["cost"] == FurnitureCatalog.get_price("simple_desk") and not quote.has("stock"),
		"sin inventario, colocar cobra el precio")


func _check_store() -> void:
	# Sigue con el puesto de _check_place.
	var money: int = Economy.balance
	var result: Dictionary = _builder.store_furniture_at(DESK)
	_expect(result["ok"] and OfficeState.get_stock("basic_computer") == 1 and Economy.balance == money,
		"Guardar empieza por la computadora y no devuelve dinero: %s" % result["message"])
	_expect(_builder.install_computer("basic_computer", DESK)["ok"], "volver a instalar la computadora")
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty() and not _builder.store_furniture_at(DESK)["ok"], "no se guarda el puesto de un empleado")
	if not employee.is_empty():
		Staff.fire(int(employee["id"]))
	_expect(_builder.store_furniture_at(CHAIR)["ok"] and OfficeState.get_stock("basic_chair") == 1, "la silla vuelve al inventario")
	_builder.buy("small_plant", 1)
	var plant: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in [Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 2), Vector2i(5, 1), Vector2i(1, 2)]:
		if _builder.quote_place("small_plant", cell, 0)["ok"]:
			plant = cell
			break
	result = _builder.place("small_plant", plant, 0)
	_expect(result["ok"], "poner la planta: %s" % result["message"])
	_expect(_builder.store_furniture_at(plant)["ok"] and OfficeState.get_stock("small_plant") == 1
		and OfficeState.find_furniture_at(plant) < 0, "la planta vuelve al inventario y deja la casilla libre")
	var ceo_chair: int = OfficeState.furniture.find_custom(func(item: Dictionary) -> bool: return item["assigned_to"] == "ceo")
	if ceo_chair >= 0:
		var cell: Vector2i = OfficeState.furniture[ceo_chair]["cell"]
		result = _builder.store_furniture_at(cell, int(OfficeState.furniture[ceo_chair]["quarter"]))
		_expect(not result["ok"] and String(result["message"]).contains("guardar"), "la silla del CEO no se guarda: %s" % result["message"])


func _check_save() -> void:
	var before: Dictionary = OfficeState.inventory.duplicate()
	_expect(SaveManager.save_game(SLOT), "guardar la partida")
	SaveManager.new_game()
	_expect(OfficeState.inventory.is_empty(), "la partida nueva no trae el inventario anterior")
	_expect(SaveManager.load_game(SLOT) and OfficeState.inventory == before, "cargar devuelve el inventario: %s" % OfficeState.inventory)
	var state: Dictionary = OfficeState.export_state()
	state["inventory"] = {"simple_desk": 2, "nothing": 4, "small_plant": 0}
	OfficeState.import_state(state)
	_expect(OfficeState.inventory == {"simple_desk": 2}, "al cargar se ignoran ids desconocidos y cantidades en 0: %s" % OfficeState.inventory)


func _check_ui() -> void:
	_new_game()
	_expect(SpriteLibrary.get_furniture_icon("nothing") == null, "lo que no tiene sprite no tiene icono")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var build: BuildPanel = game.get_node("BuildPanel")
	_expect(build.get_button_toward("simple_desk") == build.get_shop_button() and build.get_shop_button().is_visible_in_tree(),
		"la Tienda está en la barra del mapa")
	build.set_build_mode(true)
	await get_tree().process_frame
	_expect(build.get_section() == BuildPanel.SECTION_FURNITURE and build.get_tool_button("simple_desk") == null,
		"el inventario vacío no tiene tarjetas")
	build.set_build_mode(false)
	build.get_shop_button().pressed.emit()
	await get_tree().process_frame
	var shop: ShopScreen = build.get_shop()
	_expect(build.is_shop_open() and shop.get_card("simple_desk") != null, "Tienda abre desde el mapa la pantalla con cada mueble")
	shop.set_category("decor")
	await get_tree().process_frame
	_expect(not shop.get_card("simple_desk").is_visible_in_tree() and shop.get_card("small_plant").is_visible_in_tree(),
		"la categoría filtra las tarjetas")
	shop.get_card("small_plant").pressed.emit()
	shop.set_count(2)
	var money: int = Economy.balance
	shop.get_buy_button().pressed.emit()
	await get_tree().process_frame
	_expect(OfficeState.get_stock("small_plant") == 2 and Economy.balance == money - 2 * FurnitureCatalog.get_price("small_plant"),
		"Comprar en la Tienda cobra y suma al inventario")
	_expect(shop.get_message().contains("inventario"), "la Tienda dice dónde quedó: %s" % shop.get_message())
	Economy.spend(Economy.balance, "Prueba")
	await get_tree().process_frame
	_expect(shop.get_buy_button().disabled, "sin dinero el botón Comprar se apaga")
	var main: Node = game
	_expect(main.call("handle_escape") == "shop" and not build.is_shop_open() and not build.is_build_mode(),
		"Esc cierra la Tienda y vuelve al mapa")
	_expect(build.get_button_toward("small_plant") == build.get_open_button(), "con la planta comprada, el camino es Construir")
	build.set_build_mode(true)
	build.select_tool("small_plant")
	await get_tree().process_frame
	_expect(build.get_selected_tool() == "small_plant" and build.get_tool_button("small_plant").is_visible_in_tree(),
		"la planta comprada aparece en el inventario")
	build.set_build_mode(false)
	game.queue_free()
	await get_tree().process_frame
