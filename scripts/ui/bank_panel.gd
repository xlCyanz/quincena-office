# Menú Banco (diseño, 8.1 y 12.3): el saldo de la cuenta empresarial, los ingresos y
# gastos por concepto del mes actual o del anterior (con «<» y «>») y el historial de
# movimientos, los más nuevos arriba. Los préstamos y la calificación llegan en los
# hitos 21 y 22.
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
const MARGIN_TOP: float = 76.0
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
	var current: int = Economy.get_current_month()
	if _shown_month == _last_current:
		_shown_month = current
	_last_current = current
	_shown_month = clampi(_shown_month, maxi(1, current - 1), current)
	_month_label.text = "Mes %d (%s)" % [_shown_month, "este mes" if _shown_month == current else "mes anterior"]
	_previous_button.disabled = _shown_month <= maxi(1, current - 1)
	_next_button.disabled = _shown_month >= current
	_refresh_month()
	_refresh_movements()


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
