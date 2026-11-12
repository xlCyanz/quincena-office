# Menú Banco (diseño, 8.1, 8.3 y 12.3): el saldo de la cuenta empresarial, la
# calificación de crédito con lo que suma cada factor, el interés y el límite (hito 21),
# los ingresos y gastos por concepto del mes actual o del anterior (con «<» y «>») y el
# historial de movimientos, los más nuevos arriba.
#
# Préstamos (hito 22): cada préstamo activo con su cuota, lo que falta y los botones
# Saldar (con confirmación) y Refinanciar (eligiendo cuántos meses alargar), y la
# solicitud con monto y plazo de a pasos y la vista previa de tasa, cuota y total.
# Con cuotas atrasadas (hito 23) avisa cuántos meses van y qué haría hoy un embargo.
#
# No pausa el tiempo. Ocupa el lado izquierdo, como Personal, Proyectos y Equipos (abrir
# uno cierra los otros; lo hace la escena de juego). Se construye en código; su botón va
# en la barra de menús.
class_name BankPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal bank_mode_changed(active: bool)

const PANEL_WIDTH: float = 520.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 100.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const BALANCE_FONT_SIZE: int = 22
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const INCOME_COLOR := Color(0.55, 0.85, 0.5)
const DATE_WIDTH: float = 120.0
const AMOUNT_WIDTH: float = 110.0

var _open_button: Button
var _panel: PanelContainer
var _balance_label: Label
var _month_label: Label
var _previous_button: Button
var _next_button: Button
var _month_rows: VBoxContainer
var _movement_rows: VBoxContainer
var _empty_label: Label
var _credit_label: Label
var _credit_rows: VBoxContainer
var _company_label: Label
var _company_rows: VBoxContainer
var _loan_rows: VBoxContainer
var _overdue_label: Label
var _amount_label: Label
var _months_label: Label
var _amount_minus: Button
var _amount_plus: Button
var _months_minus: Button
var _months_plus: Button
var _quote_label: Label
var _request_button: Button
var _loan_status: Label
var _prepay_buttons: Dictionary[int, Button] = {}
var _refinance_buttons: Dictionary[int, Button] = {}
var _confirm_button: Button
var _extra_minus: Button
var _extra_plus: Button
# Solicitud en curso.
var _amount: int = 0
var _months: int = 12
# Préstamo con una acción esperando confirmación (0 = ninguno) y cuál: "prepay" o "refinance".
var _pending_loan: int = 0
var _pending_action: String = ""
var _refinance_extra: int = 0
# Mes que se muestra en el resumen (el actual o el anterior).
var _shown_month: int = 1
# Mes actual en el último refresco: si se miraba ese mes y empieza otro, se sigue al nuevo.
var _last_current: int = 1


