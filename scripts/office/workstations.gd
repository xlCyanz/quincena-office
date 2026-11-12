# Puestos de trabajo (diseño, 16.2): una silla delante de un escritorio con computadora,
# las dos dentro de un Área de trabajo que funciona. Son funciones puras sobre los datos
# de OfficeState; se recalculan cada vez porque los muebles y las habitaciones cambian.
#
# "Delante" quiere decir que la silla está en la casilla que mira el frente del
# escritorio (FurnitureCatalog.get_front) desde alguna de sus casillas, como el CEO en su
# oficina. Cada escritorio sirve a una sola silla: si hay dos delante, cuenta la primera
# de la lista de muebles. La silla del puesto es la que se asigna al empleado
# (assigned_to); el CEO conserva la suya en la Oficina Ejecutiva.
#
# Desde el hito 32 también hay puestos en una Oficina única que funciona (para los
# gerentes): una silla delante de un escritorio de la misma oficina, sin computadora, y
# uno solo por oficina. Cada puesto dice en "room_type" de qué clase es.
class_name Workstations
extends RefCounted

const WORK_AREA: String = "work_area"
const SINGLE_OFFICE: String = "single_office"


## Todos los puestos de la oficina. Cada uno es {"chair": int, "desk": int,
## "cell": Vector2i, "room_type": String}: índices en furniture de la silla y el
## escritorio, la casilla de la silla y la clase de habitación. Con room_type solo los
## de esa clase.
static func find_all(furniture: Array[Dictionary], rooms: Array[Dictionary], room_type: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: String in [WORK_AREA, SINGLE_OFFICE]:
		if room_type.is_empty() or room_type == kind:
			result.append_array(_find_kind(furniture, rooms, kind))
	return result


## Puestos que nadie ocupa, de una clase (Área de trabajo si no se dice).
static func find_free(furniture: Array[Dictionary], rooms: Array[Dictionary], room_type: String = WORK_AREA) -> Array[Dictionary]:
	var free: Array[Dictionary] = []
	for station: Dictionary in find_all(furniture, rooms, room_type):
		if String(furniture[station["chair"]]["assigned_to"]).is_empty():
			free.append(station)
	return free


# Puestos de una clase de habitación. En un Área de trabajo el escritorio necesita
# computadora; en una Oficina única no, pero hay un solo puesto por oficina.
static func _find_kind(furniture: Array[Dictionary], rooms: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var room_cells: Dictionary[Vector2i, int] = {}
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		if room["type"] != kind or not RoomRules.function_problems(room, furniture).is_empty():
			continue
		for cell: Vector2i in room["cells"]:
			room_cells[cell] = room_index
	var needs_computer: bool = kind == WORK_AREA
	var result: Array[Dictionary] = []
	var used_desks: Dictionary[int, bool] = {}
	var used_rooms: Dictionary[int, bool] = {}
	for chair_index: int in range(furniture.size()):
		var chair: Dictionary = furniture[chair_index]
		if not bool(FurnitureCatalog.get_item(chair["id"]).get("is_seat", false)):
			continue
		var cell: Vector2i = chair["cell"]
		if not room_cells.has(cell):
			continue
		if not needs_computer and used_rooms.has(room_cells[cell]):
			continue
		var desk_index: int = _desk_for(furniture, cell, room_cells, used_desks, needs_computer)
		if desk_index >= 0:
			used_desks[desk_index] = true
			used_rooms[room_cells[cell]] = true
			result.append({"chair": chair_index, "desk": desk_index, "cell": cell, "room_type": kind})
	return result


## Indica si la silla asignada a who forma un puesto que funciona.
static func is_working_station(furniture: Array[Dictionary], rooms: Array[Dictionary], who: String) -> bool:
	for station: Dictionary in find_all(furniture, rooms):
		if furniture[station["chair"]]["assigned_to"] == who:
			return true
	return false


## Quién usa el mueble de furniture[index] como parte de su puesto: el assigned_to de
## la silla del puesto, o "" si no es parte de un puesto ocupado.
static func owner_of(furniture: Array[Dictionary], rooms: Array[Dictionary], index: int) -> String:
	for station: Dictionary in find_all(furniture, rooms):
		if station["chair"] == index or station["desk"] == index:
			return String(furniture[station["chair"]]["assigned_to"])
	return ""


## Computadora que usa quien se sienta en la silla de furniture[chair_index]: la del
## escritorio cuyo frente da a esa silla, o "" si no hay.
static func computer_for_chair(furniture: Array[Dictionary], chair_index: int) -> String:
	var chair_cell: Vector2i = furniture[chair_index]["cell"]
	for desk: Dictionary in furniture:
		if String(desk.get("computer", "")).is_empty():
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if cell + front == chair_cell:
				return String(desk["computer"])
	return ""


## Computadora que usa who (el assigned_to de su silla), o "" si no tiene.
static func computer_of(furniture: Array[Dictionary], who: String) -> String:
	for index: int in range(furniture.size()):
		if furniture[index]["assigned_to"] == who:
			return computer_for_chair(furniture, index)
	return ""


# Primer escritorio libre (con computadora si needs_computer), dentro de la habitación
# de la silla, cuyo frente da a la casilla de la silla.
static func _desk_for(furniture: Array[Dictionary], chair_cell: Vector2i,
		work_cells: Dictionary[Vector2i, int], used_desks: Dictionary[int, bool], needs_computer: bool = true) -> int:
	for desk_index: int in range(furniture.size()):
		if used_desks.has(desk_index):
			continue
		var desk: Dictionary = furniture[desk_index]
		if not bool(FurnitureCatalog.get_item(desk["id"]).get("accepts_computer", false)):
			continue
		if needs_computer and String(desk["computer"]).is_empty():
			continue
		if work_cells.get(desk["cell"], -1) != work_cells[chair_cell]:
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if cell + front == chair_cell:
				return desk_index
	return -1
