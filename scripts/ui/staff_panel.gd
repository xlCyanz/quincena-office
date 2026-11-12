# Menú Personal (diseño, 12.3), por ahora con vacantes y candidatos (5.2): publicar
# una vacante (cargo, nivel, sueldo ofrecido y publicidad), ver las abiertas con sus
# candidatos, cerrarlas y descartar candidatos. Contratar llega en el hito 11.
#
# No pausa el tiempo: los candidatos llegan mientras está abierto. Ocupa el lado
# izquierdo para que la oficina siga a la vista. Se construye en código; su botón va
# en la barra de menús (attach_button) y muestra cuántos candidatos esperan.
class_name StaffPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal staff_mode_changed(active: bool)

const PANEL_WIDTH: float = 560.0
const MARGIN: float = 16.0
## Espacio que se deja arriba (dinero) y abajo (barra de menús).
const MARGIN_TOP: float = 76.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)

var _open_button: Button
var _panel: PanelContainer
var _role_option: OptionButton
var _level_option: OptionButton
var _salary_label: Label
var _table_label: Label
var _salary_down: Button
var _salary_up: Button
var _publicity_check: CheckBox
var _publish_button: Button
var _status_label: Label
var _list: VBoxContainer
var _salary: int = 0
var _vacancy_close_buttons: Dictionary[int, Button] = {}
var _discard_buttons: Dictionary[int, Button] = {}


func _ready() -> void:
	_open_button = Button.new()
	_open_button.custom_minimum_size = Vector2(160, 44)
	_open_button.pressed.connect(func() -> void: set_open(not is_open()))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = MARGIN + PANEL_WIDTH
	_panel.offset_top = MARGIN_TOP
	_panel.offset_bottom = -MARGIN_BOTTOM
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "Personal"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(close_button)

	_add_section(rows, "Nueva vacante")
	var choice_row := HBoxContainer.new()
	rows.add_child(choice_row)
	_role_option = OptionButton.new()
	for role: String in StaffCatalog.get_role_ids():
		_role_option.add_item(StaffCatalog.get_role_name(role))
	_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_option.item_selected.connect(func(_index: int) -> void: _reset_salary())
	choice_row.add_child(_role_option)
	_level_option = OptionButton.new()
	for level: String in StaffCatalog.get_level_ids():
		_level_option.add_item(StaffCatalog.get_level_name(level))
	_level_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_option.select(1)
	_level_option.item_selected.connect(func(_index: int) -> void: _reset_salary())
	choice_row.add_child(_level_option)

	var salary_row := HBoxContainer.new()
	rows.add_child(salary_row)
	var salary_title := Label.new()
	salary_title.text = "Sueldo ofrecido:"
	salary_row.add_child(salary_title)
	_salary_down = Button.new()
	_salary_down.text = "−"
	_salary_down.custom_minimum_size = Vector2(36, 0)
	_salary_down.pressed.connect(func() -> void: _change_salary(-1))
	salary_row.add_child(_salary_down)
	_salary_label = Label.new()
	_salary_label.custom_minimum_size = Vector2(130, 0)
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	salary_row.add_child(_salary_label)
	_salary_up = Button.new()
	_salary_up.text = "+"
	_salary_up.custom_minimum_size = Vector2(36, 0)
	_salary_up.pressed.connect(func() -> void: _change_salary(1))
	salary_row.add_child(_salary_up)
	_table_label = Label.new()
	_table_label.add_theme_color_override("font_color", MUTED_COLOR)
	salary_row.add_child(_table_label)

	_publicity_check = CheckBox.new()
	_publicity_check.text = "Con publicidad: %s, más candidatos durante %d días" % [
		MoneyFormat.format(int(StaffCatalog.get_hiring("publicity_cost"))), int(StaffCatalog.get_hiring("publicity_days"))]
	rows.add_child(_publicity_check)
	_publish_button = Button.new()
	_publish_button.text = "Publicar vacante"
	_publish_button.pressed.connect(_on_publish_pressed)
	rows.add_child(_publish_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_status_label)

	rows.add_child(HSeparator.new())
	_add_section(rows, "Vacantes abiertas")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_reset_salary()
	_panel.visible = false
	EventBus.staff_changed.connect(_refresh)
	EventBus.hour_changed.connect(func(_hour: int) -> void: _refresh())
	_refresh()


## Pone el botón "Personal" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_status_label.text = ""
		_refresh()
	staff_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


## Elige cargo y nivel en el formulario (como si se eligieran en las listas).
func select_role_and_level(role: String, level: String) -> void:
	_role_option.select(StaffCatalog.get_role_ids().find(role))
	_level_option.select(StaffCatalog.get_level_ids().find(level))
	_reset_salary()