func _ready() -> void:
	_open_button = Button.new()
	_open_button.text = "Banco"
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
	title.text = "Banco"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(close_button)
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", BALANCE_FONT_SIZE)
	rows.add_child(_balance_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	# Valor de la empresa (hito 26).
	_company_label = Label.new()
	_company_label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	content.add_child(_company_label)
	_company_rows = VBoxContainer.new()
	content.add_child(_company_rows)

	# Calificación de crédito.
	_credit_label = Label.new()
	_credit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credit_label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	content.add_child(_credit_label)
	_credit_rows = VBoxContainer.new()
	content.add_child(_credit_rows)
	var credit_hint := Label.new()
	credit_hint.text = "Se recalcula el día 1 de cada mes. Sube con ingresos, bienes, antigüedad y pagos a tiempo (nómina, mantenimiento y cuotas); cada atraso resta en el momento."
	credit_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit_hint.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(credit_hint)

	# Préstamos.
	var loans_title := Label.new()
	loans_title.text = "Préstamos"
	loans_title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	content.add_child(loans_title)
	_overdue_label = Label.new()
	_overdue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overdue_label.add_theme_color_override("font_color", Hud.NEGATIVE_COLOR)
	content.add_child(_overdue_label)
	_loan_rows = VBoxContainer.new()
	content.add_child(_loan_rows)
	var amount_row := HBoxContainer.new()
	content.add_child(amount_row)
	_amount_minus = _step_button(amount_row, "−", func() -> void: _change_amount(-1))
	_amount_label = _value_label(amount_row)
	_amount_plus = _step_button(amount_row, "+", func() -> void: _change_amount(1))
	_months_minus = _step_button(amount_row, "−", func() -> void: _change_months(-1))
	_months_label = _value_label(amount_row)
	_months_plus = _step_button(amount_row, "+", func() -> void: _change_months(1))
	_quote_label = Label.new()
	_quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_quote_label)
	_request_button = Button.new()
	_request_button.text = "Pedir préstamo"
	_request_button.pressed.connect(func() -> void: _show_result(Bank.request_loan(_amount, _months)))
	content.add_child(_request_button)
	_loan_status = Label.new()
	_loan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loan_status.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(_loan_status)

	# Resumen del mes con selector.
	var month_header := HBoxContainer.new()
	content.add_child(month_header)
	_previous_button = Button.new()
	_previous_button.text = "<"
	_previous_button.pressed.connect(func() -> void: _show_month(_shown_month - 1))
	month_header.add_child(_previous_button)
	_month_label = Label.new()
	_month_label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_month_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_month_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	month_header.add_child(_month_label)
	_next_button = Button.new()
	_next_button.text = ">"
	_next_button.pressed.connect(func() -> void: _show_month(_shown_month + 1))
	month_header.add_child(_next_button)
	_month_rows = VBoxContainer.new()
	content.add_child(_month_rows)

	var movements_title := Label.new()
	movements_title.text = "Movimientos"
	movements_title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	content.add_child(movements_title)
	_empty_label = Label.new()
	_empty_label.text = "Todavía no hay movimientos."
	_empty_label.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(_empty_label)
	_movement_rows = VBoxContainer.new()
	content.add_child(_movement_rows)

	_panel.visible = false
	EventBus.balance_changed.connect(func(_balance: int) -> void: _refresh())
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: _refresh())
	EventBus.bank_changed.connect(_refresh)
	EventBus.company_value_changed.connect(func(_value: int) -> void: _refresh())


## Pone el botón "Banco" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_shown_month = Economy.get_current_month()
		_last_current = _shown_month
		_amount = 0
		_pending_loan = 0
		_loan_status.text = ""
		_refresh()
	bank_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


func get_open_button() -> Button:
	return _open_button


## Botones «<» (mes anterior) y «>» (mes siguiente) del resumen.
func get_previous_button() -> Button:
	return _previous_button


func get_next_button() -> Button:
	return _next_button


## Mes que muestra el resumen.
func get_shown_month() -> int:
	return _shown_month


func get_balance_text() -> String:
	return _balance_label.text


## Controles de la solicitud de préstamo.
func get_amount_buttons() -> Array[Button]:
	return [_amount_minus, _amount_plus]


func get_months_buttons() -> Array[Button]:
	return [_months_minus, _months_plus]


func get_request_button() -> Button:
	return _request_button


func get_request() -> Vector2i:
	return Vector2i(_amount, _months)


## Vista previa de la solicitud y mensaje del último intento.
func get_quote_text() -> String:
	return _quote_label.text


func get_loan_status() -> String:
	return _loan_status.text


## Aviso de cuotas atrasadas ("" si está al día).
func get_overdue_text() -> String:
	return _overdue_label.text if _overdue_label.visible else ""


## Texto de los préstamos activos (una entrada por renglón).
func get_loans_text() -> String:
	var lines: Array[String] = []
	_collect_labels(_loan_rows, lines)
	return "\n".join(lines)


