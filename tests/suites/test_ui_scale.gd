# Prueba del hito 65: interfaz escalable.
# Criterio: a 150 % en 1280×720 ningún panel se sale de la pantalla ni tapa la barra; todos
# los botones miden al menos 44 px. También 100 y 125 %, la opción (se guarda y se valida) y
# las descripciones emergentes de los botones sin texto.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=ui_scale
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE_DIR: String = "user://test_saves"
const LEFT_PANELS: Array[String] = ["StaffPanel", "ProjectsPanel", "TeamsPanel", "BankPanel", "CompanyPanel"]
## Tolerancia de redondeo al comparar rectángulos.
const EPSILON: float = 0.5

var _failures: int = 0
var _checks: int = 0
var _aspect_before: Window.ContentScaleAspect
# Botones vistos en cada estado (para medirlos y revisar sus descripciones).
# Ruta → {"height", "text", "tooltip"}.
var _seen_buttons: Dictionary[String, Dictionary] = {}


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	Settings.reset_to_defaults()
	# Sin ventana la pantalla mide lo que diga la escala sobre 1280×720 (sin estirar).
	_aspect_before = get_tree().root.content_scale_aspect
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_check_option()
	for percent: int in [100, 125, 150]:
		await _check_scale(percent)
	Settings.reset_to_defaults()
	get_tree().root.content_scale_aspect = _aspect_before
	await get_tree().process_frame
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _wait(frames: int = 3) -> void:
	for i: int in range(frames):
		await get_tree().process_frame


func _check_option() -> void:
	_expect(Settings.get_value("ui_scale") == 100 and is_equal_approx(get_tree().root.content_scale_factor, 1.0),
		"por defecto la interfaz va al 100 %")
	_expect(Settings.get_ui_scales() == ([100, 125, 150] as Array[int]), "escalas: %s" % [Settings.get_ui_scales()])
	_expect(not Settings.set_value("ui_scale", 175) and not Settings.set_value("ui_scale", "150") and not Settings.set_value("ui_scale", 99.5),
		"una escala que no está en la lista no sirve")
	_expect(Settings.set_value("ui_scale", 125) and is_equal_approx(get_tree().root.content_scale_factor, 1.25),
		"elegir 125 % escala la ventana")
	Settings.load_settings()
	_expect(Settings.get_value("ui_scale") == 125 and is_equal_approx(get_tree().root.content_scale_factor, 1.25),
		"la escala se guarda y se aplica al leer las opciones")
	var options := OptionsList.new()
	add_child(options)
	_expect(options.get_scale_button().selected == 1 and options.get_scale_button().get_item_text(1) == "125 %",
		"el control muestra la escala: %s" % options.get_scale_button().get_item_text(options.get_scale_button().selected))
	options.get_scale_button().select(2)
	options.get_scale_button().item_selected.emit(2)
	_expect(Settings.get_value("ui_scale") == 150, "elegir 150 % en las opciones")
	options.queue_free()
	Settings.reset_to_defaults()
	_expect(is_equal_approx(get_tree().root.content_scale_factor, 1.0), "los valores por defecto vuelven al 100 %")


