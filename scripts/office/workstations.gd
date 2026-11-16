# Puestos de trabajo (funciones puras): una silla en la casilla que mira el frente de un escritorio,
# uno por escritorio (cuenta la primera silla). Clases por "room_type": Área de trabajo (con
# computadora), Oficina única (sin computadora, uno por oficina), Recepción (mostrador) y Cuarto de
# limpieza (el armario mismo es "chair" y "desk"). La silla es la que lleva assigned_to.
class_name Workstations
extends RefCounted

const WORK_AREA: String = "work_area"
const SINGLE_OFFICE: String = "single_office"
const RECEPTION: String = "reception"
const CLEANING_ROOM: String = "cleaning_room"

# Últimos puestos por clase de habitación y el hash de los datos.
static var _cache: Dictionary = {}
static var _cache_key: int = 0
# Últimos bonos por silla ocupada y el hash de los muebles.
static var _bonuses: Dictionary[String, float] = {}
static var _bonuses_key: int = 0


## Puestos de la oficina: {"chair", "desk" (índices en furniture), "cell", "room_type"}.
## Con room_type, solo los de esa clase.
static func find_all(furniture: Array[Dictionary], rooms: Array[Dictionary], room_type: String = "") -> Array[Dictionary]:
	# Se piden por empleado cada hora: se guardan mientras no cambie el hash de muebles y habitaciones
	# (solo tipo y casillas; la suciedad cambia cada hora).
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


# Puestos de una clase. En un Área de trabajo el escritorio necesita computadora; en una Oficina única no, pero uno por oficina.
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


## assigned_to de quien usa furniture[index] en su puesto, o "" si no es de un puesto ocupado.
static func owner_of(furniture: Array[Dictionary], rooms: Array[Dictionary], index: int) -> String:
	for station: Dictionary in find_all(furniture, rooms):
		if station["chair"] == index or station["desk"] == index:
			return String(furniture[station["chair"]]["assigned_to"])
	return ""


## Computadora del escritorio cuyo frente da a la silla furniture[chair_index], o "".
static func computer_for_chair(furniture: Array[Dictionary], chair_index: int) -> String:
	var desk: int = computer_desk_for_chair(furniture, chair_index)
	return "" if desk < 0 else String(furniture[desk]["computer"])


## Índice del primer escritorio con computadora cuyo frente da a esa silla, o -1.
static func computer_desk_for_chair(furniture: Array[Dictionary], chair_index: int) -> int:
	var chair_cell: Vector2i = furniture[chair_index]["cell"]
	for desk_index: int in range(furniture.size()):
		var desk: Dictionary = furniture[desk_index]
		if String(desk.get("computer", "")).is_empty():
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if cell + front == chair_cell:
				return desk_index
	return -1


## Bono de producción de un escritorio: computadora y pantallas extra.
static func get_desk_bonus(desk: Dictionary) -> float:
	var computer: String = String(desk.get("computer", ""))
	if computer.is_empty():
		return 0.0
	var bonus: float = FurnitureCatalog.get_production_bonus(computer)
	var monitor: String = String(desk.get("monitor", ""))
	if not monitor.is_empty():
		bonus += FurnitureCatalog.get_production_bonus(monitor) * FurnitureCatalog.get_monitor_count(desk)
	return bonus


## Bono de cada silla ocupada: {assigned_to: bono}. Como bonus_of para todos a la vez; se guarda
## mientras los muebles no cambien.
static func bonuses_by_owner(furniture: Array[Dictionary]) -> Dictionary[String, float]:
	var key: int = furniture.hash()
	if key != _bonuses_key or _bonuses.is_empty():
		_bonuses = _find_bonuses(furniture)
		_bonuses_key = key
	return _bonuses


static func _find_bonuses(furniture: Array[Dictionary]) -> Dictionary[String, float]:
	var by_cell: Dictionary[Vector2i, float] = {}
	for desk: Dictionary in furniture:
		if String(desk.get("computer", "")).is_empty():
			continue
		var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
		for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
			if not by_cell.has(cell + front):
				by_cell[cell + front] = get_desk_bonus(desk)
	var result: Dictionary[String, float] = {}
	for item: Dictionary in furniture:
		var owner: String = String(item["assigned_to"])
		if not owner.is_empty() and not result.has(owner):
			result[owner] = by_cell.get(item["cell"], 0.0)
	return result


## Bono de producción del escritorio que usa who (assigned_to de su silla).
static func bonus_of(furniture: Array[Dictionary], who: String) -> float:
	for index: int in range(furniture.size()):
		if furniture[index]["assigned_to"] == who:
			var desk: int = computer_desk_for_chair(furniture, index)
			return 0.0 if desk < 0 else get_desk_bonus(furniture[desk])
	return 0.0


## Computadora que usa who, o "".
static func computer_of(furniture: Array[Dictionary], who: String) -> String:
	for index: int in range(furniture.size()):
		if furniture[index]["assigned_to"] == who:
			return computer_for_chair(furniture, index)
	return ""


## Escritorio del puesto que funciona de who, o vacío (para mood_bonus).
static func station_desk_of(furniture: Array[Dictionary], rooms: Array[Dictionary], who: String) -> Dictionary:
	for station: Dictionary in find_all(furniture, rooms):
		if furniture[station["chair"]]["assigned_to"] == who:
			return furniture[station["desk"]]
	return {}


# Primer escritorio libre de la habitación de la silla con el frente hacia ella (con computadora
# si needs_computer; mostrador si counter).
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
