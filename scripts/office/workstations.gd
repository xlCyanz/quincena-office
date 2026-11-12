# Puestos de trabajo (diseño, 16.2): una silla delante de un escritorio con computadora,
# las dos dentro de un Área de trabajo que funciona. Son funciones puras sobre los datos
# de OfficeState; se recalculan cada vez porque los muebles y las habitaciones cambian.
#
# "Delante" quiere decir que la silla está en la casilla que mira el frente del
# escritorio (FurnitureCatalog.get_front) desde alguna de sus casillas, como el CEO en su
# oficina. Cada escritorio sirve a una sola silla: si hay dos delante, cuenta la primera
# de la lista de muebles. La silla del puesto es la que se asigna al empleado
# (assigned_to); el CEO conserva la suya en la Oficina Ejecutiva.
class_name Workstations
extends RefCounted

const WORK_AREA: String = "work_area"


## Todos los puestos de la oficina. Cada uno es {"chair": int, "desk": int,
## "cell": Vector2i}: índices en furniture de la silla y el escritorio y la casilla de
## la silla.
static func find_all(furniture: Array[Dictionary], rooms: Array[Dictionary]) -> Array[Dictionary]:
	var work_cells: Dictionary[Vector2i, int] = {}
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		if room["type"] != WORK_AREA or not RoomRules.function_problems(room, furniture).is_empty():
			continue
		for cell: Vector2i in room["cells"]:
			work_cells[cell] = room_index
	var result: Array[Dictionary] = []
	var used_desks: Dictionary[int, bool] = {}
	for chair_index: int in range(furniture.size()):
		var chair: Dictionary = furniture[chair_index]
		if not bool(FurnitureCatalog.get_item(chair["id"]).get("is_seat", false)):
			continue
		var cell: Vector2i = chair["cell"]
		if not work_cells.has(cell):
			continue
		var desk_index: int = _desk_for(furniture, cell, work_cells, used_desks)
		if desk_index >= 0:
			used_desks[desk_index] = true
			result.append({"chair": chair_index, "desk": desk_index, "cell": cell})
	return result


## Puestos que nadie ocupa.
static func find_free(furniture: Array[Dictionary], rooms: Array[Dictionary]) -> Array[Dictionary]:
	var free: Array[Dictionary] = []
	for station: Dictionary in find_all(furniture, rooms):
		if String(furniture[station["chair"]]["assigned_to"]).is_empty():
			free.append(station)
	return free


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


# Primer escritorio libre con computadora, dentro del área de trabajo de la silla, cuyo
# frente da a la casilla de la silla.
static func _desk_for(furniture: Array[Dictionary], chair_cell: Vector2i,
		work_cells: Dictionary[Vector2i, int], used_desks: Dictionary[int, bool]) -> int:
	for desk_index: int in range(furniture.size()):
		if used_desks.has(desk_index):
			continue
		var desk: Dictionary = furniture[desk_index]
		if not bool(FurnitureCatalog.get_item(desk["id"]).get("accepts_computer", false)):
			continue
		if String(desk["computer"]).is_empty():
			continue
		if work_cells.get(desk["cell"], -1) != work_cells[chair_cell]:
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if cell + front == chair_cell:
				return desk_index
	return -1
