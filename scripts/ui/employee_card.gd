# Ficha de empleado (diseño, 12.4): nombre, cargo, nivel, equipo, horario, qué está
# haciendo, barras de energía, ánimo y estrés, habilidades, rasgos conocidos y sueldo.
# Por ahora solo informa: los botones de aumento, ascenso, equipo, horario y despido
# llegan en sus hitos.
#
# Se abre con un clic en el empleado o desde Personal, no pausa el tiempo y se
# actualiza sola. Va a la derecha, debajo del reloj. Lo que el empleado está haciendo
# lo sabe la escena de juego, que lo da con status_provider.
class_name EmployeeCard
extends CanvasLayer

const PANEL_WIDTH: float = 360.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 140.0
const TITLE_FONT_SIZE: int = 22
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
## Barras de la ficha: clave en el empleado y nombre para el jugador.
const BARS: Dictionary[String, String] = {"energy": "Energía", "mood": "Ánimo", "stress": "Estrés"}
const BAR_COLORS: Dictionary[String, Color] = {
	"energy": Color("5aa84f"), "mood": Color("4a7fc1"), "stress": Color("c9553f"),
}

## Devuelve qué está haciendo un empleado ("Trabajando", …) a partir de su id.
var status_provider: Callable = Callable()

var _panel: PanelContainer
var _title: Label
var _info: Label
var _details: Label
var _bars: Dictionary[String, ProgressBar] = {}
var _bar_values: Dictionary[String, Label] = {}
var _employee_id: int = 0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -MARGIN - PANEL_WIDTH
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN_TOP
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_info)
	for bar: String in BARS:
		var line := HBoxContainer.new()
		rows.add_child(line)
		var name_label := Label.new()
		name_label.text = BARS[bar]
		name_label.custom_minimum_size = Vector2(80, 0)
		line.add_child(name_label)
		var progress := ProgressBar.new()
		progress.min_value = 0.0
		progress.max_value = 100.0
		progress.show_percentage = false
		progress.custom_minimum_size = Vector2(0, 18)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS[bar]
		fill.set_corner_radius_all(3)
		progress.add_theme_stylebox_override("fill", fill)
		line.add_child(progress)
		var value := Label.new()
		value.custom_minimum_size = Vector2(40, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		_bars[bar] = progress
		_bar_values[bar] = value
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_details)

	_panel.visible = false
	EventBus.staff_changed.connect(_refresh)
	EventBus.hour_changed.connect(func(_hour: int) -> void: _refresh())


## Abre la ficha de un empleado (o la cambia a otro).
func open_employee(employee_id: int) -> void:
	_employee_id = employee_id
	_panel.visible = true
	_refresh()


func close() -> void:
	_panel.visible = false


func is_open() -> bool:
	return _panel.visible


## Id del empleado de la ficha abierta.
func get_employee_id() -> int:
	return _employee_id


## Valor de una barra ("energy", "mood" o "stress").
func get_bar_value(bar: String) -> float:
	return _bars[bar].value


## Todo el texto de la ficha (para las pruebas).
func get_text() -> String:
	var texts: Array[String] = [_title.text, _info.text]
	for bar: String in BARS:
		texts.append("%s %s" % [BARS[bar], _bar_values[bar].text])
	texts.append(_details.text)
	return "\n".join(texts)


## Vuelve a leer los datos (también lo hace sola al cambiar el personal o la hora).
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _panel == null or not is_open():
		return
	var employee: Dictionary = Staff.get_employee(_employee_id)
	if employee.is_empty():
		close()
		return
	_title.text = employee["name"]
	var lunch: int = int(StaffCatalog.get_workday("lunch_hour"))
	_info.text = "\n".join([
		"%s, %d años" % [Staff.describe_employee(employee), employee["age"]],
		"Equipo: sin equipo",
		"Horario: %s · almuerzo %d:00–%d:00" % [Staff.get_schedule(employee).describe(), lunch, lunch + 1],
		"Ahora: %s" % (String(status_provider.call(_employee_id)) if status_provider.is_valid() else "—"),
	])
	for bar: String in BARS:
		var value: int = int(employee[bar])
		_bars[bar].value = value
		_bar_values[bar].text = str(value)
	var details: Array[String] = ["Habilidades: %s" % Staff.describe_skills(employee)]
	var known: String = Staff.describe_known_traits(employee)
	details.append(known if not known.is_empty() else "Rasgos: ninguno conocido todavía")
	_details.text = "\n".join(details)
