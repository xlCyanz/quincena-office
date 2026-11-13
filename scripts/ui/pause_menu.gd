# Menú de pausa (hito 62, diseño 21.2): Esc lo abre cuando no hay ningún panel abierto.
# Tapa el juego con un velo y ofrece Seguir, Guardar, Cargar, Ajustes y Salir al menú.
# Guardar, Cargar y Ajustes abren el panel de Ajustes en su pestaña (main.gd lo coordina);
# Salir al menú pregunta antes, porque lo que no se guardó se pierde. Avisa con señales;
# quien lo usa pausa y devuelve el tiempo.
class_name PauseMenu
extends CanvasLayer

## Se pulsó Seguir (o Esc): cerrar la pausa.
signal resume_requested
## Se pidió el panel de Ajustes en una pestaña (SettingsPanel.TAB_SAVE, TAB_LOAD o TAB_OPTIONS).
signal settings_requested(tab: String)
## Se pidió volver al menú principal (ya confirmado).
signal quit_requested

const LAYER: int = 15
const PANEL_WIDTH: float = 360.0
const TEXT_WIDTH: float = PANEL_WIDTH - 40.0
const BUTTON_HEIGHT: float = 44.0
const TITLE_FONT_SIZE: int = 28
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.45)

var _cover: ColorRect
var _buttons_box: VBoxContainer
var _buttons: Dictionary[String, Button] = {}
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _confirm_button: Button
var _cancel_button: Button


func _ready() -> void:
	layer = LAYER
	_cover = ColorRect.new()
	_cover.color = DIM_COLOR
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Atrapa los clics: mientras está la pausa no se toca la oficina.
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(center)
	var panel: PanelContainer = Hud.make_panel()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)
	var title := Label.new()
	title.text = "Pausa"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	_buttons_box = VBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 8)
	rows.add_child(_buttons_box)
	_add_button("resume", "Seguir", func() -> void: resume_requested.emit())
	_add_button("save", "Guardar", func() -> void: settings_requested.emit(SettingsPanel.TAB_SAVE))
	_add_button("load", "Cargar", func() -> void: settings_requested.emit(SettingsPanel.TAB_LOAD))
	_add_button("settings", "Ajustes", func() -> void: settings_requested.emit(SettingsPanel.TAB_OPTIONS))
	_add_button("quit", "Salir al menú", _ask_quit)

	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 8)
	rows.add_child(_confirm_box)
	_confirm_label = Label.new()
	_confirm_label.text = "¿Salir al menú? Lo que no se guardó se pierde."
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_confirm_box.add_child(_confirm_label)
	_confirm_button = _make_button("Salir al menú")
	_confirm_button.pressed.connect(func() -> void: quit_requested.emit())
	_confirm_box.add_child(_confirm_button)
	_cancel_button = _make_button("Cancelar")
	_cancel_button.pressed.connect(cancel_confirm)
	_confirm_box.add_child(_cancel_button)
	_cover.visible = false
	cancel_confirm()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	return button


func _add_button(key: String, text: String, action: Callable) -> void:
	var button: Button = _make_button(text)
	button.name = key.capitalize()
	button.pressed.connect(action)
	_buttons_box.add_child(button)
	_buttons[key] = button


## Muestra u oculta la pausa (siempre sin la pregunta de salir).
func set_open(open: bool) -> void:
	cancel_confirm()
	_cover.visible = open
	if open:
		_buttons["resume"].grab_focus()


func is_open() -> bool:
	return _cover.visible


func _ask_quit() -> void:
	_buttons_box.visible = false
	_confirm_box.visible = true
	_cancel_button.grab_focus()


## Vuelve de la pregunta de salir a los botones.
func cancel_confirm() -> void:
	_confirm_box.visible = false
	_buttons_box.visible = true


## Indica si está preguntando antes de salir al menú.
func is_confirming() -> bool:
	return _confirm_box.visible


## Botón por clave: "resume", "save", "load", "settings" o "quit".
func get_button(key: String) -> Button:
	return _buttons[key]


func get_confirm_button() -> Button:
	return _confirm_button


func get_cancel_button() -> Button:
	return _cancel_button


## Rectángulo del panel en pantalla (para comprobar que cabe).
func get_panel_rect() -> Rect2:
	return (_cover.get_child(0).get_child(0) as Control).get_global_rect()
