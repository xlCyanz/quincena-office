# Menú Ajustes (diseño, 12.3 y hito 60): tres pestañas, Guardar (en una ranura manual),
# Cargar (el autoguardado o una ranura) y Opciones (las de Settings), y Salir al menú.
# Cargar y salir piden confirmación: lo que no se guardó se pierde. El sonido llega en la
# fase 8. Se construye en código; su botón va en la barra de menús (attach_button) y los
# botones avisan con señales.
class_name SettingsPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal settings_mode_changed(active: bool)
## Se pidió guardar en una ranura (ver SaveManager).
signal save_requested(slot: String)
## Se pidió cargar una ranura (ya confirmado).
signal load_requested(slot: String)
## Se pidió volver al menú principal (ya confirmado).
signal quit_requested

const PANEL_WIDTH: float = 460.0
## Ancho de los textos que se parten en líneas (sin ancho fijo calculan un alto enorme).
const TEXT_WIDTH: float = PANEL_WIDTH - 40.0
const TAB_SAVE: String = "save"
const TAB_LOAD: String = "load"
const TAB_OPTIONS: String = "options"
const TAB_NAMES: Dictionary[String, String] = {TAB_SAVE: "Guardar", TAB_LOAD: "Cargar", TAB_OPTIONS: "Opciones"}

var _open_button: Button
var _panel: PanelContainer
var _tab_buttons: Dictionary[String, Button] = {}
var _sections: Dictionary[String, VBoxContainer] = {}
var _tab: String = TAB_SAVE
var _slot_buttons: Dictionary[String, Button] = {}
var _load_buttons: Dictionary[String, Button] = {}
var _options: OptionsList
var _tutorial_button: Button
var _status_label: Label
var _quit_button: Button
var _close_button: Button
var _main_rows: VBoxContainer
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _confirm_button: Button
var _cancel_button: Button
var _pending: Callable


func _ready() -> void:
	_open_button = Button.new()
	_open_button.text = "Ajustes"
	_open_button.custom_minimum_size = Hud.MENU_BUTTON_SIZE
	_open_button.pressed.connect(func() -> void: set_open(true))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)
	var title := Label.new()
	title.text = "Ajustes"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	_main_rows = VBoxContainer.new()
	_main_rows.add_theme_constant_override("separation", 8)
	outer.add_child(_main_rows)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_main_rows.add_child(tabs)
	for tab: String in TAB_NAMES:
		var tab_button := Button.new()
		tab_button.text = TAB_NAMES[tab]
		tab_button.toggle_mode = true
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.pressed.connect(set_tab.bind(tab))
		tabs.add_child(tab_button)
		_tab_buttons[tab] = tab_button
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 6)
		_main_rows.add_child(section)
		_sections[tab] = section

	for slot: String in SaveManager.get_manual_slots():
		var button := _slot_button()
		button.pressed.connect(func() -> void: save_requested.emit(slot))
		_sections[TAB_SAVE].add_child(button)
		_slot_buttons[slot] = button
	var load_slots: Array[String] = [SaveManager.AUTOSAVE]
	load_slots.append_array(SaveManager.get_manual_slots())
	for slot: String in load_slots:
		var button := _slot_button()
		button.pressed.connect(_ask_load.bind(slot))
		_sections[TAB_LOAD].add_child(button)
		_load_buttons[slot] = button
	_options = OptionsList.new()
	_sections[TAB_OPTIONS].add_child(_options)
	# Tutorial (hito 63): se retoma donde quedó o se vuelve a empezar si se terminó.
	_tutorial_button = Button.new()
	_tutorial_button.custom_minimum_size = Vector2(0, 44)
	_tutorial_button.pressed.connect(_on_tutorial_pressed)
	_sections[TAB_OPTIONS].add_child(_tutorial_button)
	EventBus.tutorial_changed.connect(_refresh_tutorial_button)
	_refresh_tutorial_button()

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_main_rows.add_child(_status_label)
	_quit_button = Button.new()
	_quit_button.text = "Salir al menú"
	_quit_button.pressed.connect(_ask_quit)
	_main_rows.add_child(_quit_button)
	_close_button = Button.new()
	_close_button.text = "Cerrar"
	_close_button.pressed.connect(func() -> void: set_open(false))
	_main_rows.add_child(_close_button)

	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 8)
	_confirm_box.visible = false
	outer.add_child(_confirm_box)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_box.add_child(_confirm_label)
	_confirm_button = Button.new()
	_confirm_button.pressed.connect(_confirm)
	_confirm_box.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancelar"
	_cancel_button.pressed.connect(cancel_confirm)
	_confirm_box.add_child(_cancel_button)

	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	set_tab(TAB_SAVE)


