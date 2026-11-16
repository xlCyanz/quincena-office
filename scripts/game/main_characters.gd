# Partida, capa 1 de 3: nodos, oficina dibujada y personajes (CEO, empleados, visitas, rutinas y lugares).
# main.gd hereda de las capas en orden; cada una solo llama a las de abajo.
extends Node2D

const CEO_SCENE: PackedScene = preload("res://scenes/ceo.tscn")
const EMPLOYEE_SCENE: PackedScene = preload("res://scenes/employee.tscn")
const VISITOR_SCENE: PackedScene = preload("res://scenes/visitor.tscn")
## Distancia máxima entre apretar y soltar para que cuente como clic.
const CLICK_TOLERANCE_PX: float = 8.0
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
## Sin lugar (p. ej. donde trapear).
const NO_SPOT := Vector2i(-9999, -9999)

# Paredes arriba pedidas por el jugador (botón ↕ o tecla P).
var _walls_wanted: bool = false
var ceo: Ceo
## Personaje de cada empleado, por id.
var employees: Dictionary[int, Employee] = {}
# Despedidos que todavía caminan hacia la salida; desaparecen al salir.
var _departing: Array[Employee] = []
## Personaje de cada cliente que espera en la Recepción, por id de visita.
var visitors: Dictionary[int, Visitor] = {}
# Clientes que ya se van; desaparecen al salir.
var _leaving_visitors: Array[Visitor] = []
## Candidato en entrevista (va al escritorio de quien entrevista); null si no hay.
var interviewee: Visitor = null
## Citados que ya llegaron: id del candidato → personaje. Al empezar pasa a interviewee.
var appointment_visitors: Dictionary[int, Visitor] = {}
var pathfinder := OfficePathfinder.new()
# Llegadas escalonadas: clave → minuto absoluto en que entra. Se recalcula en _update_routines.
var _arrivals: Dictionary[String, int] = {}
# Salidas escalonadas: clave → minuto absoluto en que se va.
var _departures: Dictionary[String, int] = {}
# Llegaron antes de su hora: esperan en la Sala de descanso o dan vueltas.
var _early: Dictionary[String, bool] = {}
# Último minuto (o tramo de vueltas) revisado de las llegadas.
var _last_arrival_check: int = -1
# Hay alguien de limpieza trapeando: cada mop_minutes cambia de lugar (main._process).
var _cleaners_on_duty: bool = false
# Limpieza que ya llegó y espera su minuto de empezar: clave → minuto absoluto.
var _cleaning_starts: Dictionary[String, int] = {}

# El reloj estaba en pausa antes de abrir construcción o Ajustes.
var _was_paused_before_menu: bool = false
# Construcción pausó el tiempo al entrar (opción pause_on_build).
var _build_paused: bool = false
var _was_paused_before_emergency: bool = false
var _was_paused_before_ipo: bool = false
# El reloj estaba en pausa antes de abrir el menú de pausa.
var _was_paused_before_pause: bool = false
# Ajustes abierto desde la pausa: al cerrarlo se vuelve a ella.
var _settings_from_pause: bool = false
# Menú de pausa; se arma en código.
var _pause_menu: PauseMenu
# Tarjeta del tutorial; se arma en código.
var _tutorial_panel: TutorialPanel
# Ayuda de los menús (botones «?»); se arma en código.
var _help_dialog: HelpDialog
# Pantalla de salida a bolsa; se arma en código.
var _ipo_screen: IpoScreen
# Dónde se apretó el botón izquierdo (clic o arrastre).
var _press_position := Vector2.INF
var _ceo_button: Button

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera
@onready var _build_controller: BuildController = $BuildController
@onready var _build_panel: BuildPanel = $BuildPanel
@onready var _hud: Hud = $Hud
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _staff_panel: StaffPanel = $StaffPanel
@onready var _projects_panel: ProjectsPanel = $ProjectsPanel
@onready var _teams_panel: TeamsPanel = $TeamsPanel
@onready var _bank_panel: BankPanel = $BankPanel
@onready var _company_panel: CompanyPanel = $CompanyPanel
@onready var _objectives_panel: ObjectivesPanel = $ObjectivesPanel
@onready var _game_over_screen: GameOverScreen = $GameOverScreen
@onready var _emergency_dialog: EmergencyLoanDialog = $EmergencyLoanDialog
@onready var _employee_card: EmployeeCard = $EmployeeCard


