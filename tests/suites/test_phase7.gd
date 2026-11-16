# Comprobación de la fase 7: del menú principal a la primera entrega siguiendo el tutorial solo con
# el ratón (clics, arrastres y rueda sobre lo que resalta); entre pasos solo corre el reloj.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=phase7
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE_DIR: String = "user://test_saves"
## Local inicial 6×8 (Oficina Ejecutiva en 0–2 × 0–2): el resto es el Área de trabajo; el puesto va arriba a la derecha.
const AREA_CELL := Vector2i(4, 4)
const DESK_CELL := Vector2i(4, 0)
const CHAIR_CELL := Vector2i(4, 1)
## 0 = −y, 2 = +y: escritorio y silla se miran.
const DESK_ROTATION: int = 2
const CHAIR_ROTATION: int = 0
## Tope de horas de juego para esperar algo.
const MAX_WAIT_HOURS: int = 24 * 40
## Semillas de candidatos y contratos (si hace falta se sube la oferta con «+»).
const SEEDS: Array[int] = [20261113, 7, 4242]

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
# Entradas de teclado recibidas.
var _key_events: int = 0
var _mouse_events: int = 0
var _menu: Node
var _game: Node
var _rotation: int = 0
# Veces que se movió la cámara porque la interfaz tapaba una casilla.
var _camera_drags: int = 0
# Llegó al final (un error de script lo corta sin fallar comprobaciones).
var _completed: bool = false


func _ready() -> void:
	# Pantalla de 1280×720 (sin ventana mediría 1280×1280).
	var aspect_before: Window.ContentScaleAspect = get_tree().root.content_scale_aspect
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	SaveManager.save_dir = TEST_SAVE_DIR
	Settings.reset_to_defaults()
	_clear_saves()
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	for seed: int in SEEDS:
		Settings.reset_to_defaults()
		_clear_saves()
		_completed = false
		_key_events = 0
		_mouse_events = 0
		_rotation = 0
		_camera_drags = 0
		await _play(seed)
		_expect(_completed, "semilla %d: el recorrido llegó hasta el final" % seed)
		if _game != null:
			GameClock.set_speed_index(0)
			_game.queue_free()
			_game = null
			await get_tree().process_frame
	_clear_saves()
	Settings.reset_to_defaults()
	get_tree().root.content_scale_aspect = aspect_before
	await get_tree().process_frame
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_key_events += 1
	elif event is InputEventMouse:
		_mouse_events += 1


func _clear_saves() -> void:
	var dir := DirAccess.open(TEST_SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)