func get_salary_offer() -> int:
	return _salary


func get_open_button() -> Button:
	return _open_button


func get_salary_buttons() -> Array[Button]:
	return [_salary_down, _salary_up]


func get_publicity_check() -> CheckBox:
	return _publicity_check


func get_publish_button() -> Button:
	return _publish_button


func get_status_text() -> String:
	return _status_label.text


## Botón "Cerrar vacante" de una vacante, o null.
func get_vacancy_close_button(vacancy_id: int) -> Button:
	return _vacancy_close_buttons.get(vacancy_id)


## Botón "Descartar" de un candidato, o null.
func get_discard_button(candidate_id: int) -> Button:
	return _discard_buttons.get(candidate_id)


## Todo el texto de la lista de vacantes (para las pruebas).
func get_list_text() -> String:
	var texts: Array[String] = []
	for label: Node in _list.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return "\n".join(texts)


func _add_section(parent: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	parent.add_child(label)


func _selected_role() -> String:
	return StaffCatalog.get_role_ids()[_role_option.selected]


func _selected_level() -> String:
	return StaffCatalog.get_level_ids()[_level_option.selected]


# Al cambiar cargo o nivel, el sueldo vuelve al de la tabla.
func _reset_salary() -> void:
	_salary = StaffCatalog.get_salary(_selected_role(), _selected_level())
	_table_label.text = "(tabla: %s)" % MoneyFormat.format(_salary)
	_update_salary()


func _change_salary(direction: int) -> void:
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_salary = maxi(step, _salary + direction * step)
	_update_salary()


func _update_salary() -> void:
	_salary_label.text = "%s al mes" % MoneyFormat.format(_salary)
	_salary_down.disabled = _salary <= int(StaffCatalog.get_hiring("salary_step"))


func _on_publish_pressed() -> void:
	var result: Dictionary = Staff.open_vacancy(_selected_role(), _selected_level(), _salary,
		_publicity_check.button_pressed)
	_status_label.text = result["message"]
	if result["ok"]:
		_publicity_check.button_pressed = false


func _refresh() -> void:
	var waiting: int = Staff.get_waiting_count()
	_open_button.text = "Personal (%d)" % waiting if waiting > 0 else "Personal"
	if _list == null or not is_open():
		return
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_vacancy_close_buttons.clear()
	_discard_buttons.clear()
	if Staff.vacancies.is_empty():
		_list.add_child(_muted_label("No hay vacantes abiertas."))
		return
	for vacancy: Dictionary in Staff.vacancies:
		_add_vacancy(vacancy)


func _add_vacancy(vacancy: Dictionary) -> void:
	var header := HBoxContainer.new()
	_list.add_child(header)
	var title := Label.new()
	title.text = Staff.describe_vacancy(vacancy)
	var publicity_left: int = Staff.publicity_days_left(vacancy)
	if publicity_left > 0:
		title.text += " · publicidad %d %s" % [publicity_left, "día" if publicity_left == 1 else "días"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Cerrar vacante"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vacancy_id: int = vacancy["id"]
	close_button.pressed.connect(func() -> void: Staff.close_vacancy(vacancy_id))
	header.add_child(close_button)
	_vacancy_close_buttons[vacancy_id] = close_button

	var candidates: Array[Dictionary] = vacancy["candidates"]
	if candidates.is_empty():
		_list.add_child(_muted_label("Sin candidatos todavía. Llegan cada día a las %02d:00." % int(
			StaffCatalog.get_hiring("arrival_hour"))))
	for candidate: Dictionary in candidates:
		_add_candidate(candidate)
	_list.add_child(HSeparator.new())


func _add_candidate(candidate: Dictionary) -> void:
	var row := HBoxContainer.new()
	_list.add_child(row)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var days_left: int = Staff.candidate_days_left(candidate)
	var leaving: String = "se va hoy" if days_left == 0 else ("se va mañana" if days_left == 1 else "se va en %d días" % days_left)
	info.text = "%s, %d años · pide %s · %s\n%s" % [candidate["name"], candidate["age"],
		MoneyFormat.format(candidate["asked_salary"]), leaving, Staff.describe_skills(candidate)]
	row.add_child(info)
	var discard := Button.new()
	discard.text = "Descartar"
	discard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var candidate_id: int = candidate["id"]
	discard.pressed.connect(func() -> void: Staff.discard_candidate(candidate_id))
	row.add_child(discard)
	_discard_buttons[candidate_id] = discard


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label