func _rebuild_office() -> void:
	_office_grid.set_site(OfficeState.site_rect, OfficeState.get_outside_of_entrance())
	_office_grid.build(OfficeState.lot, OfficeState.floors, OfficeState.edges, OfficeState.furniture,
		OfficeState.rooms)
	pathfinder.build(OfficeState.lot, OfficeState.get_blocking_cells(), OfficeState.edges)


func _spawn_ceo() -> void:
	ceo = CEO_SCENE.instantiate()
	_office_grid.add_object(ceo)
	ceo.sat_down.connect(func() -> void: print("El CEO se sentó en su escritorio."))
	ceo.left_office.connect(_on_character_left_office)
	ceo.setup(_office_grid, pathfinder, _seat_of("ceo"), OfficeState.entrance,
		OfficeState.get_outside_of_entrance())


# Crea el personaje de los empleados nuevos, quita el de los que ya no están y avisa cambios de silla.
func _sync_employees() -> void:
	for employee: Dictionary in Staff.employees:
		var employee_id: int = employee["id"]
		if employees.has(employee_id):
			employees[employee_id].set_seat(_spot_of(employee))
			employees[employee_id].update_role(employee)
			continue
		var character: Employee = EMPLOYEE_SCENE.instantiate()
		character.configure(employee)
		_office_grid.add_object(character)
		character.left_office.connect(_on_character_left_office)
		character.setup(_office_grid, pathfinder, _spot_of(employee), OfficeState.entrance,
			OfficeState.get_outside_of_entrance())
		employees[employee_id] = character
		character.update_routine(Staff.is_expected_now(character.person_key))
	for employee_id: int in employees.keys():
		if Staff.get_employee(employee_id).is_empty():
			var leaving: Employee = employees[employee_id]
			employees.erase(employee_id)
			_departing.append(leaving)
			leaving.update_routine(false)
	_remove_departed()


# Crea a los clientes que llegaron, manda a casa a los que ya no esperan y reparte lugares.
func _sync_visitors() -> void:
	var spots: Array[Vector2i] = Projects.get_waiting_spots()
	var waiting: Array[int] = []
	var used: Dictionary[Vector2i, bool] = {}
	for index: int in range(Projects.visits.size()):
		var visit: Dictionary = Projects.visits[index]
		var visit_id: int = visit["id"]
		waiting.append(visit_id)
		var spot: Vector2i = _free_spot_near(spots[index % spots.size()], used) if not spots.is_empty() \
			else OfficeState.entrance
		if visitors.has(visit_id):
			visitors[visit_id].set_seat(spot)
			continue
		var character: Visitor = VISITOR_SCENE.instantiate()
		character.configure(visit)
		_office_grid.add_object(character)
		character.left_office.connect(_remove_left_visitors)
		character.setup(_office_grid, pathfinder, spot, OfficeState.entrance, OfficeState.get_outside_of_entrance())
		visitors[visit_id] = character
		character.update_routine(true)
	for visit_id: int in visitors.keys():
		if not waiting.has(visit_id):
			var leaving: Visitor = visitors[visit_id]
			visitors.erase(visit_id)
			_leaving_visitors.append(leaving)
			leaving.update_routine(false)
	_remove_left_visitors()


# El candidato entra y va frente al escritorio de quien entrevista; al terminar se va.
func _sync_interview() -> void:
	var candidate: Dictionary = Staff.get_interviewed_now()
	var candidate_key: String = "" if candidate.is_empty() else "candidate_%d" % int(candidate["id"])
	if interviewee != null and interviewee.person_key != candidate_key:
		_leaving_visitors.append(interviewee)
		interviewee.update_routine(false)
		interviewee = null
		_remove_left_visitors()
	if candidate.is_empty() or interviewee != null:
		_sync_appointments()
		return
	var by: String = String(Staff.interview.get("by", "ceo"))
	var waiting: Visitor = appointment_visitors.get(int(candidate["id"]))
	if waiting != null:
		# Ya estaba esperando: camina hasta la silla de visita.
		appointment_visitors.erase(int(candidate["id"]))
		interviewee = waiting
		interviewee.hurry = not Staff.is_interview_started()
		interviewee.sat_down.connect(_on_interviewee_seated.bind(interviewee))
		interviewee.standing = Staff.get_guest_chair(by).is_empty()
		interviewee.set_seat(_interview_spot(by))
		_sync_appointments()
		return
	interviewee = VISITOR_SCENE.instantiate()
	interviewee.configure_candidate(candidate)
	interviewee.standing = Staff.get_guest_chair(String(Staff.interview.get("by", "ceo"))).is_empty()
	_office_grid.add_object(interviewee)
	interviewee.left_office.connect(_remove_left_visitors)
	interviewee.sat_down.connect(_on_interviewee_seated.bind(interviewee))
	interviewee.hurry = not Staff.is_interview_started()
	interviewee.setup(_office_grid, pathfinder, _interview_spot(String(Staff.interview.get("by", "ceo"))),
		OfficeState.entrance, OfficeState.get_outside_of_entrance())
	interviewee.update_routine(true)
	_sync_appointments()


