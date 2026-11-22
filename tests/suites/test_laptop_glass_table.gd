# Laptop y mesa de reuniones de vidrio: la laptop solo va sobre el escritorio ejecutivo; la mesa de
# vidrio hace funcionar la Sala de reuniones como la de madera y suma ambiente.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=laptop_glass_table
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const SEED: int = 20261170
## Zona abierta del local inicial (fuera de la Oficina Ejecutiva).
const OPEN_CELL := Vector2i(3, 3)
const TABLE_CELL := Vector2i(3, 4)
const SLOT: String = "slot_5"

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_laptop()
	_check_glass_table()
	_check_sprites()
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
	Economy.earn(100000, "Prueba")


func _item_at(cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	return {} if index < 0 else OfficeState.furniture[index]


func _check_catalog() -> void:
	var laptop: Dictionary = FurnitureCatalog.get_item("laptop")
	_expect(FurnitureCatalog.get_price("laptop") == 1800 and bool(laptop["on_desk"]) and laptop["category"] == "work",
		"laptop: computadora de $1,800 de la categoría Trabajo")
	_expect(is_equal_approx(FurnitureCatalog.get_production_bonus("laptop"), 0.2)
		and is_equal_approx(Production.get_computer_bonus("laptop"), 0.2), "la laptop suma +20 %")
	_expect(FurnitureCatalog.fits_desk("laptop", "executive_desk") and not FurnitureCatalog.fits_desk("laptop", "simple_desk")
		and not FurnitureCatalog.fits_desk("laptop", "long_desk"), "la laptop solo cabe en el escritorio ejecutivo")
	_expect(FurnitureCatalog.fits_desk("basic_computer", "simple_desk") and FurnitureCatalog.fits_desk("pro_computer", "executive_desk"),
		"las otras computadoras caben en cualquiera")
	_expect(FurnitureCatalog.get_upgrade("laptop").is_empty() and not FurnitureCatalog.allows_monitors("laptop"),
		"la laptop no se mejora ni admite pantallas extra")
	_expect(FurnitureCatalog.get_price("glass_meeting_table") == 2000
		and FurnitureCatalog.get_footprint("glass_meeting_table", Vector2i.ZERO, 0).size() == 4
		and is_equal_approx(FurnitureCatalog.get_ambiance_points("glass_meeting_table"), 6.0),
		"mesa de vidrio 2×2 a $2,000 con 6 puntos de ambiente")
	_expect(FurnitureCatalog.get_price("meeting_table") == 1200, "la de madera sigue igual")


func _check_laptop() -> void:
	_new_game()
	_expect(_builder.place("simple_desk", OPEN_CELL, 0)["ok"], "escritorio sencillo")
	var result: Dictionary = _builder.quote_install_computer("laptop", OPEN_CELL)
	_expect(not result["ok"] and String(result["message"]).contains("escritorio ejecutivo"),
		"no va sobre el sencillo: %s" % result["message"])
	_expect(_builder.place("executive_desk", TABLE_CELL, 0)["ok"], "escritorio ejecutivo")
	var balance: int = Economy.balance
	result = _builder.install_computer("laptop", TABLE_CELL)
	_expect(result["ok"] and _item_at(TABLE_CELL)["computer"] == "laptop", "laptop sobre el ejecutivo: %s" % result["message"])
	_expect(Economy.balance == balance - 1800, "cobra $1,800")
	result = _builder.quote_upgrade(TABLE_CELL)
	_expect(not result["ok"] and String(result["message"]).contains("no se puede mejorar"), "Mejorar no la cambia: %s" % result["message"])
	result = _builder.quote_install_monitor("second_monitor", TABLE_CELL)
	_expect(not result["ok"], "no admite pantalla extra")
	_expect(SaveManager.save_game(SLOT), "guardar")
	_new_game()
	_expect(SaveManager.load_game(SLOT) and String(_item_at(TABLE_CELL).get("computer", "")) == "laptop", "se guarda y se carga")
	result = _builder.sell_furniture_at(TABLE_CELL)
	_expect(result["ok"] and String(result["message"]).contains("Laptop"), "vender devuelve también la laptop: %s" % result["message"])


func _check_glass_table() -> void:
	_new_game()
	Projects.meeting_room_unlocked = true
	_expect(_builder.mark_room("meeting_room", OPEN_CELL)["ok"], "marcar la Sala de reuniones")
	_expect(not Projects.has_working_room("meeting_room"), "sin mesa no funciona")
	var balance: int = Economy.balance
	_expect(_builder.place("glass_meeting_table", TABLE_CELL, 1)["ok"], "mesa de vidrio girada")
	_expect(Economy.balance == balance - 2000, "cobra $2,000")
	_expect(Projects.has_working_room("meeting_room"), "con la mesa de vidrio la sala funciona")
	var room: Dictionary = OfficeState.get_working_room("meeting_room")
	var with_glass: float = float(Ambiance.get_detail(room, OfficeState.furniture)["points"])
	_expect(is_equal_approx(with_glass, 6.0), "suma 6 puntos de ambiente a la sala: %s" % with_glass)


func _check_sprites() -> void:
	for rotation: int in range(4):
		for item_id: String in ["laptop", "glass_meeting_table"]:
			var sprite: String = SpriteLibrary.get_furniture_sprite(item_id, rotation)
			_expect(SpriteLibrary.has_sprite(sprite) and SpriteLibrary.has_sprite(sprite + "_shadow"),
				"%s r%d tiene dibujo y sombra: %s" % [item_id, rotation, sprite])
	_expect(is_equal_approx(SpriteLibrary.get_seat_x("computer_laptop"), 0.5), "se sienta frente al centro de la laptop")
