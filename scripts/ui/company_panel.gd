# Menú Empresa (diseño, 9.1 y 12.3; hito 27): la etapa actual y lo que desbloqueó, el
# progreso hacia la siguiente (cada requisito con lo que hay y lo que pide), la
# reputación, el valor de la empresa, los ingresos y gastos del mes y, desde el hito 33,
# los departamentos con quién los dirige y cuánto rinden. Desde el hito 48, la meta
# final: salir a bolsa (Corporación y valor), con su botón y una confirmación.
#
# No pausa el tiempo. Ocupa el lado izquierdo, como Personal, Proyectos, Equipos y
# Banco (abrir uno cierra los otros; lo hace la escena de juego). Se construye en
# código; su botón va en la barra de menús.
class_name CompanyPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal company_mode_changed(active: bool)

const PANEL_WIDTH: float = 520.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 100.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const STAGE_FONT_SIZE: int = 22
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const MET_COLOR := Color(0.55, 0.85, 0.5)
const AMOUNT_WIDTH: float = 140.0

var _open_button: Button
var _panel: PanelContainer
var _content: VBoxContainer
var _ipo_button: Button
var _confirm_ipo_button: Button
# Se pulsó «Salir a bolsa» y se espera la confirmación.
var _confirming_ipo: bool = false


func _ready() -> void:
	_open_button = Button.new()
	_open_button.text = "Empresa"
	_open_button.custom_minimum_size = Hud.MENU_BUTTON_SIZE
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
	title.text = "Empresa"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	_panel.visible = false

	EventBus.stage_changed.connect(func(_stage: int) -> void: _refresh())
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: _refresh())
	EventBus.staff_changed.connect(_refresh)
	EventBus.projects_changed.connect(_refresh)
	EventBus.company_value_changed.connect(func(_value: int) -> void: _refresh())
	EventBus.office_changed.connect(_refresh)


func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	_refresh()
	company_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


func get_open_button() -> Button:
	return _open_button


## Contenido del panel como texto, una línea por renglón (para las pruebas).
func get_text() -> String:
	var lines: Array[String] = []
	for child: Node in _content.get_children():
		if child is Label:
			lines.append((child as Label).text)
		elif child is HBoxContainer:
			var parts: Array[String] = []
			for label: Node in child.get_children():
				parts.append(String(label.get("text")).strip_edges())
			lines.append(" | ".join(parts))
	return "\n".join(lines)


func _refresh() -> void:
	if _content == null or not is_open():
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var count: int = Company.get_stage_count()
	_label("Etapa %d de %d: %s" % [Company.stage + 1, count, Company.get_stage_name()], STAGE_FONT_SIZE)
	var unlocked: Array[String] = []
	for index: int in range(Company.stage + 1):
		for item: Variant in Company.get_stage_info(index).get("unlocks", []):
			unlocked.append(String(item))
	unlocked.append(Company.describe_loan_cap(Company.get_max_loan()))
	_label("Tienes: %s." % ", ".join(PackedStringArray(unlocked)), 0, MUTED_COLOR)

	if Company.stage + 1 < count:
		var next: int = Company.stage + 1
		_label("Siguiente etapa: %s" % Company.get_stage_name(next), SECTION_FONT_SIZE)
		for requirement: Dictionary in Company.get_requirements(next):
			var met: bool = requirement["met"]
			_row("  %s %s" % ["✓" if met else "·", requirement["label"]],
				"%d / %d" % [requirement["current"], requirement["needed"]], MET_COLOR if met else Color.WHITE)
		var unlocks: Array[String] = Company.get_new_unlocks(next)
		_label("Desbloquea: %s." % ", ".join(PackedStringArray(unlocks)), 0, MUTED_COLOR)
		_label("Las etapas se revisan cada día y nunca bajan.", 0, MUTED_COLOR)
	else:
		_label("La empresa llegó a la última etapa.", SECTION_FONT_SIZE)

	var departments: Array[String] = Staff.get_departments()
	if not departments.is_empty():
		_label("Departamentos", SECTION_FONT_SIZE)
		for department: String in departments:
			var executive: Dictionary = Staff.get_executive_of(department)
			_row("  %s (%s)" % [StaffCatalog.get_department_name(department), "el CEO" if executive.is_empty() else executive["name"]],
				"%d %%" % roundi(Staff.get_department_factor(department) * 100.0), Color.WHITE)

	var racks: int = OfficeState.get_server_capacity()
	var server_cost: int = Economy.get_monthly_server_cost()
	var has_server_room: bool = OfficeState.rooms.any(func(room: Dictionary) -> bool: return room["type"] == OfficeState.SERVER_ROOM)
	if has_server_room or server_cost > 0:
		_label("Servidores", SECTION_FONT_SIZE)
		_row("  Capacidad", "%d %s" % [racks, "rack" if racks == 1 else "racks"], Color.WHITE)
		_row("  Mantenimiento al mes", MoneyFormat.format(server_cost), Color.WHITE)
		if racks == 0:
			_label("La Sala de servidores no funciona: le falta un rack o el aire acondicionado.", 0, MUTED_COLOR)

	_add_ipo_section()

	_label("Reputación", SECTION_FONT_SIZE)
	_row("  Actual", ProjectsPanel.describe_reputation(Projects.reputation), Hud.REPUTATION_COLOR)
	_row("  Mejor", "%.1f" % Projects.best_reputation, Color.WHITE)
	_row("  Contratos entregados", str(Projects.delivered_count), Color.WHITE)

	_label("Valor de la empresa", SECTION_FONT_SIZE)
	var value: int = Company.get_value()
	_row("  Valor", MoneyFormat.format(value), Hud.NEGATIVE_COLOR if value < 0 else Color.WHITE)

	var month: int = Economy.get_current_month()
	_label("Este mes (mes %d)" % month, SECTION_FONT_SIZE)
	var income: int = 0
	var expenses: int = 0
	var borrowed: int = 0
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	for concept: String in totals:
		# Un préstamo entra a la caja pero no es un ingreso: va aparte.
		if concept == Bank.CONCEPT_LOAN or concept == Bank.CONCEPT_EMERGENCY:
			borrowed += totals[concept]
		elif totals[concept] >= 0:
			income += totals[concept]
		else:
			expenses -= totals[concept]
	_row("  Ingresos", "+" + MoneyFormat.format(income), BankPanel.INCOME_COLOR)
	_row("  Gastos", MoneyFormat.format(-expenses), Hud.NEGATIVE_COLOR if expenses > 0 else Color.WHITE)
	var result: int = income - expenses
	_row("  Resultado", ("+" if result >= 0 else "") + MoneyFormat.format(result), Hud.NEGATIVE_COLOR if result < 0 else Color.WHITE)
	if borrowed > 0:
		_row("  Préstamos recibidos", "+" + MoneyFormat.format(borrowed), MUTED_COLOR)
	_label("El detalle por concepto está en el Banco.", 0, MUTED_COLOR)


