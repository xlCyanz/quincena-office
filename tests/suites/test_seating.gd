# Sillas arrimadas a mesas: frente a un escritorio quedan a SEAT_REACH del canto de su sprite y frente al
# teclado; dos sillas frente al mismo escritorio no se juntan; una silla de costado o de reunión se arrima
# si mira a la mesa.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=seating
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const DESKS: Array[String] = ["simple_desk", "long_desk", "executive_desk", "reception_counter"]
const TABLES: Array[String] = ["meeting_table", "glass_meeting_table", "dining_table"]
const ANCHOR := Vector2i(20, 20)

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	_check_edges()
	for id: String in DESKS:
		for rotation: int in range(4):
			_check_front_chair(id, rotation)
			_check_two_chairs(id, rotation)
	_check_side_chairs()
	_check_tables()
	OfficeState.furniture = []
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _item(id: String, cell: Vector2i, rotation: int, computer: String = "") -> Dictionary:
	return {"id": id, "cell": cell, "rotation": rotation, "assigned_to": "", "computer": computer, "monitor": "",
		"monitors": 0, "quarter": -1}


func _computer(id: String) -> String:
	return "" if id == "reception_counter" else "basic_computer"


# Toda mesa con sprite trae el canto de su tablero por lado, dentro de la casilla.
func _check_edges() -> void:
	for id: String in DESKS + TABLES:
		var edges: Array = SpriteLibrary.get_table_edges(SpriteLibrary.get_furniture_base(id))
		var inside: bool = edges.size() == 4
		for value: Variant in edges:
			inside = inside and float(value) >= 0.0 and float(value) < 0.5
		_expect(inside, "%s trae el canto de su tablero por lado (edges)" % id)
	_expect(SpriteLibrary.get_table_edges("desk_long_basic").size() == 4, "el escritorio largo con computadora también")


# Silla frente al escritorio: a SEAT_REACH del canto y con el teclado a la altura del centro.
func _check_front_chair(id: String, rotation: int) -> void:
	var desk: Dictionary = _item(id, ANCHOR, rotation, _computer(id))
	var front: Vector2i = FurnitureCatalog.get_front(rotation)
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(id, ANCHOR, rotation)
	var seat: Vector2i = cells[0] + front
	OfficeState.furniture = [desk, _item("basic_chair", seat, 0)]
	var what: String = "%s r%d" % [id, rotation]
	var table: Dictionary = FurnitureView.get_seat_table(seat)
	_expect(bool(table.get("front", false)) and FurnitureCatalog.get_front(int(table["direction"])) == -front,
		"%s: la silla de delante lo mira" % what)
	var offset: Vector2 = FurnitureView.get_seat_offset(seat)
	var step := Vector2(-front)
	# Del centro de la silla al canto: medio de casilla menos lo arrimado más el hueco del sprite.
	var reach: float = 0.5 - offset.dot(step) + FurnitureView.get_table_edge(desk, Vector2(front))
	_expect(absf(reach - FurnitureView.SEAT_REACH) < 0.001, "%s: la silla queda a %.3f del canto (debe %.2f)" % [what, reach, FurnitureView.SEAT_REACH])
	# A lo largo del modelo, desde su punta −x, el centro de la silla cae en el teclado.
	var base: String = SpriteLibrary.get_desk_set_base(id, _computer(id), 0)
	var along_key: float = SpriteLibrary.get_seat_x(base) if not base.is_empty() else -1.0
	if along_key < 0.0 and not _computer(id).is_empty():
		along_key = (cells.size()) / 2.0 - 0.5 + SpriteLibrary.get_seat_x(SpriteLibrary.get_furniture_base(_computer(id)))
	if along_key < 0.0:
		_expect(is_zero_approx(offset.dot(Vector2(FurnitureView.MODEL_X_SIDES[rotation]))), "%s: sin teclado no se corre de lado" % what)
		return
	var side: Vector2 = FurnitureView.MODEL_X_SIDES[rotation]
	var tip: float = INF
	for cell: Vector2i in cells:
		tip = minf(tip, Vector2(cell).dot(side) - 0.5)
	var along_chair: float = (Vector2(seat) + offset).dot(side) - tip
	var wanted: float = clampf(along_key, Vector2(seat).dot(side) - tip - FurnitureView.SEAT_SHIFT_MAX,
		Vector2(seat).dot(side) - tip + FurnitureView.SEAT_SHIFT_MAX)
	_expect(absf(along_chair - wanted) < 0.001, "%s: la silla queda frente al teclado (%.3f, debe %.3f)" % [what, along_chair, wanted])