func _check_scale(percent: int) -> void:
	Settings.set_value("ui_scale", percent)
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	SaveManager.start_with_demo = false
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await _wait(4)
	GameClock.stop()
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var expected := Vector2(1280.0, 720.0) / (percent / 100.0)
	_expect(screen.size.is_equal_approx(expected), "%d %%: la pantalla mide %s" % [percent, screen.size])
	var build: BuildPanel = game.get_node("BuildPanel")
	var bar: Control = build.get_menu_bar()
	var hud: Hud = game.get_node("Hud")
	_seen_buttons.clear()
	_fits(percent, "la barra de menús", bar.get_global_rect(), screen, Rect2())
	for corner: Rect2 in hud.get_corner_rects():
		_fits(percent, "el dinero y el reloj", corner, screen, bar.get_global_rect())
	_collect(game)
	# Paneles de la izquierda, y la ficha de un empleado con Personal abierto.
	for panel_name: String in LEFT_PANELS:
		var panel: CanvasLayer = game.get_node(panel_name)
		panel.call("set_open", true)
		await _wait()
		var control: Control = panel.get("_panel")
		_fits(percent, panel_name, control.get_global_rect(), screen, bar.get_global_rect())
		_collect(game)
		panel.call("set_open", false)
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	staff_panel.set_open(true)
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(int(Staff.employees[0]["id"]))
	await _wait()
	_fits(percent, "la ficha", (card.get("_panel") as Control).get_global_rect(), screen, bar.get_global_rect())
	_collect(game)
	card.close()
	staff_panel.set_open(false)
	# Evento.
	Events.trigger("birthday")
	await _wait()
	var event_card: EventCard = game.get_node("EventCard")
	_expect(event_card.is_showing(), "%d %%: sale la tarjeta del evento" % percent)
	_fits(percent, "la tarjeta del evento", (event_card.get("_panel") as Control).get_global_rect(), screen, bar.get_global_rect())
	_collect(game)
	Events.choose(0)
	# Tutorial: entre el dinero y el reloj, o bajo el reloj, sin taparlos.
	Tutorial.import_state({"active": true, "finished": false, "step": "camera"})
	await _wait()
	var tutorial: TutorialPanel = game.get_tutorial_panel()
	_fits(percent, "la tarjeta del tutorial", tutorial.get_panel_rect(), screen, bar.get_global_rect())
	for corner: Rect2 in hud.get_corner_rects():
		_expect(not tutorial.get_panel_rect().grow(-EPSILON).intersects(corner), "%d %%: la tarjeta del tutorial no tapa %s" % [percent, corner])
	_collect(game)
	Tutorial.import_state({})
	# Construir (la barra se oculta mientras tanto).
	build.set_build_mode(true)
	await _wait()
	_fits(percent, "Construir", (build.get("_panel") as Control).get_global_rect(), screen, Rect2())
	for corner: Rect2 in hud.get_corner_rects():
		_expect(not (build.get("_panel") as Control).get_global_rect().intersects(corner), "%d %%: Construir no tapa el dinero ni el reloj" % percent)
	build.select_tool(BuildController.TOOL_LAND)
	await _wait()
	_fits(percent, "Construir con el terreno", (build.get("_panel") as Control).get_global_rect(), screen, Rect2())
	_collect(game)
	build.select_tool(BuildController.TOOL_WALL)
	build.set_build_mode(false)
	await _wait()
	# Ajustes en cada pestaña, la pausa y la ayuda.
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	settings.set_open(true)
	for tab: String in SettingsPanel.TAB_NAMES:
		settings.set_tab(tab)
		await _wait()
		_fits(percent, "Ajustes · %s" % tab, settings.get_panel_rect(), screen, Rect2())
		_collect(game)
	settings.set_open(false)
	game.set_pause_menu_open(true)
	await _wait()
	_fits(percent, "la pausa", game.get_pause_menu().get_panel_rect(), screen, Rect2())
	_collect(game)
	game.set_pause_menu_open(false)
	var help: HelpDialog = game.get_help_dialog()
	for topic: String in help.get_topics():
		help.show_topic(topic)
		await _wait()
		_fits(percent, "la ayuda de %s" % topic, help.get_panel_rect(), screen, Rect2())
	_collect(game)
	help.close()
	# Pantallas de fin y de bolsa (tapan todo; se miran al final).
	var stats: Dictionary = Company.get_ipo_stats()
	for screen_name: String in ["GameOverScreen", "IpoScreen"]:
		var cover: CanvasLayer = game.get_node(screen_name)
		cover.call("show_stats", stats)
		await _wait()
		var box: Control = cover.find_children("*", "PanelContainer", true, false)[0]
		_fits(percent, screen_name, box.get_global_rect(), screen, Rect2())
		_collect(game)
		(cover.get_child(0) as Control).visible = false
	# Botones: todos de 44 px, y los que no tienen palabras llevan descripción.
	var low: Array[String] = []
	var silent: Array[String] = []
	var letters := RegEx.create_from_string("[A-Za-zÁÉÍÓÚáéíóúÑñ]")
	for path: String in _seen_buttons:
		var seen: Dictionary = _seen_buttons[path]
		if float(seen["height"]) < Settings.get_min_button_height() - EPSILON:
			low.append("%s (%s)" % [path, seen["height"]])
		if letters.search(String(seen["text"])) == null and String(seen["tooltip"]).is_empty():
			silent.append("%s «%s»" % [path, seen["text"]])
	_expect(_seen_buttons.size() > 100, "%d %%: se revisaron %d botones" % [percent, _seen_buttons.size()])
	_expect(low.is_empty(), "%d %%: botones de menos de 44 px: %s" % [percent, low.slice(0, 8)])
	_expect(silent.is_empty(), "%d %%: botones sin texto ni descripción: %s" % [percent, silent.slice(0, 8)])
	game.queue_free()
	await _wait(2)


# El rectángulo entra en la pantalla y no tapa la barra (si se da).
func _fits(percent: int, what: String, rect: Rect2, screen: Rect2, bar: Rect2) -> void:
	_expect(screen.grow(EPSILON).encloses(rect) and rect.has_area(), "%d %%: %s cabe en la pantalla: %s en %s" % [percent, what, rect, screen.size])
	if bar.has_area():
		_expect(not rect.grow(-EPSILON).intersects(bar), "%d %%: %s no tapa la barra: %s, barra %s" % [percent, what, rect, bar])


# Anota los botones que se ven ahora con su alto.
func _collect(game: Node) -> void:
	for node: Node in game.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.is_visible_in_tree():
			_seen_buttons[str(button.get_path())] = {"height": button.size.y,
				"text": (button as Button).text if button is Button else "", "tooltip": button.tooltip_text}