## Botón «Salir a bolsa» (null si el panel está cerrado o la empresa ya cotiza).
func get_ipo_button() -> Button:
	return _ipo_button


## Botón «Confirmar» de la salida a bolsa (null si no se está confirmando).
func get_confirm_ipo_button() -> Button:
	return _confirm_ipo_button


# Meta final (hito 48): lo que pide salir a bolsa, el botón y su confirmación.
func _add_ipo_section() -> void:
	_ipo_button = null
	_confirm_ipo_button = null
	_label("Salir a bolsa", SECTION_FONT_SIZE)
	if Company.is_public():
		_label("Cotiza en bolsa desde el día %d. La partida sigue en modo libre." % (Company.public_day + 1), 0, MET_COLOR)
		return
	var stage_met: bool = Company.stage >= Company.get_ipo_stage()
	_row("  %s Ser %s" % ["✓" if stage_met else "·", Company.get_stage_name(Company.get_ipo_stage())],
		"%d / %d" % [Company.stage + 1, Company.get_ipo_stage() + 1], MET_COLOR if stage_met else Color.WHITE)
	var value: int = Company.get_value()
	var value_met: bool = value > Company.get_ipo_value()
	_row("  %s Valor de más de %s" % ["✓" if value_met else "·", MoneyFormat.format(Company.get_ipo_value())],
		MoneyFormat.format(value), MET_COLOR if value_met else Color.WHITE)
	var problem: String = Company.ipo_problem()
	var buttons := HBoxContainer.new()
	_content.add_child(buttons)
	if _confirming_ipo and problem.is_empty():
		_label("¿Salir a bolsa? Es la meta final y no se deshace: verás el cierre y la partida seguirá en modo libre.", 0, MUTED_COLOR)
		_confirm_ipo_button = Button.new()
		_confirm_ipo_button.text = "Confirmar"
		_confirm_ipo_button.pressed.connect(func() -> void:
			_confirming_ipo = false
			Company.go_public()
			_refresh())
		buttons.add_child(_confirm_ipo_button)
		var cancel := Button.new()
		cancel.text = "Cancelar"
		cancel.pressed.connect(func() -> void:
			_confirming_ipo = false
			_refresh())
		buttons.add_child(cancel)
		return
	_confirming_ipo = false
	_ipo_button = Button.new()
	_ipo_button.text = "Salir a bolsa"
	_ipo_button.disabled = not problem.is_empty()
	_ipo_button.tooltip_text = problem
	_ipo_button.pressed.connect(func() -> void:
		_confirming_ipo = true
		_refresh())
	buttons.add_child(_ipo_button)


func _label(text: String, font_size: int = 0, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	if color != Color.WHITE:
		label.add_theme_color_override("font_color", color)
	_content.add_child(label)


func _row(concept: String, amount: String, color: Color) -> void:
	var row := HBoxContainer.new()
	var concept_label := Label.new()
	concept_label.text = concept
	concept_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Un requisito largo se parte en líneas en vez de ensanchar el panel.
	concept_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	concept_label.custom_minimum_size.x = 1.0
	row.add_child(concept_label)
	var amount_label := Label.new()
	amount_label.text = amount
	amount_label.custom_minimum_size = Vector2(AMOUNT_WIDTH, 0)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.add_theme_color_override("font_color", color)
	row.add_child(amount_label)
	_content.add_child(row)
