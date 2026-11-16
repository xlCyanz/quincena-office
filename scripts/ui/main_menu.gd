# Menú principal: Continuar (la partida más reciente), Nueva partida, Cargar, Ajustes y Salir.
# Cada vista reemplaza a los botones; «Volver» o «Cancelar» regresan.
extends Control

const GAME_SCENE_PATH: String = "res://scenes/main.tscn"
const SLOT_BUTTON_SIZE := Vector2(460, 44)
const VIEW_BUTTONS: String = "buttons"
const VIEW_LOAD: String = "load"
const VIEW_OPTIONS: String = "options"
const VIEW_CONFIRM: String = "confirm"
## Ancho de los textos que se parten en líneas.
const TEXT_WIDTH: float = 460.0

## Lo que hace «Salir»; las pruebas lo cambian para no cerrar el juego.
var quit_action: Callable = func() -> void: get_tree().quit()
## Abre la escena de juego; las pruebas lo cambian para quedarse en el menú.
var change_scene: Callable = func(path: String) -> void: get_tree().change_scene_to_file(path)

var _view: String = VIEW_BUTTONS
var _options_box: VBoxContainer
var _options: OptionsList
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _confirm_button: Button
var _cancel_button: Button

@onready var _continue_button: Button = %ContinueButton
@onready var _new_game_button: Button = %NewGameButton
@onready var _load_button: Button = %LoadButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _load_list: VBoxContainer = %LoadList


func _ready() -> void:
	# El suelo de la partida se pinta mientras se ve el menú (tarda ~1 s).
	OfficeGrid.prepare_tile_set.call_deferred()
	var latest: String = SaveManager.get_latest_slot()
	_continue_button.visible = not latest.is_empty()
	_continue_button.tooltip_text = SaveManager.describe_slot(latest) if not latest.is_empty() else ""
	_continue_button.pressed.connect(_on_continue_pressed)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_show.bind(VIEW_LOAD))
	_load_button.disabled = not SaveManager.has_any_save()
	_settings_button.pressed.connect(_show.bind(VIEW_OPTIONS))
	_quit_button.pressed.connect(func() -> void: quit_action.call())
	_build_load_list()
	_build_options()
	_build_confirm()
	_show(VIEW_BUTTONS)
	if _continue_button.visible:
		_continue_button.grab_focus()
	else:
		_new_game_button.grab_focus()


## Vista actual (VIEW_BUTTONS, VIEW_LOAD, VIEW_OPTIONS o VIEW_CONFIRM).
func get_view() -> String:
	return _view


## Botón de una ranura en la lista de carga (null si no existe).
func get_slot_button(slot: String) -> Button:
	return _load_list.get_node_or_null(slot) as Button


func get_continue_button() -> Button:
	return _continue_button


func get_new_game_button() -> Button:
	return _new_game_button


func get_settings_button() -> Button:
	return _settings_button


func get_quit_button() -> Button:
	return _quit_button


func get_options() -> OptionsList:
	return _options


func get_confirm_text() -> String:
	return _confirm_label.text


func get_confirm_button() -> Button:
	return _confirm_button


func get_cancel_button() -> Button:
	return _cancel_button


## Botón «Volver» de la vista actual (cargar u opciones).
func get_back_button() -> Button:
	return (_options_box if _view == VIEW_OPTIONS else _load_list).get_node("Back") as Button


func _build_load_list() -> void:
	var slots: Array[String] = [SaveManager.AUTOSAVE]
	slots.append_array(SaveManager.get_manual_slots())
	for slot: String in slots:
		var button := Button.new()
		button.name = slot
		button.text = SaveManager.describe_slot(slot)
		button.custom_minimum_size = SLOT_BUTTON_SIZE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not SaveManager.has_save(slot)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		_load_list.add_child(button)
	_load_list.add_child(_back_button())


func _build_options() -> void:
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 12)
	_options_box.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_load_list.get_parent().add_child(_options_box)
	_options = OptionsList.new()
	_options_box.add_child(_options)
	_options_box.add_child(_back_button())


func _build_confirm() -> void:
	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 12)
	_load_list.get_parent().add_child(_confirm_box)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_confirm_box.add_child(_confirm_label)
	_confirm_button = Button.new()
	_confirm_button.text = "Empezar una nueva"
	_confirm_button.custom_minimum_size = SLOT_BUTTON_SIZE
	_confirm_button.pressed.connect(_start_new_game)
	_confirm_box.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancelar"
	_cancel_button.custom_minimum_size = SLOT_BUTTON_SIZE
	_cancel_button.pressed.connect(_show.bind(VIEW_BUTTONS))
	_confirm_box.add_child(_cancel_button)


func _back_button() -> Button:
	var back := Button.new()
	back.name = "Back"
	back.text = "Volver"
	back.custom_minimum_size = SLOT_BUTTON_SIZE
	back.pressed.connect(_show.bind(VIEW_BUTTONS))
	return back


func _show(view: String) -> void:
	_view = view
	var buttons: bool = view == VIEW_BUTTONS
	_continue_button.visible = buttons and not SaveManager.get_latest_slot().is_empty()
	for button: Button in [_new_game_button, _load_button, _settings_button, _quit_button]:
		button.visible = buttons
	_load_list.visible = view == VIEW_LOAD
	_options_box.visible = view == VIEW_OPTIONS
	_confirm_box.visible = view == VIEW_CONFIRM


func _on_continue_pressed() -> void:
	var slot: String = SaveManager.get_latest_slot()
	if not slot.is_empty():
		_on_slot_pressed(slot)


# Con autoguardado se pregunta antes: se reemplaza el primer día (las ranuras manuales quedan).
func _on_new_game_pressed() -> void:
	if not SaveManager.has_save(SaveManager.AUTOSAVE):
		_start_new_game()
		return
	_confirm_label.text = "Ya hay una partida en curso (%s). Al empezar otra se reemplazará el autoguardado; las ranuras manuales quedan. ¿Empezar una nueva?" % (
		SaveManager.describe_slot(SaveManager.AUTOSAVE).trim_prefix(SaveManager.get_slot_name(SaveManager.AUTOSAVE) + " — "))
	_show(VIEW_CONFIRM)


func _start_new_game() -> void:
	SaveManager.new_game()
	change_scene.call(GAME_SCENE_PATH)


func _on_slot_pressed(slot: String) -> void:
	if SaveManager.load_game(slot):
		change_scene.call(GAME_SCENE_PATH)
	else:
		var button: Button = get_slot_button(slot)
		button.text = "%s — no se pudo cargar" % SaveManager.get_slot_name(slot)
		button.disabled = true
		_continue_button.disabled = slot == SaveManager.get_latest_slot()