# El candidato llamado llegó a la silla de visita: empieza la entrevista.
func _on_interviewee_seated(character: Visitor) -> void:
	if character == interviewee and character.person_key == "candidate_%d" % int(Staff.interview.get("candidate_id", -1)):
		Staff.start_called_interview()


# Los citados llegan antes (Staff.get_appointment_arrival) y esperan de pie; si se cancela, se van.
func _sync_appointments() -> void:
	var now: int = get_arrival_minute()
	var due: Array[int] = []
	for appointment: Dictionary in Staff.appointments:
		if Staff.get_appointment_arrival(appointment) <= now:
			due.append(int(appointment["candidate_id"]))
	var used: Dictionary[Vector2i, bool] = {}
	for visitor: Visitor in visitors.values():
		used[visitor.get_seat_cell()] = true
	var spots: Array[Vector2i] = Projects.get_waiting_spots()
	if spots.is_empty() and not due.is_empty():
		spots = _cells_near(OfficeState.entrance, due.size() + used.size() + 1)
		spots.erase(OfficeState.entrance)
	for index: int in range(due.size()):
		var candidate_id: int = due[index]
		var spot: Vector2i = _free_spot_near(spots[index % spots.size()], used) if not spots.is_empty() \
			else OfficeState.entrance
		if appointment_visitors.has(candidate_id):
			appointment_visitors[candidate_id].set_seat(spot)
			continue
		var character: Visitor = VISITOR_SCENE.instantiate()
		character.configure_candidate(Staff.get_candidate(candidate_id))
		_office_grid.add_object(character)
		character.left_office.connect(_remove_left_visitors)
		character.setup(_office_grid, pathfinder, spot, OfficeState.entrance, OfficeState.get_outside_of_entrance())
		appointment_visitors[candidate_id] = character
		character.update_routine(true)
	for candidate_id: int in appointment_visitors.keys():
		if not due.has(candidate_id):
			var leaving: Visitor = appointment_visitors[candidate_id]
			appointment_visitors.erase(candidate_id)
			_leaving_visitors.append(leaving)
			leaving.update_routine(false)
	_remove_left_visitors()


## Casilla del candidato: del otro lado del escritorio de quien entrevista ("ceo" o clave del
## ejecutivo), en su habitación; si no hay, junto a su silla.
func _interview_spot(by: String) -> Vector2i:
	# En la silla de visita de su oficina, si hay.
	var guest: Dictionary = Staff.get_guest_chair(by)
	if not guest.is_empty():
		return guest["cell"]
	var chair: Vector2i = _seat_of(by)
	var desk_cells: Array[Vector2i] = []
	for item: Dictionary in OfficeState.furniture:
		if bool(FurnitureCatalog.get_item(String(item["id"])).get("accepts_computer", false)):
			var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(item["id"], item["cell"], int(item["rotation"]))
			for cell: Vector2i in cells:
				if (cell - chair).abs().x + (cell - chair).abs().y == 1:
					desk_cells = cells
	var room: Dictionary = Staff.get_workplace_room(by)
	var room_cells: Array = room.get("cells", [])
	var best := chair
	var best_score: int = -1000000
	var around: Array[Vector2i] = desk_cells if not desk_cells.is_empty() else [chair] as Array[Vector2i]
	for base: Vector2i in around:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var cell: Vector2i = base + direction
			if cell == chair or desk_cells.has(cell) or not pathfinder.is_walkable(cell) or cell == OfficeState.entrance:
				continue
			if not room_cells.is_empty() and not room_cells.has(cell):
				continue
			# Del otro lado del escritorio: lo más lejos posible de la silla.
			var score: int = (cell - chair).abs().x + (cell - chair).abs().y
			if score > best_score:
				best_score = score
				best = cell
	if best == chair:
		return _cells_near(chair, 2)[-1] if pathfinder.is_walkable(chair) else OfficeState.entrance
	return best


