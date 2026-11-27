# Personal, capa 1: constantes, estado y piezas comunes (etiquetas, chips, barras y fotos).
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal staff_mode_changed(active: bool)
## Se pidió ver la ficha de un empleado.
signal employee_selected(employee_id: int)
## Se mostró otra pestaña (main cierra la ficha fuera de Empleados).
signal tab_shown(tab: int)
## Cambió dónde empiezan las pestañas (get_body_top): main mueve la ficha.
signal body_moved

## Rectángulo que el panel no tapa (la tarjeta del tutorial): empieza debajo de él.
var avoid_provider: Callable = func() -> Rect2: return Rect2()

## Ancho del panel angosto de antes: el tutorial no se pone a la izquierda de esto.
const PANEL_WIDTH: float = 560.0
const MARGIN: float = 16.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := UiTheme.MUTED
## Pestañas del panel.
const TAB_EMPLOYEES: int = 0
const TAB_HIRING: int = 1
const TAB_ORG: int = 2
const TAB_NAMES: Array[String] = ["Empleados", "Vacantes", "Organigrama"]
## Tarjeta de empleado: ancho mínimo (las columnas salen del ancho), alto, foto y globo de estado.
const CARD_MIN_WIDTH: float = 250.0
const CARD_HEIGHT: float = 84.0
const CARD_PHOTO: float = 56.0
const CARD_ICON: Vector2 = Vector2(22, 24)
## Nombre de cada globo de estado (Staff.get_status_icon) para el texto de ayuda.
const STATUS_NAMES: Dictionary[String, String] = {
	"no_station": "Sin puesto", "tired": "Cansado", "upset": "Molesto", "stressed": "Estresado", "idle": "Sin proyecto",
}
## Plural de cada globo para el resumen de avisos.
const STATUS_PLURALS: Dictionary[String, String] = {
	"no_station": "sin puesto", "tired": "cansados", "upset": "molestos", "stressed": "estresados", "idle": "sin proyecto",
}
## Áreas del filtro de Empleados: id → [nombre, cargos].
const AREAS: Dictionary[String, Array] = {
	"programming": ["Programación", ["programmer"]], "design": ["Diseño", ["designer"]], "qa": ["QA", ["qa"]],
	"sales": ["Ventas", ["salesperson"]], "leadership": ["Liderazgo", ["team_leader", "manager", "executive"]],
	"services": ["Servicios", ["accountant", "receptionist", "cleaner"]],
}
const AREA_ALL: String = "all"
## Órdenes de Empleados.
const SORT_TEAM: int = 0
const SORT_ROLE: int = 1
const SORT_SALARY: int = 2
const SORT_MOOD: int = 3
const SORT_ENERGY: int = 4
const SORT_NAMES: Array[String] = ["Por equipo", "Por cargo", "Por sueldo", "Ánimo (bajo primero)", "Energía (baja primero)"]
## Vacantes: ancho del formulario y de cada candidato.
const FORM_WIDTH: float = 400.0
const CANDIDATE_MIN_WIDTH: float = 300.0
const CANDIDATE_PHOTO: float = 64.0
## Organigrama: fotos de jefes, líderes y miembros.
const BOSS_PHOTO: float = 52.0
const LEADER_PHOTO: float = 44.0
const MEMBER_PHOTO: float = 24.0
## Miembros que se muestran en la ficha de un equipo.
const TEAM_FACES: int = 6
const LINE_COLOR := UiTheme.BUTTON_HOVER
const LINE_WIDTH: float = 2.0
const DOT_SIZE: int = 10

# Botón «?» de ayuda.
var _help_button: Button
var _open_button: Button
var _close_button: Button
var _panel: PanelContainer
var _tab_buttons: Array[Button] = []
var _current_tab: int = TAB_EMPLOYEES
var _views: Array[Control] = []
var _status_label: Label
var _payroll_label: Label
var _free_label: Label
var _mood_label: Label
var _body: VBoxContainer
var _body_top: float = -1.0

# Empleados.
var _employees_list: VBoxContainer
var _employees_header: Label
var _alerts_box: VBoxContainer
var _area_buttons: Dictionary[String, Button] = {}
var _area: String = AREA_ALL
var _search: LineEdit
var _sort_option: OptionButton
var _groups_box: VBoxContainer
var _groups_scroll: ScrollContainer
var _card_grids: Array[GridContainer] = []
var _ficha_column: PanelContainer
var _ficha_hint: Label
## Empleado cuya ficha está abierta (su tarjeta se marca).
var _selected_id: int = 0
var _card_buttons: Dictionary[int, Button] = {}