static func _collect_labels(node: Node, lines: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is Label:
			lines.append((child as Label).text)
		_collect_labels(child, lines)


func get_prepay_button(loan_id: int) -> Button:
	return _prepay_buttons.get(loan_id)


func get_refinance_button(loan_id: int) -> Button:
	return _refinance_buttons.get(loan_id)


## Botón que confirma saldar o refinanciar (visible después de pulsar uno de ellos).
func get_confirm_button() -> Button:
	return _confirm_button


## Botones −/+ de los meses que se alarga al refinanciar.
func get_extra_buttons() -> Array[Button]:
	return [_extra_minus, _extra_plus]


## Texto de la calificación: título y una línea por factor.
## Valor de la empresa y sus partes, una por renglón ("concepto | monto").
func get_value_text() -> String:
	var lines: Array[String] = [_company_label.text]
	for row: Node in _company_rows.get_children():
		lines.append(_row_text(row))
	return "\n".join(lines)


func get_credit_text() -> String:
	var lines: Array[String] = [_credit_label.text]
	for row: Node in _credit_rows.get_children():
		lines.append(_row_text(row))
	return "\n".join(lines)


## Texto del resumen del mes: título y una línea por concepto y por total.
func get_month_text() -> String:
	var lines: Array[String] = [_month_label.text]
	for row: Node in _month_rows.get_children():
		lines.append(_row_text(row))
	return "\n".join(lines)


## Texto de cada movimiento, en el orden en que se ven (los más nuevos primero).
func get_movement_texts() -> Array[String]:
	var texts: Array[String] = []
	for row: Node in _movement_rows.get_children():
		texts.append(_row_text(row))
	return texts


func _show_month(month: int) -> void:
	var current: int = Economy.get_current_month()
	_shown_month = clampi(month, maxi(1, current - 1), current)
	_refresh()


func _refresh() -> void:
	if _panel == null or not is_open():
		return
	_balance_label.text = "Saldo: %s" % MoneyFormat.format(Economy.balance)
	if Economy.balance < 0:
		_balance_label.add_theme_color_override("font_color", Hud.NEGATIVE_COLOR)
	else:
		_balance_label.remove_theme_color_override("font_color")
	_company_label.text = "Valor de la empresa: %s" % MoneyFormat.format(Company.get_value())
	_clear(_company_rows)
	for part: Dictionary in Company.get_value_parts():
		var amount: int = part["amount"]
		_company_rows.add_child(_row("", "  " + String(part["label"]), amount, Hud.NEGATIVE_COLOR if amount < 0 else Color.WHITE))
	var current: int = Economy.get_current_month()
	if _shown_month == _last_current:
		_shown_month = current
	_last_current = current
	_shown_month = clampi(_shown_month, maxi(1, current - 1), current)
	_month_label.text = "Mes %d (%s)" % [_shown_month, "este mes" if _shown_month == current else "mes anterior"]
	_previous_button.disabled = _shown_month <= maxi(1, current - 1)
	_next_button.disabled = _shown_month >= current
	_refresh_credit()
	_refresh_loans()
	_refresh_month()
	_refresh_movements()


func _refresh_credit() -> void:
	_credit_label.text = "Crédito: %s (%d puntos) · interés %s al mes · presta hasta %s" % [
		Bank.rating, Bank.score, _percent(Bank.get_monthly_rate()), MoneyFormat.format(Bank.get_limit())]
	_clear(_credit_rows)
	for part: Dictionary in Bank.get_score_parts():
		var label: String = part["label"] if String(part["detail"]).is_empty() else "%s (%s)" % [part["label"], part["detail"]]
		var points: int = part["points"]
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "   " + label
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var points_label := Label.new()
		points_label.text = ("+%d" % points) if points >= 0 else ("−%d" % -points)
		points_label.custom_minimum_size = Vector2(AMOUNT_WIDTH, 0)
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if points < 0:
			points_label.add_theme_color_override("font_color", Hud.NEGATIVE_COLOR)
		elif points == 0:
			points_label.add_theme_color_override("font_color", MUTED_COLOR)
		row.add_child(points_label)
		_credit_rows.add_child(row)


func _refresh_loans() -> void:
	_clear(_loan_rows)
	_prepay_buttons.clear()
	_refinance_buttons.clear()
	_confirm_button = null
	_extra_minus = null
	_extra_plus = null
	if Bank.loans.is_empty():
		var none := Label.new()
		none.text = "No tienes préstamos."
		none.add_theme_color_override("font_color", MUTED_COLOR)
		_loan_rows.add_child(none)
	if Bank.get_loan(_pending_loan).is_empty():
		_pending_loan = 0
	_overdue_label.visible = Bank.get_overdue() > 0
	if _overdue_label.visible:
		var seizure: int = int(Bank.get_config("seizure_months"))
		var plan: Dictionary = Bank.preview_seizure()
		var outcome: String
		if bool(plan["covers"]):
			var taken: int = (plan["take"] as Array).size()
			outcome = "se llevaría %d %s y saldaría la deuda" % [taken, "mueble" if taken == 1 else "muebles"]
		else:
			outcome = "tus muebles (%s) no alcanzan: perderías la empresa" % MoneyFormat.format(int(plan["value"]))
		_overdue_label.text = "Cuotas atrasadas: %s, %d %s seguido%s debiendo. Se pagan solas cuando alcance el saldo. A los %d meses el banco no presta; a los %d embarga: hoy %s." % [
			MoneyFormat.format(Bank.get_overdue()), Bank.overdue_months, "mes" if Bank.overdue_months == 1 else "meses",
			"" if Bank.overdue_months == 1 else "s", int(Bank.get_config("warning_months")), seizure, outcome]
	for loan: Dictionary in Bank.loans:
		var box := VBoxContainer.new()
		_loan_rows.add_child(box)
		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var left: int = Bank.get_remaining_months(loan)
		info.text = "%s al %s mensual%s · cuota %s · %d %s · capital pendiente %s" % [
			MoneyFormat.format(int(loan["amount"])), _percent(float(loan["rate"])), " (refinanciado)" if bool(loan["refinanced"]) else "",
			MoneyFormat.format(Bank.get_installment(loan)) if left > 0 else "—", left, "cuota" if left == 1 else "cuotas",
			MoneyFormat.format(Bank.get_remaining_principal(loan))]
		if bool(loan.get("emergency", false)):
			info.text = "De emergencia: " + info.text
			if GameClock.get_day_count() < int(loan.get("first_due_day", 0)):
				info.text += " · primera cuota el %s" % Bank.describe_day(int(loan["first_due_day"]))
		if int(loan.get("overdue", 0)) > 0:
			info.text += " · atrasado %s" % MoneyFormat.format(int(loan["overdue"]))
			info.add_theme_color_override("font_color", Hud.NEGATIVE_COLOR)
		box.add_child(info)
		var buttons := HBoxContainer.new()
		box.add_child(buttons)
		var loan_id: int = loan["id"]
		var prepay := Button.new()
		prepay.text = "Saldar (%s)" % MoneyFormat.format(Bank.get_prepay_cost(loan))
		prepay.pressed.connect(func() -> void: _ask(loan_id, "prepay"))
		buttons.add_child(prepay)
		_prepay_buttons[loan_id] = prepay
		var refinance := Button.new()
		refinance.text = "Refinanciar"
		refinance.disabled = Bank.get_max_refinance_extra(loan) == 0
		refinance.tooltip_text = Bank.refinance_problem(loan, int(Bank.get_config("refinance_min_extra")))
		refinance.pressed.connect(func() -> void: _ask(loan_id, "refinance"))
		buttons.add_child(refinance)
		_refinance_buttons[loan_id] = refinance
		if _pending_loan == loan_id:
			_add_confirm(box, loan)
	# Solicitud.
	var step: int = int(Bank.get_config("loan_amount_step"))
	var min_amount: int = int(Bank.get_config("loan_min_amount"))
	var available: int = floori(float(Bank.get_max_request()) / step) * step
	if _amount <= 0:
		_amount = clampi(available, min_amount, maxi(min_amount, available))
	_amount_label.text = "Monto %s" % MoneyFormat.format(_amount)
	_months_label.text = "Plazo %d meses" % _months
	_amount_minus.disabled = _amount - step < min_amount
	_amount_plus.disabled = _amount + step > available
	_months_minus.disabled = _months <= int(Bank.get_config("loan_min_months"))
	_months_plus.disabled = _months >= int(Bank.get_config("loan_max_months"))
	var problem: String = Bank.loan_problem(_amount, _months)
	var terms: Dictionary = Bank.quote(_amount, _months, Bank.get_monthly_rate())
	_quote_label.text = "Tasa %s mensual · cuota %s · total %s (intereses %s)" % [_percent(Bank.get_monthly_rate()),
		MoneyFormat.format(int(terms["installment"])), MoneyFormat.format(int(terms["total"])), MoneyFormat.format(int(terms["interest"]))]
	if not problem.is_empty():
		_quote_label.text += "\n" + problem
	_request_button.disabled = not problem.is_empty()


# Fila de confirmación debajo de un préstamo: saldar o refinanciar.
func _add_confirm(box: VBoxContainer, loan: Dictionary) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button = Button.new()
	_confirm_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _pending_action == "prepay":
		var cost: int = Bank.get_prepay_cost(loan)
		text.text = "¿Saldar por %s? Ahorras %s de intereses." % [MoneyFormat.format(cost),
			MoneyFormat.format(maxi(0, Bank.get_remaining_total(loan) - cost))]
		_confirm_button.text = "Sí, saldar"
		_confirm_button.disabled = not Economy.can_afford(cost)
		_confirm_button.pressed.connect(func() -> void: _show_result(Bank.prepay(loan["id"])))
	else:
		_extra_minus = _step_button(row, "−", func() -> void: _change_extra(-1))
		var terms: Dictionary = Bank.preview_refinance(loan, _refinance_extra)
		text.text = "+%d meses: %d cuotas de %s al %s" % [_refinance_extra, terms.get("months", 0),
			MoneyFormat.format(int(terms.get("installment", 0))), _percent(float(terms.get("rate", 0.0)))]
		_extra_plus = _step_button(row, "+", func() -> void: _change_extra(1))
		_extra_minus.disabled = _refinance_extra <= int(Bank.get_config("refinance_min_extra"))
		_extra_plus.disabled = _refinance_extra >= Bank.get_max_refinance_extra(loan)
		_confirm_button.text = "Refinanciar"
		_confirm_button.pressed.connect(func() -> void: _show_result(Bank.refinance(loan["id"], _refinance_extra)))
	row.add_child(text)
	row.move_child(text, 0)
	row.add_child(_confirm_button)
	var cancel := Button.new()
	cancel.text = "No"
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void:
		_pending_loan = 0
		_refresh())
	row.add_child(cancel)