func _remove_left_visitors() -> void:
	for leaving: Visitor in _leaving_visitors.duplicate():
		if leaving.activity == OfficeCharacter.Activity.AWAY:
			_leaving_visitors.erase(leaving)
			leaving.queue_free()


# Quita a los despedidos que ya salieron del local.
func _remove_departed() -> void:
	for leaving: Employee in _departing.duplicate():
		if leaving.activity == OfficeCharacter.Activity.AWAY:
			_departing.erase(leaving)
			leaving.queue_free()


func _on_dirt_changed() -> void:
	_office_grid.set_dirt(OfficeState.rooms)
	_sync_employees()


# Destino de un empleado: la limpieza en su turno trapea por partes (_cleaning_spot); los demás, a su silla.
func _spot_of(employee: Dictionary) -> Vector2i:
	if is_cleaning_now(employee):
		var spot: Vector2i = _cleaning_spot(employee, get_arrival_minute())
		if spot != NO_SPOT:
			return spot
	return _seat_of(Staff.employee_key(employee["id"]))


## Indica si alguien es de limpieza y le toca estar ahora (trapea con su cubo).
func is_cleaning_now(employee: Dictionary) -> bool:
	return Staff.is_cleaner(employee) and Staff.is_expected_now(Staff.employee_key(employee["id"])) \
		and GameClock.get_minute() >= Staff.get_cleaning_start_minute(employee)


## Dónde trapea ahora alguien de limpieza: una casilla libre que cambia cada mop_minutes, en la
## habitación que limpia (la más sucia) o, sin nada sucio, recorriendo las habitaciones
## (mop_spots_per_room casillas en cada una). Solo visual: la suciedad la quita Staff. NO_SPOT si no hay dónde.
func _cleaning_spot(employee: Dictionary, now: int) -> Vector2i:
	var minutes: int = maxi(1, int(StaffCatalog.get_cleaning("mop_minutes")))
	@warning_ignore("integer_division")
	var turn: int = now / minutes
	# Varios de limpieza: cada uno en otra casilla (y, recorriendo, en otra habitación).
	var before: int = 0
	for other: Dictionary in Staff.employees:
		if int(other["id"]) < int(employee["id"]) and is_cleaning_now(other):
			before += 1
	var room_index: int = Staff.get_cleaning_room(employee)
	if room_index < 0:
		var rooms: Array[int] = []
		for index: int in range(OfficeState.rooms.size()):
			if OfficeState.rooms[index]["type"] != Workstations.CLEANING_ROOM:
				rooms.append(index)
		if rooms.is_empty():
			return NO_SPOT
		@warning_ignore("integer_division")
		var round_index: int = turn / maxi(1, int(StaffCatalog.get_cleaning("mop_spots_per_room")))
		room_index = rooms[posmod(round_index + before, rooms.size())]
	var taken: Array[Vector2i] = OfficeState.get_blocking_cells()
	var free: Array[Vector2i] = []
	for cell: Vector2i in OfficeState.rooms[room_index]["cells"]:
		if cell != OfficeState.entrance and not taken.has(cell) and pathfinder.is_walkable(cell):
			free.append(cell)
	if free.is_empty():
		return NO_SPOT
	return free[posmod(hash([int(employee["id"]), turn]) + before * 7, free.size())]


