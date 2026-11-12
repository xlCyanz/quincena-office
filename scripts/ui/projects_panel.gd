# Menú Proyectos (diseño, 12.3): la reputación, los contratos en curso con su plazo, quién
# los lleva y sus tres barras de avance (diseño, programación y pruebas), y la bandeja de
# ofertas con cliente, tipo, tamaño, trabajo, plazo, pago, anticipo y penalidad, para
# aceptarlas o rechazarlas.
#
# No pausa el tiempo. Ocupa el lado izquierdo, como Personal (abrir uno cierra el otro;
# lo hace la escena de juego). Se construye en código; su botón va en la barra de menús
# y muestra cuántas ofertas hay.
class_name ProjectsPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal projects_mode_changed(active: bool)

const PANEL_WIDTH: float = 560.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 76.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const STARS: int = 5
const PHASE_LABEL_WIDTH: float = 120.0
const PHASE_VALUE_WIDTH: float = 150.0
const BAR_HEIGHT: float = 14.0

var _open_button: Button
var _panel: PanelContainer
var _reputation_label: Label
var _status_label: Label
var _list: VBoxContainer
var _accept_buttons: Dictionary[int, Button] = {}
var _reject_buttons: Dictionary[int, Button] = {}
var _bars: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	_open_button = Button.new()
	_open_button.custom_minimum_size = Vector2(160, 44)
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.pressed.connect(func() -> void: set_open(not is_open()))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
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
	title.text = "Proyectos"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	header.add_child(title)
	_reputation_label = Label.new()
	_reputation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reputation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_reputation_label)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(close_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_panel.visible = false
	EventBus.projects_changed.connect(_refresh)
	EventBus.staff_changed.connect(_refresh)
	EventBus.office_changed.connect(_refresh)
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: _refresh())
	_refresh()


## Pone el botón "Proyectos" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_status_label.text = ""
		_refresh()
	projects_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


func get_open_button() -> Button:
	return _open_button


func get_status_text() -> String:
	return _status_label.text


## Botón "Aceptar" de una oferta, o null.
func get_accept_button(offer_id: int) -> Button:
	return _accept_buttons.get(offer_id)


## Botón "Rechazar" de una oferta, o null.
func get_reject_button(offer_id: int) -> Button:
	return _reject_buttons.get(offer_id)


## Barra de avance de una fase de un contrato en curso, o null.
func get_phase_bar(contract_id: int, phase: String) -> ProgressBar:
	return _bars.get(contract_id, {}).get(phase)


## Todo el texto del panel (para las pruebas).
func get_list_text() -> String:
	var texts: Array[String] = [_reputation_label.text]
	for label: Node in _list.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return "\n".join(texts)


## "★☆☆☆☆" para una reputación de 1 a 5.
static func stars(value: float) -> String:
	var full: int = clampi(roundi(value), 0, STARS)
	return "★".repeat(full) + "☆".repeat(STARS - full)


func _refresh() -> void:
	var count: int = Projects.offers.size()
	_open_button.text = "Proyectos (%d)" % count if count > 0 else "Proyectos"
	if _list == null or not is_open():
		return
	_reputation_label.text = "Reputación %s" % stars(Projects.reputation)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_accept_buttons.clear()
	_reject_buttons.clear()
	_bars.clear()

	_add_section("En curso (%d de %d)" % [Projects.contracts.size(), Projects.get_contract_limit()])
	if Projects.contracts.is_empty():
		_list.add_child(_muted_label("Ningún contrato en curso. Acepta una oferta de la bandeja."))
	for contract: Dictionary in Projects.contracts:
		_add_contract(contract)
	_list.add_child(HSeparator.new())
	_add_section("Ofertas (%d)" % Projects.offers.size())
	if Projects.offers.is_empty():
		_list.add_child(_muted_label("No hay ofertas. Llegan a las %02d:00; más con vendedores y con más reputación." % int(
			ContractCatalog.get_offers("arrival_hour"))))
	for offer: Dictionary in Projects.offers:
		_add_offer(offer)