func _ask(loan_id: int, action: String) -> void:
	_pending_loan = loan_id
	_pending_action = action
	_refinance_extra = int(Bank.get_config("refinance_min_extra"))
	_refresh()


func _change_extra(direction: int) -> void:
	_refinance_extra = clampi(_refinance_extra + direction, int(Bank.get_config("refinance_min_extra")),
		maxi(int(Bank.get_config("refinance_min_extra")), Bank.get_max_refinance_extra(Bank.get_loan(_pending_loan))))
	_refresh()


func _change_amount(direction: int) -> void:
	var step: int = int(Bank.get_config("loan_amount_step"))
	_amount = maxi(int(Bank.get_config("loan_min_amount")), _amount + direction * step)
	_refresh()


func _change_months(direction: int) -> void:
	_months = clampi(_months + direction, int(Bank.get_config("loan_min_months")), int(Bank.get_config("loan_max_months")))
	_refresh()


func _show_result(result: Dictionary) -> void:
	_loan_status.text = result["message"]
	if result["ok"]:
		_pending_loan = 0
		_amount = 0
	_refresh()


static func _step_button(parent: Container, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(32, 0)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _value_label(parent: Container) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


# 0.045 → "4.5 %"; 0.02 → "2 %".
static func _percent(rate: float) -> String:
	var value: float = snappedf(rate * 100.0, 0.1)
	return ("%d %%" % roundi(value)) if is_equal_approx(value, roundf(value)) else ("%.1f %%" % value)


func _refresh_month() -> void:
	_clear(_month_rows)
	var totals: Dictionary[String, int] = Economy.get_month_totals(_shown_month)
	var incomes: Array[String] = []
	var expenses: Array[String] = []
	var income: int = 0
	var expense: int = 0
	for concept: String in totals:
		if totals[concept] > 0:
			incomes.append(concept)
			income += totals[concept]
		elif totals[concept] < 0:
			expenses.append(concept)
			expense += totals[concept]
	# Los montos más grandes primero.
	incomes.sort_custom(func(a: String, b: String) -> bool: return totals[a] > totals[b])
	expenses.sort_custom(func(a: String, b: String) -> bool: return totals[a] < totals[b])
	if incomes.is_empty() and expenses.is_empty():
		_month_rows.add_child(_row("", "Sin movimientos este mes.", 0, MUTED_COLOR))
		return
	_month_rows.add_child(_row("", "Ingresos", income, INCOME_COLOR, true))
	for concept: String in incomes:
		_month_rows.add_child(_row("", "   " + concept, totals[concept], INCOME_COLOR))
	_month_rows.add_child(_row("", "Gastos", expense, Hud.NEGATIVE_COLOR, true))
	for concept: String in expenses:
		_month_rows.add_child(_row("", "   " + concept, totals[concept], Hud.NEGATIVE_COLOR))
	var result: int = income + expense
	_month_rows.add_child(_row("", "Resultado", result, INCOME_COLOR if result >= 0 else Hud.NEGATIVE_COLOR, true))


func _refresh_movements() -> void:
	_clear(_movement_rows)
	_empty_label.visible = Economy.movements.is_empty()
	for index: int in range(Economy.movements.size() - 1, -1, -1):
		var movement: Dictionary = Economy.movements[index]
		var amount: int = movement["amount"]
		_movement_rows.add_child(_row("Día %d · Mes %d" % [movement["day"], movement["month"]], movement["concept"],
			amount, INCOME_COLOR if amount > 0 else Hud.NEGATIVE_COLOR))


# Una fila: fecha (opcional), concepto y monto con signo. Sin ajuste de línea: dentro de
# un HBox una etiqueta con ajuste se aplasta.
func _row(date: String, concept: String, amount: int, color: Color, bold: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	if not date.is_empty():
		var date_label := Label.new()
		date_label.text = date
		date_label.custom_minimum_size = Vector2(DATE_WIDTH, 0)
		date_label.add_theme_color_override("font_color", MUTED_COLOR)
		row.add_child(date_label)
	var concept_label := Label.new()
	concept_label.text = concept
	concept_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	concept_label.clip_text = true
	if color == MUTED_COLOR:
		concept_label.add_theme_color_override("font_color", MUTED_COLOR)
	row.add_child(concept_label)
	if color != MUTED_COLOR:
		var amount_label := Label.new()
		amount_label.text = _signed(amount)
		amount_label.custom_minimum_size = Vector2(AMOUNT_WIDTH, 0)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.add_theme_color_override("font_color", color)
		row.add_child(amount_label)
	if bold:
		for label: Node in row.get_children():
			(label as Label).add_theme_font_size_override("font_size", SECTION_FONT_SIZE - 1)
	return row


static func _signed(amount: int) -> String:
	if amount > 0:
		return "+" + MoneyFormat.format(amount)
	if amount < 0:
		return "−" + MoneyFormat.format(-amount)
	return MoneyFormat.format(0)


static func _row_text(row: Node) -> String:
	var parts: Array[String] = []
	for label: Node in row.get_children():
		parts.append((label as Label).text.strip_edges())
	return " | ".join(parts)


static func _clear(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
