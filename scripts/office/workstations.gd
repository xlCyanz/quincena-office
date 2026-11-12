# Puestos de trabajo (diseño, 16.2): una silla delante de un escritorio con computadora,
# las dos dentro de un Área de trabajo que funciona. Son funciones puras sobre los datos
# de OfficeState; se recalculan cuando cambian los muebles o las habitaciones.
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
#
# Desde el hito 36 la Recepción tiene puestos para los recepcionistas: una silla
# delante del frente de un mostrador (is_counter), uno por mostrador.
#
# Desde el hito 37 el personal de limpieza tiene su puesto en un Cuarto de limpieza que
# funciona: el armario de limpieza (is_closet) mismo, sin silla; uno por armario. En esos
# puestos "chair" y "desk" son el armario (ahí va su assigned_to).
class_name Workstations
extends RefCounted

const WORK_AREA: String = "work_area"
const SINGLE_OFFICE: String = "single_office"
const RECEPTION: String = "reception"
const CLEANING_ROOM: String = "cleaning_room"

# Últimos puestos encontrados por clase de habitación y el hash de los datos que los dieron.
static var _cache: Dictionary = {}
static var _cache_key: int = 0
# Últimas computadoras por silla ocupada (computers_by_owner) y el hash de los muebles.
static var _computers: Dictionary[String, String] = {}
static var _computers_key: int = 0


## Todos los puestos de la oficina. Cada uno es {"chair": int, "desk": int,
## "cell": Vector2i, "room_type": String}: índices en furniture de la silla y el
## escritorio, la casilla de la silla y la clase de habitación. Con room_type solo los
## de esa clase.
static func find_all(furniture: Array[Dictionary], rooms: Array[Dictionary], room_type: String = "") -> Array[Dictionary]:
	# Buscarlos recorre los muebles por cada silla y se pide por cada empleado cada hora:
	# se guarda el último resultado mientras muebles y habitaciones no cambien (el hash
	# de los dos, que Godot calcula en código nativo, mucho más rápido que buscarlos). De
	# las habitaciones cuentan el tipo y las casillas: la suciedad cambia cada hora.
	var room_parts: Array = []
	for room: Dictionary in rooms:
		room_parts.append(room["type"])
		room_parts.append(room["cells"])
	var key: int = [furniture.hash(), room_parts.hash()].hash()
	if key != _cache_key or _cache.is_empty():
		_cache.clear()
		for kind: String in [WORK_AREA, SINGLE_OFFICE, RECEPTION, CLEANING_ROOM]:
			_cache[kind] = _find_kind(furniture, rooms, kind)
		_cache_key = key
	var result: Array[Dictionary] = []
	for kind: String in [WORK_AREA, SINGLE_OFFICE, RECEPTION, CLEANING_ROOM]:
		if room_type.is_empty() or room_type == kind:
			result.append_array(_cache[kind])
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
	var result: Array[Dictionary] = []
	if kind == CLEANING_ROOM:
		for index: int in range(furniture.size()):
			var item: Dictionary = furniture[index]
			if bool(FurnitureCatalog.get_item(item["id"]).get("is_closet", false)) and room_cells.has(item["cell"]):
				result.append({"chair": index, "desk": index, "cell": item["cell"], "room_type": kind})
		return result
	var needs_computer: bool = kind == WORK_AREA
	var one_per_room: bool = kind == SINGLE_OFFICE
	var used_desks: Dictionary[int, bool] = {}
	var used_rooms: Dictionary[int, bool] = {}
	for chair_index: int in range(furniture.size()):
		var chair: Dictionary = furniture[chair_index]
		if not bool(FurnitureCatalog.get_item(chair["id"]).get("is_seat", false)):
			continue
		var cell: Vector2i = chair["cell"]
		if not room_cells.has(cell):
			continue
		if one_per_room and used_rooms.has(room_cells[cell]):
			continue
		var desk_index: int = _desk_for(furniture, cell, room_cells, used_desks, needs_computer, kind == RECEPTION)
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


## Computadora de cada silla ocupada: {assigned_to: computadora} (sin computadora, "").
## Lo mismo que computer_of para todos de una vez, sin recorrer los muebles por cada uno.
## Se guarda el último resultado mientras los muebles no cambien.
static func computers_by_owner(furniture: Array[Dictionary]) -> Dictionary[String, String]:
	var key: int = furniture.hash()
	if key != _computers_key or _computers.is_empty():
		_computers = _find_computers(furniture)
		_computers_key = key
	return _computers


static func _find_computers(furniture: Array[Dictionary]) -> Dictionary[String, String]:
	var by_cell: Dictionary[Vector2i, String] = {}
	for desk: Dictionary in furniture:
		if String(desk.get("computer", "")).is_empty():
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if not by_cell.has(cell + front):
				by_cell[cell + front] = String(desk["computer"])
	var result: Dictionary[String, String] = {}
	for item: Dictionary in furniture:
		var owner: String = String(item["assigned_to"])
		if not owner.is_empty() and not result.has(owner):
			result[owner] = by_cell.get(item["cell"], "")
	return result


## Computadora que usa who (el assigned_to de su silla), o "" si no tiene.
static func computer_of(furniture: Array[Dictionary], who: String) -> String:
	for index: int in range(furniture.size()):
		if furniture[index]["assigned_to"] == who:
			return computer_for_chair(furniture, index)
	return ""


# Primer escritorio libre (con computadora si needs_computer; un mostrador si counter),
# dentro de la habitación de la silla, cuyo frente da a la casilla de la silla.
static func _desk_for(furniture: Array[Dictionary], chair_cell: Vector2i,
		work_cells: Dictionary[Vector2i, int], used_desks: Dictionary[int, bool], needs_computer: bool = true,
		counter: bool = false) -> int:
	for desk_index: int in range(furniture.size()):
		if used_desks.has(desk_index):
			continue
		var desk: Dictionary = furniture[desk_index]
		var info: Dictionary = FurnitureCatalog.get_item(desk["id"])
		if not bool(info.get("is_counter" if counter else "accepts_computer", false)):
			continue
		if needs_computer and String(desk.get("computer", "")).is_empty():
			continue
		if work_cells.get(desk["cell"], -1) != work_cells[chair_cell]:
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if cell + front == chair_cell:
				return desk_index
	return -1
