# Menú Ajustes mínimo (diseño, 12.3): guardar en una de las ranuras y salir al menú
# principal. Sonido y opciones llegan en una fase siguiente. Se construye en código; su
# botón va en la barra de menús (attach_button) y los botones avisan con señales.
class_name SettingsPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal settings_mode_changed(active: bool)
## Se pidió guardar en una ranura (ver SaveManager).
signal save_requested(slot: String)
## Se pidió volver al menú principal.
signal quit_requested

const PANEL_WIDTH: float = 460.0

var _open_button: Button
var _panel: PanelContainer
var _slot_buttons: Dictionary[String, Button] = {}
var _status_label: Label
var _quit_button: Button
var _close_button: Button


func _ready() -> void:
	_open_button = Button.new()
	_open_button.text = "Ajustes"
	_open_button.custom_minimum_size = Vector2(160, 44)
	_open_button.pressed.connect(func() -> void: set_open(true))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)
	var title := Label.new()
	title.text = "Ajustes"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	var save_label := Label.new()
	save_label.text = "Guardar en:"
	rows.add_child(save_label)
	for slot: String in SaveManager.get_manual_slots():
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: save_requested.emit(slot))
		rows.add_child(button)
		_slot_buttons[slot] = button
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_status_label)
	_quit_button = Button.new()
	_quit_button.text = "Salir al menú (lo que no se guardó se pierde)"
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	rows.add_child(_quit_button)
	_close_button = Button.new()
	_close_button.text = "Cerrar"
	_close_button.pressed.connect(func() -> void: set_open(false))
	rows.add_child(_close_button)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false


## Pone el botón "Ajustes" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open:
		refresh_slots()
		_status_label.text = "El tiempo está en pausa."
	_panel.visible = open
	_open_button.disabled = open
	settings_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


## Vuelve a leer qué hay en cada ranura.
func refresh_slots() -> void:
	for slot: String in _slot_buttons:
		_slot_buttons[slot].text = SaveManager.describe_slot(slot)


func show_status(text: String) -> void:
	_status_label.text = text


func get_open_button() -> Button:
	return _open_button


func get_slot_button(slot: String) -> Button:
	return _slot_buttons[slot]


func get_quit_button() -> Button:
	return _quit_button


func get_close_button() -> Button:
	return _close_button