func _add_contract(contract: Dictionary) -> void:
	var days_left: int = Projects.contract_days_left(contract)
	var deadline: String
	if days_left > 1:
		deadline = "quedan %d días" % days_left
	elif days_left == 1:
		deadline = "queda 1 día"
	elif days_left == 0:
		deadline = "vence hoy"
	else:
		deadline = "atrasado %d %s" % [-days_left, "día" if days_left == -1 else "días"]
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var owner_text: String = Projects.describe_owner(contract)
	info.text = "%s · %s\n%s · Pago %s · %s" % [Projects.describe_title(contract), deadline,
		owner_text.left(1).to_upper() + owner_text.substr(1), MoneyFormat.format(contract["pay"]),
		"anticipo cobrado %s" % MoneyFormat.format(contract["advance"]) if int(contract["advance"]) > 0 else "sin anticipo"]
	_list.add_child(info)
	var contract_id: int = contract["id"]
	var bars: Dictionary[String, ProgressBar] = {}
	_bars[contract_id] = bars
	for phase: String in ContractCatalog.PHASES:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var name_label := Label.new()
		name_label.text = ContractCatalog.PHASE_NAMES[phase].capitalize()
		name_label.custom_minimum_size = Vector2(PHASE_LABEL_WIDTH, 0)
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
		bar.show_percentage = false
		bar.max_value = maxf(1.0, float(contract["points"][phase]))
		bar.value = float(contract["progress"][phase])
		row.add_child(bar)
		bars[phase] = bar
		var value := Label.new()
		var closed: bool = not Production.is_open(contract, phase)
		value.text = "%d / %d%s" % [floori(float(contract["progress"][phase]) + Production.EPSILON), contract["points"][phase],
			" (espera)" if closed else ""]
		value.custom_minimum_size = Vector2(PHASE_VALUE_WIDTH, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
	_list.add_child(_muted_label(Projects.describe_bugs(contract) + "."))
	var state: String
	var pending: int = int(contract["bugs_found"])
	if Production.is_finished(contract) and pending > 0:
		state = "Terminado, con %d %s por corregir: los programadores siguen." % [pending, "error" if pending == 1 else "errores"]
	elif Production.is_finished(contract):
		state = "Terminado: listo para entregar. Si el equipo tiene QA, sigue buscando errores."
	elif int(contract["team_id"]) == Projects.NO_TEAM:
		state = "Nadie lo lleva: dáselo a un equipo en el menú Equipos."
	else:
		var rate: float = Projects.get_hourly_rate(contract)
		state = "Ahora rinde %s puntos por hora." % String.num(rate, 1).trim_suffix(".0") if rate > 0.0 \
			else "Ahora nadie está trabajando en él."
	_list.add_child(_muted_label(state))


func _add_offer(offer: Dictionary) -> void:
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var days_left: int = Projects.offer_days_left(offer)
	var expires: String = "caduca hoy" if days_left == 0 else ("caduca mañana" if days_left == 1 else "caduca en %d días" % days_left)
	info.text = "%s · %s\n%s\n%s" % [Projects.describe_title(offer), expires, Projects.describe_points(offer),
		Projects.describe_terms(offer)]
	_list.add_child(info)
	var actions := HBoxContainer.new()
	_list.add_child(actions)
	var offer_id: int = offer["id"]
	var accept := Button.new()
	accept.text = "Aceptar"
	var problem: String = Projects.accept_problem(offer_id)
	accept.disabled = not problem.is_empty()
	accept.tooltip_text = problem
	accept.pressed.connect(func() -> void: _status_label.text = Projects.accept(offer_id)["message"])
	actions.add_child(accept)
	_accept_buttons[offer_id] = accept
	var reject := Button.new()
	reject.text = "Rechazar"
	reject.pressed.connect(func() -> void: Projects.reject(offer_id))
	actions.add_child(reject)
	_reject_buttons[offer_id] = reject
	if not problem.is_empty():
		var why := _muted_label(problem)
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(why)
	_list.add_child(HSeparator.new())


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_list.add_child(label)


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label