func _step_id() -> String:
	return String(Tutorial.get_current_step().get("id", ""))


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _mouse_button(at: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _push(motion)


func _click_at(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _move(at)
	await _push(_mouse_button(at, button, true))
	await _push(_mouse_button(at, button, false))


## Si el botón está en una lista desplazable y no se ve, antes gira la rueda.
func _click(control: Control) -> void:
	await _reveal(control)
	await _click_at(control.get_global_rect().get_center())
	await get_tree().process_frame


func _reveal(control: Control) -> void:
	var scroll: ScrollContainer = null
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			scroll = parent
			break
		parent = parent.get_parent()
	if scroll == null:
		return
	for i: int in range(60):
		var view: Rect2 = scroll.get_global_rect()
		var rect: Rect2 = control.get_global_rect()
		if view.encloses(rect):
			return
		var wheel: MouseButton = MOUSE_BUTTON_WHEEL_DOWN if rect.position.y > view.position.y else MOUSE_BUTTON_WHEEL_UP
		await _move(view.get_center())
		var event: InputEventMouseButton = _mouse_button(view.get_center(), wheel, true)
		event.factor = 1.0
		await _push(event)
		await _push(_mouse_button(view.get_center(), wheel, false))
		await get_tree().process_frame


func _drag(from: Vector2, to: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _move(from)
	await _push(_mouse_button(from, button, true))
	var last: Vector2 = from
	for index: int in range(1, 6):
		var at: Vector2 = from.lerp(to, index / 5.0)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.relative = at - last
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		last = at
		await _push(motion)
	await _push(_mouse_button(to, button, false))


## Ningún control atrapa el ratón en ese punto.
func _is_free(at: Vector2) -> bool:
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if not screen.grow(-4.0).has_point(at):
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	return get_viewport().gui_get_hovered_control() == null


## Puntos de pantalla donde se ve el mapa, del centro hacia afuera.
func _free_points() -> Array[Vector2]:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var points: Array[Vector2] = []
	for row: int in range(1, 12):
		for column: int in range(1, 12):
			var at := Vector2(size.x * column / 12.0, size.y * row / 12.0)
			if _is_free(at):
				points.append(at)
	var center: Vector2 = size / 2.0
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(center) < b.distance_to(center))
	return points


## Si la casilla queda bajo la interfaz, arrastra la cámara con el clic derecho.
func _bring_into_view(cell: Vector2i) -> void:
	for attempt: int in range(4):
		var at: Vector2 = _cell_on_screen(cell)
		if _is_free(at):
			return
		var points: Array[Vector2] = _free_points()
		if points.is_empty():
			return
		# Agarrar y soltar en puntos libres (si no, la interfaz se queda con el clic); si no hay par, mueve la mitad.
		var delta: Vector2 = points[0] - at
		var start := Vector2(-1, -1)
		for halving: int in range(4):
			for point: Vector2 in points:
				if _is_free(point + delta):
					start = point
					break
			if start.x >= 0.0:
				break
			delta /= 2.0
		if start.x < 0.0:
			return
		await _drag(start, start + delta, MOUSE_BUTTON_RIGHT)
		_camera_drags += 1


func _cell_on_screen(cell: Vector2i) -> Vector2:
	var grid: OfficeGrid = _game.find_children("*", "OfficeGrid", true, false)[0]
	return grid.get_canvas_transform() * grid.cell_to_world(cell)


## Lo que el tutorial resalta encierra el botón que se va a pulsar.
func _follows(control: Control, what: String) -> void:
	await get_tree().process_frame
	var panel: TutorialPanel = _game.get_tutorial_panel()
	await _reveal(control)
	await get_tree().process_frame
	_expect(panel.is_showing() and panel.get_frame_rect().encloses(control.get_global_rect()),
		"paso %s: el tutorial resalta %s (%s)" % [_step_id(), what, panel.get_target_key()])


## Pasa el tiempo hora por hora hasta `done` o el tope; devuelve las horas que pasaron.
func _wait_until(done: Callable, max_hours: int = MAX_WAIT_HOURS) -> int:
	var hours: int = 0
	while not bool(done.call()) and hours < max_hours:
		var scale: float = maxf(GameClock.get_time_scale(), 1.0)
		GameClock.advance(GameConstants.SECONDS_PER_GAME_HOUR / scale)
		hours += 1
		if hours % 12 == 0:
			await get_tree().process_frame
	await get_tree().process_frame
	return hours


## Abre sección y categoría si están cerradas y elige la herramienta (con follow, comprueba el resalte).
func _open_tool(tool: String, what: String, follow: bool) -> void:
	var build: BuildPanel = _game.get_node("BuildPanel")
	for i: int in range(3):
		var control: Button = build.get_button_toward(tool)
		if follow:
			await _follows(control, "%s (%s)" % [what, control.text])
		await _click(control)
		if build.get_selected_tool() == tool:
			return


## Gira con el clic derecho hasta `rotation` y coloca.
func _place(tool: String, cell: Vector2i, rotation: int) -> void:
	await _open_tool(tool, tool, false)
	await _bring_into_view(cell)
	var at: Vector2 = _cell_on_screen(cell)
	while _rotation != rotation:
		await _click_at(at, MOUSE_BUTTON_RIGHT)
		_rotation = (_rotation + 1) % 4
	await _click_at(at)


func _play(seed: int) -> void:
	# Sin partidas no hay Continuar; Nueva partida abre el juego.
	_menu = MENU_SCENE.instantiate()
	_menu.set("change_scene", func(_path: String) -> void:
		_menu.queue_free()
		_game = GAME_SCENE.instantiate()
		add_child(_game))
	add_child(_menu)
	await get_tree().process_frame
	_expect(not (_menu.call("get_continue_button") as Button).visible, "sin partidas no aparece Continuar")
	await _click(_menu.call("get_new_game_button"))
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_game != null and is_instance_valid(_game), "Nueva partida abre el juego")
	if _game == null:
		return
	# El reloj corre solo con lo que la prueba deja pasar (así no salen eventos).
	GameClock.stop()
	Staff.set_seed(seed)
	Projects.set_seed(seed)
	var panel: TutorialPanel = _game.get_tutorial_panel()
	var build: BuildPanel = _game.get_node("BuildPanel")
	var staff_panel: StaffPanel = _game.get_node("StaffPanel")
	var projects_panel: ProjectsPanel = _game.get_node("ProjectsPanel")
	var bank_panel: BankPanel = _game.get_node("BankPanel")
	var hud: Hud = _game.get_node("Hud")
	await get_tree().process_frame
	_expect(Tutorial.active and _step_id() == "camera" and panel.is_showing(), "la partida nueva empieza con el tutorial")
	_expect(Staff.employees.is_empty() and OfficeState.rooms.size() == 1, "empieza el CEO solo en su oficina")

	# 1. Cámara: arrastrar el local.
	var office_rect: Rect2 = panel.get_frame_rect()
	_expect(panel.get_target_key() == "office" and office_rect.has_area(), "paso 1: resalta el local")
	await _drag(office_rect.get_center(), office_rect.get_center() + Vector2(60, 30))
	_expect(_step_id() == "build", "arrastrar la cámara cumple el paso 1")

	# 2. Construir.
	await _follows(build.get_open_button(), "Construir")
	await _click(build.get_open_button())
	_expect(build.is_build_mode() and _step_id() == "work_area", "abrir Construir cumple el paso 2")

	# 3. Área de trabajo: herramienta y clic en el espacio libre.
	await _open_tool("work_area", "Área de trabajo", true)
	await _bring_into_view(AREA_CELL)
	await _click_at(_cell_on_screen(AREA_CELL))
	_expect(OfficeState.rooms.any(func(room: Dictionary) -> bool: return room["type"] == "work_area"),
		"un clic en el espacio libre marca el Área de trabajo")
	_expect(_step_id() == "workstation", "el Área de trabajo cumple el paso 3")

	# 4. Puesto: escritorio, computadora encima y silla delante (girar con clic derecho).
	await _open_tool("simple_desk", "Escritorio sencillo", true)
	var money_before: int = Economy.balance
	await _place("simple_desk", DESK_CELL, DESK_ROTATION)
	await _place("basic_computer", DESK_CELL, _rotation)
	await _place("basic_chair", CHAIR_CELL, CHAIR_ROTATION)
	_expect(Economy.balance < money_before, "los muebles se compraron: $%d" % (money_before - Economy.balance))
	_expect(Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.WORK_AREA).size() == 1,
		"queda un puesto de trabajo")
	_expect(_step_id() == "vacancy", "el puesto cumple el paso 4: %s" % _step_id())

	# 5. Vacante: salir de Construir, abrir Personal y publicar (programador Junior).
	await _follows(build.get_exit_button(), "Salir de Construir")
	await _click(build.get_exit_button())
	_expect(not build.is_build_mode() and not GameClock.is_paused, "salir de Construir y el tiempo vuelve a correr")
	await _follows(staff_panel.get_open_button(), "Personal")
	await _click(staff_panel.get_open_button())
	await _follows(staff_panel.get_publish_button(), "Publicar")
	await _click(staff_panel.get_publish_button())
	_expect(Staff.vacancies.size() == 1 and Staff.vacancies[0]["role"] == "programmer", "se publicó la vacante de programador")
	_expect(_step_id() == "hire", "la vacante cumple el paso 5")

	# 6. Contratar: esperar candidatos, entrevistar y ofrecer lo que pide.
	await _follows(staff_panel.get_open_button(), "Personal")
	var waited: int = await _wait_until(func() -> bool:
		return not Staff.vacancies.is_empty() and not (Staff.vacancies[0]["candidates"] as Array).is_empty())
	_expect(not (Staff.vacancies[0]["candidates"] as Array).is_empty(), "llegan candidatos (%d h)" % waited)
	var candidate: Dictionary = Staff.vacancies[0]["candidates"][0]
	var candidate_id: int = int(candidate["id"])
	var interview_button: Button = staff_panel.get_interview_button(candidate_id)
	_expect(interview_button != null and not interview_button.disabled, "se puede entrevistar al candidato")
	if interview_button == null:
		return
	await _click(interview_button)
	_expect(not Staff.get_appointment(candidate_id).is_empty(), "la entrevista quedó citada")
	# El candidato vuelve el próximo día del CEO a las 8 y la entrevista dura media hora.
	waited = await _wait_until(func() -> bool: return bool(candidate["interviewed"]), 80)
	_expect(bool(candidate["interviewed"]), "el CEO lo entrevistó a la hora citada (%d h)" % waited)
	var offer_button: Button = staff_panel.get_offer_button(candidate_id)
	_expect(offer_button != null, "tras la entrevista se puede ofrecer (%d h)" % waited)
	if offer_button == null:
		return
	var asked: int = int(candidate["asked_salary"])
	var raises: int = 0
	while staff_panel.get_offer(candidate_id) < asked and raises < 20:
		await _click(staff_panel.get_offer_step_buttons(candidate_id)[1])
		raises += 1
	_expect(staff_panel.get_offer(candidate_id) >= asked, "la oferta alcanza lo que pide: $%d de $%d (%d clics en +)" % [
		staff_panel.get_offer(candidate_id), asked, raises])
	offer_button = staff_panel.get_offer_button(candidate_id)
	await _click(offer_button)
	_expect(Staff.employees.size() == 1, "el candidato aceptó y quedó contratado")
	_expect(_step_id() == "contract", "contratar cumple el paso 6: %s" % _step_id())
	await _click(staff_panel.get_open_button())
	_expect(not staff_panel.is_open(), "cerrar Personal con su botón")

	# 7. Contrato: abrir Proyectos y aceptar la primera oferta de la bandeja.
	await _wait_until(func() -> bool: return not Projects.offers.is_empty(), 48)
	_expect(not Projects.offers.is_empty(), "hay ofertas de contratos")
	await _follows(projects_panel.get_open_button(), "Proyectos")
	await _click(projects_panel.get_open_button())
	var offer_id: int = int(Projects.offers[0]["id"])
	await _follows(projects_panel.get_accept_button(offer_id), "Aceptar")
	await _click(projects_panel.get_accept_button(offer_id))
	_expect(Projects.contracts.size() == 1, "se aceptó el contrato")
	_expect(_step_id() == "payroll", "aceptar cumple el paso 7: %s" % _step_id())
	await _click(projects_panel.get_open_button())

	# 8. Velocidad: 2x.
	await _follows(hud.get_speed_button(1), "2x")
	await _click(hud.get_speed_button(1))
	_expect(GameClock.speed_index == 1 and _step_id() == "bank", "2x cumple el paso 8: %s" % _step_id())

	# 9. Banco.
	await _follows(bank_panel.get_open_button(), "Banco")
	await _click(bank_panel.get_open_button())
	_expect(bank_panel.is_open() and _step_id() == "delivery", "abrir el Banco cumple el paso 9")
	await _click(bank_panel.get_open_button())

	# 10. Entrega: esperar a que el contrato llegue al 100 % y entregarlo desde Proyectos.
	var contract_id: int = int(Projects.contracts[0]["id"])
	waited = await _wait_until(func() -> bool:
		return Projects.contracts.is_empty() or Projects.get_done_ratio(Projects.contracts[0]) >= 1.0)
	_expect(not Projects.contracts.is_empty() and Projects.get_done_ratio(Projects.contracts[0]) >= 1.0,
		"el contrato llega al 100 %% (%d días)" % (waited / 24))
	if Projects.contracts.is_empty():
		return
	var late: bool = GameClock.get_day_count() > int(Projects.contracts[0]["deadline_day"])
	_expect(not late, "termina a tiempo (día %d, plazo %d)" % [GameClock.get_day_count(), Projects.contracts[0]["deadline_day"]])
	var balance_before: int = Economy.balance
	await _follows(projects_panel.get_open_button(), "Proyectos")
	await _click(projects_panel.get_open_button())
	await _follows(projects_panel.get_deliver_button(contract_id), "Entregar")
	_notices.clear()
	await _click(projects_panel.get_deliver_button(contract_id))
	_expect(Projects.contracts.is_empty() and Projects.delivered_count == 1, "se entregó el contrato")
	_expect(Economy.balance > balance_before, "la entrega se cobró: $%d" % (Economy.balance - balance_before))
	_expect(Tutorial.finished and not Tutorial.active and not panel.is_showing(), "la primera entrega termina el tutorial")
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("Terminaste el tutorial")), "avisa que terminó")
	_expect(Staff.employees.size() == 1 and Economy.balance > 0, "la empresa sigue en pie: $%d" % Economy.balance)

	_expect(_key_events == 0, "no se usó el teclado: %d teclas" % _key_events)
	_expect(_mouse_events > 50, "se jugó con el ratón: %d eventos" % _mouse_events)
	print("Fase 7 (semilla %d): del menú a la primera entrega en el día %d con %d eventos del ratón (%d arrastres de cámara para ver casillas) y 0 teclas; saldo $%d, reputación %.2f." % [
		seed, GameClock.get_day_count() + 1, _mouse_events, _camera_drags, Economy.balance, Projects.reputation])
	_completed = true
