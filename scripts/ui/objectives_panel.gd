# Objetivos guiados: lista plegable a la izquierda, bajo el dinero, con su avance y recompensa.
# Se pliega sola con un panel izquierdo abierto y luego vuelve como la tenía el jugador.
class_name ObjectivesPanel
extends CanvasLayer

const MARGIN: float = 16.0
const MARGIN_TOP: float = 100.0
const PANEL_WIDTH: float = 340.0
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const REWARD_COLOR := Color(0.55, 0.85, 0.5)

var _panel: PanelContainer
var _header: Button
var _rows: VBoxContainer
# Elección del jugador (true = desplegada) y si un panel izquierdo la tapa.
var _expanded: bool = true
var _suppressed: bool = false


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.position = Vector2(MARGIN, MARGIN_TOP)
	_panel.custom_minimum_size.x = PANEL_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_header = Button.new()
	_header.flat = true
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.focus_mode = Control.FOCUS_NONE
	_header.pressed.connect(func() -> void: set_expanded(not _expanded))
	box.add_child(_header)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)
	EventBus.objectives_changed.connect(_refresh)
	EventBus.staff_changed.connect(_refresh)
	EventBus.projects_changed.connect(_refresh)
	EventBus.company_value_changed.connect(func(_value: int) -> void: _refresh())
	_refresh()


## Despliega (true) o pliega (false) la lista.
func set_expanded(expanded: bool) -> void:
	_expanded = expanded
	_refresh()


## true: un panel izquierdo está abierto y la lista se pliega hasta que se cierre.
func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed
	_refresh()


func is_expanded() -> bool:
	return _expanded and not _suppressed


func is_shown() -> bool:
	return _panel.visible


func get_header_button() -> Button:
	return _header


## Texto de la lista, un renglón por línea (para las pruebas).
func get_text() -> String:
	var lines: Array[String] = [_header.text]
	if _rows.visible:
		for row: Node in _rows.get_children():
			for label: Node in row.get_children():
				lines.append((label as Label).text)
	return "\n".join(lines)


func _refresh() -> void:
	if _rows == null:
		return
	var objectives: Array[Dictionary] = Company.get_visible_objectives()
	_panel.visible = not objectives.is_empty() and not _suppressed
	_header.text = "%s Objetivos" % ("▾" if is_expanded() else "▸")
	_rows.visible = is_expanded()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for objective: Dictionary in objectives:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var progress: String = String(Company.get_objective_progress(objective)["progress"])
		var title := Label.new()
		title.text = "• %s%s" % [objective["text"], "  (%s)" % progress if not progress.is_empty() else ""]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = PANEL_WIDTH
		row.add_child(title)
		var reward := Label.new()
		reward.text = "   Recompensa: %s" % _describe_reward(objective)
		reward.add_theme_color_override("font_color", REWARD_COLOR)
		reward.add_theme_font_size_override("font_size", 14)
		row.add_child(reward)
		_rows.add_child(row)
	_panel.reset_size()


static func _describe_reward(objective: Dictionary) -> String:
	var parts: Array[String] = []
	var money: int = int(objective.get("money", 0))
	if money > 0:
		parts.append(MoneyFormat.format(money))
	var stars: float = float(objective.get("reputation", 0.0))
	if stars > 0.0:
		parts.append("+%s ★" % String.num(stars, 2))
	return " y ".join(PackedStringArray(parts)) if not parts.is_empty() else "—"