# Vacantes.
var _hire_form: VBoxContainer
var _role_option: OptionButton
var _level_option: OptionButton
var _role_buttons: Array[Button] = []
var _level_buttons: Array[Button] = []
var _salary_label: Label
var _table_label: Label
var _salary_down: Button
var _salary_up: Button
var _publicity_check: CheckBox
var _outlook_label: Label
var _publish_button: Button
var _vacancy_list: VBoxContainer
var _vacancy_scroll: ScrollContainer
var _candidate_grids: Array[GridContainer] = []
var _salary: int = 0
var _vacancy_close_buttons: Dictionary[int, Button] = {}
var _discard_buttons: Dictionary[int, Button] = {}
var _interview_buttons: Dictionary[int, Button] = {}
var _delegate_buttons: Dictionary[int, Button] = {}
var _offer_buttons: Dictionary[int, Button] = {}
var _offer_step_buttons: Dictionary[int, Array] = {}
var _counter_buttons: Dictionary[int, Button] = {}
## Sueldo que se le va a ofrecer a cada candidato (por id).
var _offers: Dictionary[int, int] = {}

# Organigrama.
var _org_list: VBoxContainer
var _org_tree: VBoxContainer
## Líneas del árbol: [jefe, subordinado] (se dibujan detrás de las tarjetas).
var _org_links: Array[Array] = []
## Lista del departamento que dirige cada ejecutivo en el organigrama (por id).
var _department_choices: Dictionary[int, OptionButton] = {}
## Lista "A cargo de" de cada líder en el organigrama (por id del líder).
var _boss_choices: Dictionary[int, OptionButton] = {}

static var _dots: Dictionary[Color, Texture2D] = {}


# Rehace todo el panel (la capa de arriba la llena; las listas del organigrama la llaman al cambiar algo).
func _refresh() -> void:
	pass


func _section(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionLabel"
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	parent.add_child(label)
	return label


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CaptionLabel"
	return label


func _strong(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"StrongLabel"
	return label


func _button(text: String, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	if not variation.is_empty():
		button.theme_type_variation = variation
	return button


# Botón − o + de un sueldo.
func _step_button(text: String, tooltip: String) -> Button:
	var button: Button = _button(text)
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(44, 0)
	return button


func _card_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	return panel


func _photo(person: Dictionary, side: float) -> EmployeePortrait:
	var photo := EmployeePortrait.new()
	photo.custom_minimum_size = Vector2(side, side)
	photo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	photo.set_employee(person)
	return photo


func _ceo_photo(side: float) -> EmployeePortrait:
	var photo := EmployeePortrait.new()
	photo.custom_minimum_size = Vector2(side, side)
	photo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	photo.set_look("executive", _role_color("executive"))
	return photo


# Foto de un candidato: el mismo aspecto con que viene a la entrevista (Visitor).
func _candidate_photo(candidate: Dictionary, side: float) -> EmployeePortrait:
	var photo := EmployeePortrait.new()
	photo.custom_minimum_size = Vector2(side, side)
	photo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	photo.set_look(Employee.make_look(String(candidate.get("sex", "")) == "female", "office", int(candidate["id"])),
		_role_color(String(candidate["role"])))
	return photo


# Punto de color de un cargo o área (textura cuadrada, se guarda por color).
static func _dot(color: Color) -> Texture2D:
	if not _dots.has(color):
		var image := Image.create_empty(DOT_SIZE, DOT_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(color)
		_dots[color] = ImageTexture.create_from_image(image)
	return _dots[color]


static func _role_color(role: String) -> Color:
	return EmployeePortrait.ROLE_COLORS.get(role, EmployeePortrait.DEFAULT_COLOR)


static func _area_of(role: String) -> String:
	for area: String in AREAS:
		if (AREAS[area][1] as Array).has(role):
			return area
	return "services"


# Columnas que caben en un ancho con tarjetas de min_width.
static func _columns_for(width: float, min_width: float, gap: float) -> int:
	return maxi(1, floori((width + gap) / (min_width + gap)))


# Aviso bajo la cabecera (resultado de la última acción); vacío no ocupa lugar.
func _set_status(text: String) -> void:
	_status_label.text = text
	_status_label.visible = not text.is_empty()


## Barra fina de 0 a 100; con low >= 0 pinta un rango (habilidad sin entrevistar).
class Bar:
	extends Control

	var value: float = 0.0
	var low: float = -1.0
	var color: Color = UiTheme.ACCENT

	func _init(bar_value: float, bar_color: Color, height: float, range_low: float = -1.0) -> void:
		value = bar_value
		color = bar_color
		low = range_low
		custom_minimum_size = Vector2(24, height)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.OUTLINE)
		var from: float = clampf(low, 0.0, 100.0) / 100.0 if low >= 0.0 else 0.0
		var to: float = clampf(value, 0.0, 100.0) / 100.0
		if to > from:
			var fill: Color = color.darkened(0.35) if low >= 0.0 else color
			draw_rect(Rect2(Vector2(size.x * from, 0), Vector2(size.x * (to - from), size.y)), fill)