# Hasta count casillas libres alrededor de spot (spot primero), las más cercanas caminando; nunca la entrada.
func _cells_near(spot: Vector2i, count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = [spot]
	var index: int = 0
	while index < found.size() and found.size() < count:
		var cell: Vector2i = found[index]
		index += 1
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + direction
			if found.size() < count and not found.has(next) and next != OfficeState.entrance \
					and pathfinder.is_walkable(next) and pathfinder.can_cross(cell, next):
				found.append(next)
	return found


# La casilla libre más cercana a spot que no está en used (y la anota).
func _free_spot_near(spot: Vector2i, used: Dictionary[Vector2i, bool]) -> Vector2i:
	var count: int = used.size() + 1
	for cell: Vector2i in _cells_near(spot, count):
		if not used.has(cell):
			used[cell] = true
			return cell
	return spot


# Lugar de trabajo: el CEO a su silla y cada empleado a su lugar.
func _home_spot(key: String) -> Vector2i:
	if key == "ceo":
		return _seat_of(key)
	var employee: Dictionary = Staff.get_employee_by_key(key)
	return _seat_of(key) if employee.is_empty() else _spot_of(employee)


func _seat_of(key: String) -> Vector2i:
	return OfficeState.find_furniture_assigned_to(key).get("cell", OfficeState.entrance)


## Todos los personajes: el CEO y los empleados.
func get_characters() -> Array[OfficeCharacter]:
	var characters: Array[OfficeCharacter] = [ceo]
	for employee_id: int in employees:
		characters.append(employees[employee_id])
	characters.append_array(_departing)
	return characters


## Minuto absoluto del reloj (hora absoluta × 60 + minuto).
func get_arrival_minute() -> int:
	return Staff.get_absolute_hour() * 60 + GameClock.get_minute()


## Copia de _arrivals: minuto en que entra cada empleado que no llegó.
func get_pending_arrivals() -> Dictionary[String, int]:
	return _arrivals.duplicate()


## Copia de _departures: minuto en que se va cada empleado que terminó.
func get_pending_departures() -> Dictionary[String, int]:
	return _departures.duplicate()


## Indica si llegó antes de su hora y está esperando.
func is_waiting_shift(key: String) -> bool:
	return _early.has(key)


# Llegadas escalonadas (staff.json, arrivals): quien llega antes espera de pie hasta su hora.
# Devuelve true si ya se ocupó del personaje.
func _arrive_staggered(character: OfficeCharacter, eating: bool, now: int, hour_start: int,
		used: Dictionary[Vector2i, bool]) -> bool:
	var key: String = character.person_key
	if eating or Staff.is_expected_now(key):
		_early.erase(key)
		character.standing = false
		if eating or character.activity != OfficeCharacter.Activity.AWAY:
			return false
		var late_at: int = hour_start + Staff.get_late_minutes(key)
		if late_at <= now:
			# Entra después de su hora: llega apurado.
			# Limpieza entra a su minuto fijo: solo se apura si ya pasó.
			character.hurry = now > late_at if Staff.is_cleaner(Staff.get_employee_by_key(key)) \
				else now > hour_start or Staff.get_late_minutes(key) > 0
			return false
		_arrivals[key] = late_at
		character.set_seat(_home_spot(key))
		return true
	# Terminó su jornada: se queda unos minutos antes de irse.
	var leave_at: int = hour_start + Staff.get_leave_minutes(key)
	if leave_at > now and character.activity != OfficeCharacter.Activity.AWAY \
			and character.activity != OfficeCharacter.Activity.WALKING_OUT:
		_departures[key] = leave_at
		return true
	var early: int = Staff.get_early_minutes(key)
	if early <= 0:
		_early.erase(key)
		character.standing = false
		return false
	var early_at: int = hour_start + 60 - early
	if early_at > now and character.activity == OfficeCharacter.Activity.AWAY:
		_arrivals[key] = early_at
		return true
	_early[key] = true
	character.standing = true
	character.set_seat(_waiting_spot(key, now, used))
	character.update_routine(true)
	return true


# El CEO abre la oficina open_minutes antes de su hora y va a su silla. True si ya se ocupó de él.
func _ceo_opens(now: int, hour_start: int) -> bool:
	var early: int = Staff.get_ceo_early_minutes()
	if early <= 0:
		return false
	var open_at: int = hour_start + 60 - early
	if open_at > now:
		if ceo.activity == OfficeCharacter.Activity.AWAY:
			_arrivals["ceo"] = open_at
		return ceo.activity == OfficeCharacter.Activity.AWAY
	ceo.set_seat(_home_spot("ceo"))
	ceo.update_routine(true)
	return true


# Dónde espera quien llegó antes: casilla libre de la Sala de descanso o, sin ella, una
# casilla que cambia cada wander_minutes.
func _waiting_spot(key: String, now: int, used: Dictionary[Vector2i, bool]) -> Vector2i:
	var cells: Array[Vector2i] = []
	var bucket: int = 0
	var room: Dictionary = OfficeState.get_working_room(OfficeState.BREAK_ROOM)
	if not room.is_empty():
		cells.assign(room["cells"])
	else:
		cells.assign(pathfinder.get_reachable(OfficeState.entrance).keys())
		@warning_ignore("integer_division")
		bucket = now / int(StaffCatalog.get_arrivals("wander_minutes"))
	var free: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if cell != OfficeState.entrance and pathfinder.is_walkable(cell):
			free.append(cell)
	if free.is_empty():
		return _home_spot(key)
	return _free_spot_near(free[posmod(hash([key, bucket]), free.size())], used)


# Cada personaje entra o sale según le toque estar. Quien almuerza dentro va a una mesa y vuelve.
func _update_routines() -> void:
	var lunch: Dictionary[String, bool] = Staff.get_lunch_inside(Staff.get_absolute_hour())
	var spots: Array[Vector2i] = []
	if not lunch.is_empty():
		spots = OfficeState.get_lunch_spots()
	var next_spot: int = 0
	# Pausas: los cansados van junto a un sofá.
	var resting: Array[String] = Staff.get_breaks(Staff.get_absolute_hour())
	var rest_spots: Array[Vector2i] = []
	if not resting.is_empty():
		rest_spots = OfficeState.get_rest_spots()
	var next_rest: int = 0
	# Lugares de comer o descansar ya repartidos: con más gente que lugares, uno por casilla.
	var used: Dictionary[Vector2i, bool] = {}
	var now: int = get_arrival_minute()
	var hour_start: int = Staff.get_absolute_hour() * 60
	_arrivals.clear()
	_departures.clear()
	_cleaners_on_duty = false
	_cleaning_starts.clear()
	for character: OfficeCharacter in get_characters():
		var leaving: bool = character is Employee and _departing.has(character)
		if leaving:
			_early.erase(character.person_key)
			character.update_routine(false)
			continue
		var eating: bool = lunch.has(character.person_key) and not spots.is_empty()
		if character is Employee and _arrive_staggered(character, eating, now, hour_start, used):
			continue
		if character == ceo and _ceo_opens(now, hour_start):
			continue
		if eating:
			character.set_seat(_free_spot_near(spots[next_spot % spots.size()], used))
			next_spot += 1
		elif resting.has(character.person_key) and not rest_spots.is_empty():
			character.set_seat(_free_spot_near(rest_spots[next_rest % rest_spots.size()], used))
			next_rest += 1
		else:
			character.set_seat(_home_spot(character.person_key))
		var mopping: bool = false
		if character is Employee and not eating and not resting.has(character.person_key):
			var employee: Dictionary = Staff.get_employee_by_key(character.person_key)
			mopping = is_cleaning_now(employee)
			var start: int = Staff.get_cleaning_start_minute(employee)
			if not mopping and start > GameClock.get_minute() and Staff.is_expected_now(character.person_key):
				_cleaning_starts[character.person_key] = hour_start + start
		character.cleaning = mopping
		_cleaners_on_duty = _cleaners_on_duty or mopping
		character.update_routine(eating or Staff.is_expected_now(character.person_key))
	_update_ceo_button()


## Faltan inodoros: algunos sentados salen a buscar baño y vuelven (solo visual). Devuelve cuántos.
func _send_bathroom_trips(hour: int = -1) -> int:
	if hour < 0:
		hour = Staff.get_absolute_hour()
	var shortage: int = Staff.get_bathroom_shortage(hour)
	if shortage <= 0:
		return 0
	var seated: Array[OfficeCharacter] = get_characters().filter(func(character: OfficeCharacter) -> bool:
		return character.activity == OfficeCharacter.Activity.SEATED and not (character is Employee and _departing.has(character)))
	# Cada uno sale una vez cada trip_every_hours, en su turno (por su clave); por hora, como mucho
	# los que no caben ÷ esas horas.
	var every: int = maxi(1, int(StaffCatalog.get_bathrooms("trip_every_hours")))
	var unfit: int = mini(Staff.count_present(hour), shortage * int(StaffCatalog.get_bathrooms("people_per_toilet")))
	var limit: int = ceili(float(unfit) / every)
	var count: int = 0
	for character: OfficeCharacter in seated:
		if count >= limit:
			break
		if posmod(character.person_key.hash() + hour, every) == 0:
			character.step_out()
			count += 1
	return count


## Qué está haciendo un empleado, para su ficha.
func describe_employee_activity(employee_id: int) -> String:
	var character: Employee = employees.get(employee_id)
	if character == null:
		return "—"
	var lunch: bool = Staff.is_at_lunch(character.person_key)
	match character.activity:
		OfficeCharacter.Activity.WALKING_TO_DESK:
			return "llegó temprano y espera su hora" if _early.has(character.person_key) else "llegando a su puesto"
		OfficeCharacter.Activity.SEATED:
			if _early.has(character.person_key):
				return "llegó temprano y espera su hora"
			if _departures.has(character.person_key):
				return "terminando antes de irse"
			if String(Staff.interview.get("by", "")) == character.person_key:
				return "entrevistando a %s" % Staff.get_interviewed_now().get("name", "un candidato")
			if lunch:
				return "almorzando en la Sala de descanso"
			return "descansando en la Sala de descanso" if Staff.is_on_break(character.person_key) else "trabajando"
		OfficeCharacter.Activity.WALKING_OUT:
			return "saliendo a almorzar" if lunch else "yéndose a casa"
		OfficeCharacter.Activity.STEPPING_OUT:
			return "buscando un baño fuera del edificio"
	return "almorzando fuera" if lunch else "fuera de su horario"


## Pone a cada empleado su icono de estado. Al cambiar hora, personal, oficina o proyectos; no por cuadro.
func update_status_icons() -> void:
	for employee_id: int in employees:
		var employee: Dictionary = Staff.get_employee(employee_id)
		employees[employee_id].set_status_icon("" if employee.is_empty() else Staff.get_status_icon(employee))


## Indica si no queda nadie en la oficina (ni llegando ni saliendo).
func is_office_empty() -> bool:
	for character: OfficeCharacter in get_characters():
		if character.activity != OfficeCharacter.Activity.AWAY:
			return false
	return true


# Al irse el último, el tiempo salta hasta que llegue alguien.
func _on_character_left_office() -> void:
	_remove_departed()
	if not is_office_empty() or Bank.game_over:
		return
	var hours: int = Staff.hours_until_anyone_expected()
	print("La oficina está vacía.")
	if hours <= 0:
		return
	# Salta a la hora anterior a la próxima llegada y luego al primero que entra (o a la hora en punto).
	var target: int = Staff.get_absolute_hour() + hours - 1
	if hours > 1:
		GameClock.fast_forward_hours(hours - 1)
		if Staff.get_absolute_hour() != target:
			return  # Un evento cortó el salto.
	_update_routines()
	if _arrivals.is_empty():
		GameClock.fast_forward_hours(1)
		return
	var first: int = _arrivals.values().min()
	GameClock.skip_to_minute(first - target * 60)


# Botón del CEO: lo manda a casa o a la oficina.
func _add_ceo_button(menu_bar: Container) -> void:
	_ceo_button = Button.new()
	_ceo_button.name = "CeoButton"
	_ceo_button.custom_minimum_size = Vector2(172.0, Hud.MENU_BUTTON_SIZE.y)
	_ceo_button.focus_mode = Control.FOCUS_NONE
	_ceo_button.pressed.connect(func() -> void: Staff.set_ceo_at_work(not Staff.ceo_at_work))
	menu_bar.add_child(_ceo_button)
	menu_bar.move_child(_ceo_button, _company_panel.get_open_button().get_index() + 1)
	_update_ceo_button()


func _update_ceo_button() -> void:
	if _ceo_button != null:
		_ceo_button.text = "CEO: irse a casa" if Staff.ceo_at_work else "CEO: ir a la oficina"


## Botón que manda al CEO a casa o a la oficina.
func get_ceo_button() -> Button:
	return _ceo_button


## Empleado dibujado en ese punto del mundo (el de más adelante), o null.
func employee_at(world_point: Vector2) -> Employee:
	var picked: Employee = null
	for employee_id: int in employees:
		var character: Employee = employees[employee_id]
		if character.contains_point(world_point) and (picked == null or character.position.y > picked.position.y):
			picked = character
	return picked