# Dos sillas frente al mismo escritorio largo: cada una frente a su casilla, sin juntarse.
func _check_two_chairs(id: String, rotation: int) -> void:
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(id, ANCHOR, rotation)
	if cells.size() < 2:
		return
	var front: Vector2i = FurnitureCatalog.get_front(rotation)
	OfficeState.furniture = [_item(id, ANCHOR, rotation, _computer(id)), _item("basic_chair", cells[0] + front, 0),
		_item("basic_chair", cells[1] + front, 0)]
	var a: Vector2 = Vector2(cells[0] + front) + FurnitureView.get_seat_offset(cells[0] + front)
	var b: Vector2 = Vector2(cells[1] + front) + FurnitureView.get_seat_offset(cells[1] + front)
	_expect(is_equal_approx(a.distance_to(b), 1.0), "%s r%d: dos sillas quedan a una casilla una de otra (%.2f)" % [id, rotation, a.distance_to(b)])


# Silla de costado: se arrima al ejecutivo si lo mira, sin girar; si mira a otro lado, queda en su casilla.
func _check_side_chairs() -> void:
	var desk: Dictionary = _item("executive_desk", ANCHOR, 2, "basic_computer")
	for rotation: int in range(4):
		var seat: Vector2i = ANCHOR + Vector2i(-1, 0)
		OfficeState.furniture = [desk, _item("basic_chair", seat, rotation)]
		var offset: Vector2 = FurnitureView.get_seat_offset(seat)
		if rotation == 1:
			var table: Dictionary = FurnitureView.get_seat_table(seat)
			var reach: float = 0.5 - offset.x + FurnitureView.get_table_edge(desk, Vector2(-1, 0))
			_expect(not table.is_empty() and not bool(table["front"]) and is_zero_approx(offset.y)
				and absf(reach - FurnitureView.SEAT_REACH) < 0.001, "la visita de costado se arrima al canto del ejecutivo")
		else:
			_expect(offset == Vector2.ZERO, "una silla de costado que no mira al escritorio (r%d) queda en su casilla" % rotation)
	# Del otro lado, frente al fondo del escritorio.
	var back_seat: Vector2i = ANCHOR + Vector2i(0, -1)
	OfficeState.furniture = [desk, _item("basic_chair", back_seat, 2)]
	var back: Vector2 = FurnitureView.get_seat_offset(back_seat)
	_expect(back.y > 0.0 and is_zero_approx(back.x), "la visita del otro lado se arrima al fondo del ejecutivo")


# Mesas de reunión y comedor: cada silla que la mira se arrima sin salir de su casilla.
func _check_tables() -> void:
	for id: String in TABLES:
		var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(id, ANCHOR, 0)
		var ok: bool = true
		for cell: Vector2i in cells:
			for direction: int in range(4):
				var step: Vector2i = FurnitureCatalog.get_front(direction)
				var seat: Vector2i = cell - step
				if cells.has(seat):
					continue
				OfficeState.furniture = [_item(id, ANCHOR, 0), _item("basic_chair", seat, direction)]
				var tuck: float = FurnitureView.get_seat_offset(seat).dot(Vector2(step))
				ok = ok and tuck > 0.0 and tuck <= FurnitureView.SEAT_TUCK_MAX + 0.001
		_expect(ok, "%s: las sillas que la miran se arriman sin salir de su casilla" % id)