# Al cambiar de pestaña o de pregunta cambia el alto: se vuelve a centrar con su tamaño
# mínimo (después de que los contenedores lo recalculen).
func _fit() -> void:
	_panel.reset_size()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _queue_fit() -> void:
	_fit()
	_fit.call_deferred()


func _slot_button() -> Button:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 40)
	return button


## Pone el botón "Ajustes" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open:
		refresh_slots()
		refresh_options()
		cancel_confirm()
		_status_label.text = "El tiempo está en pausa."
	_panel.visible = open
	_open_button.disabled = open
	settings_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


## Muestra una pestaña (TAB_SAVE, TAB_LOAD o TAB_OPTIONS).
func set_tab(tab: String) -> void:
	_tab = tab
	for name: String in _sections:
		_sections[name].visible = name == tab
		_tab_buttons[name].button_pressed = name == tab
	_queue_fit()


func get_tab() -> String:
	return _tab


## Vuelve a leer qué hay en cada ranura.
func refresh_slots() -> void:
	for slot: String in _slot_buttons:
		_slot_buttons[slot].text = SaveManager.describe_slot(slot)
	for slot: String in _load_buttons:
		_load_buttons[slot].text = SaveManager.describe_slot(slot)
		_load_buttons[slot].disabled = not SaveManager.has_save(slot)


## Pone los controles de Opciones como están las opciones (sin volver a guardarlas).
func refresh_options() -> void:
	_options.refresh()


func _refresh_tutorial_button() -> void:
	_tutorial_button.disabled = Tutorial.active
	if Tutorial.active:
		_tutorial_button.text = "El tutorial está en curso"
	elif Tutorial.finished:
		_tutorial_button.text = "Volver a empezar el tutorial"
	else:
		_tutorial_button.text = "Retomar el tutorial"


# Retoma el tutorial y cierra Ajustes para que se vea el paso.
func _on_tutorial_pressed() -> void:
	Tutorial.resume()
	set_open(false)


## Botón para retomar o volver a empezar el tutorial (pestaña Opciones).
func get_tutorial_button() -> Button:
	return _tutorial_button


func show_status(text: String) -> void:
	_status_label.text = text


func _ask_load(slot: String) -> void:
	_ask("¿Cargar la %s? Lo que no se guardó de esta partida se pierde." % SaveManager.get_slot_name(slot).to_lower(),
		"Cargar", func() -> void: load_requested.emit(slot))


func _ask_quit() -> void:
	_ask("¿Salir al menú? Lo que no se guardó se pierde.", "Salir al menú", func() -> void: quit_requested.emit())


func _ask(text: String, confirm_text: String, action: Callable) -> void:
	_pending = action
	_confirm_label.text = text
	_confirm_button.text = confirm_text
	_main_rows.visible = false
	_confirm_box.visible = true
	_queue_fit()


func _confirm() -> void:
	var action: Callable = _pending
	cancel_confirm()
	if action.is_valid():
		action.call()


## Vuelve de la pregunta (cargar o salir) a las pestañas.
func cancel_confirm() -> void:
	_pending = Callable()
	_confirm_box.visible = false
	_main_rows.visible = true
	_queue_fit()


## Indica si está preguntando antes de cargar o salir.
func is_confirming() -> bool:
	return _confirm_box.visible


func get_confirm_text() -> String:
	return _confirm_label.text


## Rectángulo del panel en pantalla (para comprobar que cabe).
func get_panel_rect() -> Rect2:
	return _panel.get_global_rect()


func get_open_button() -> Button:
	return _open_button


func get_tab_button(tab: String) -> Button:
	return _tab_buttons[tab]


func get_slot_button(slot: String) -> Button:
	return _slot_buttons[slot]


func get_load_button(slot: String) -> Button:
	return _load_buttons[slot]


func get_option_toggle(key: String) -> CheckBox:
	return _options.get_toggle(key)


func get_speed_button() -> OptionButton:
	return _options.get_speed_button()


func get_quit_button() -> Button:
	return _quit_button


func get_confirm_button() -> Button:
	return _confirm_button


func get_cancel_button() -> Button:
	return _cancel_button


func get_close_button() -> Button:
	return _close_button
