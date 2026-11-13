# Panel del modo construcción, parte de la interfaz superpuesta (el dinero y el reloj
# están en Hud). Abajo al centro: la barra de menús con "Construir" (otros paneles,
# como Ajustes, añaden ahí su botón) o, en modo construcción, las herramientas, el
# estado de la última acción y "Salir". Con la herramienta Terreno (hito 25) aparece una
# fila para elegir el lado, el ancho, el fondo y la posición del terreno, y Comprar.
class_name BuildPanel
extends CanvasLayer

## Se entró (true) o se salió (false) del modo construcción.
signal build_mode_changed(active: bool)
## Se eligió una herramienta (ver BuildController).
signal tool_selected(tool: String)
## Cambió el terreno elegido (lado, ancho, fondo y posición a lo largo del lado).
signal land_changed(side: String, width: int, depth: int, offset: int)
## Se pulsó Comprar en la fila del terreno.
signal land_buy_requested

const SIDE_NAMES: Dictionary[String, String] = {
	Builder.SIDE_NORTH: "Norte", Builder.SIDE_SOUTH: "Sur", Builder.SIDE_EAST: "Este", Builder.SIDE_WEST: "Oeste",
}
const DEFAULT_LAND_WIDTH: int = 4
const DEFAULT_LAND_DEPTH: int = 3

const MARGIN_BOTTOM: float = 16.0
## Botones por fila de muebles y de habitaciones.
const MAX_ROW_BUTTONS: int = 6

var _menu_bar: HBoxContainer
var _open_button: Button
var _panel: PanelContainer
var _status_label: Label
var _tool_buttons: Dictionary[String, Button] = {}
var _exit_button: Button
var _land_row: HBoxContainer
var _side_buttons: Dictionary[String, Button] = {}
var _land_labels: Dictionary[String, Label] = {}
var _land_buttons: Dictionary[String, Button] = {}
var _buy_button: Button
var _land_side: String = Builder.SIDE_EAST
var _land_width: int = DEFAULT_LAND_WIDTH
var _land_depth: int = DEFAULT_LAND_DEPTH
var _land_offset: int = 0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_menu_bar = HBoxContainer.new()
	_menu_bar.add_theme_constant_override("separation", 8)
	root.add_child(_menu_bar)
	_open_button = Button.new()
	_open_button.text = "Construir"
	_open_button.custom_minimum_size = Hud.MENU_BUTTON_SIZE
	_open_button.pressed.connect(func() -> void: set_build_mode(true))
	_menu_bar.add_child(_open_button)
	_anchor_bottom_center(_menu_bar)

	_panel = PanelContainer.new()
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	var group := ButtonGroup.new()
	# Primera fila: estructura. Segunda fila: muebles (con su precio) y Girar.
	# Tercera fila: tipos de habitación y Quitar habitación.
	var structure: Array[Array] = [
		[BuildController.TOOL_WALL, ConstructionCatalog.get_display_name(ConstructionCatalog.WALL)],
		[BuildController.TOOL_DOOR, ConstructionCatalog.get_display_name(ConstructionCatalog.DOOR)],
		[BuildController.TOOL_WINDOW, ConstructionCatalog.get_display_name(ConstructionCatalog.WINDOW)],
	]
	for floor_type: String in ConstructionCatalog.get_floor_types():
		structure.append([floor_type, ConstructionCatalog.get_display_name(floor_type)])
	structure.append([BuildController.TOOL_SELL, "Vender"])
	structure.append([BuildController.TOOL_LAND, "Terreno"])
	var furniture: Array[Array] = []
	for id: String in FurnitureCatalog.get_ids():
		var item: Dictionary = FurnitureCatalog.get_item(id)
		furniture.append([id, "%s $%d" % [item["short_name"], item["price"]]])
	furniture.append([BuildController.TOOL_ROTATE, "Girar"])
	furniture.append([BuildController.TOOL_UPGRADE, "Mejorar"])
	var room_tools: Array[Array] = []
	for type_id: String in RoomCatalog.get_type_ids():
		room_tools.append([type_id, RoomCatalog.get_display_name(type_id)])
	room_tools.append([BuildController.TOOL_UNMARK_ROOM, "Quitar habitación"])
	var structure_row: HBoxContainer = _add_tool_row(rows, structure, group)
	_add_tool_rows(rows, furniture, group)
	_add_tool_rows(rows, room_tools, group)
	_build_land_row(rows)
	_exit_button = Button.new()
	_exit_button.text = "Salir"
	_exit_button.pressed.connect(func() -> void: set_build_mode(false))
	structure_row.add_child(_exit_button)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_status_label)
	_anchor_bottom_center(_panel)

	_tool_buttons[BuildController.TOOL_WALL].button_pressed = true
	_panel.visible = false
	EventBus.stage_changed.connect(func(_stage: int) -> void: _refresh_room_locks())
	EventBus.rooms_unlocked.connect(_refresh_room_locks)
	_refresh_room_locks()


## Entra o sale del modo construcción.
func set_build_mode(active: bool) -> void:
	_menu_bar.visible = not active
	_panel.visible = active
	_status_label.text = "El tiempo está en pausa." if active else ""
	build_mode_changed.emit(active)


func is_build_mode() -> bool:
	return _panel.visible


## Elige una herramienta como si se hubiera pulsado su botón.
func select_tool(tool: String) -> void:
	_tool_buttons[tool].button_pressed = true
	_on_tool_pressed(tool)


## Elige el terreno como si se hubieran usado los botones de la fila.
func set_land(side: String, width: int, depth: int, offset: int) -> void:
	_land_side = side
	_land_width = width
	_land_depth = depth
	_land_offset = offset
	_refresh_land()


## Terreno elegido: {"side", "width", "depth", "offset"}.
func get_land() -> Dictionary:
	return {"side": _land_side, "width": _land_width, "depth": _land_depth, "offset": _land_offset}


func is_land_row_visible() -> bool:
	return _land_row.visible


## Botones de la fila del terreno: "north"…"west", "width-", "width+", "depth-", "depth+",
## "offset-", "offset+" y "buy".
func get_land_button(key: String) -> Button:
	if key == "buy":
		return _buy_button
	if _side_buttons.has(key):
		return _side_buttons[key]
	return _land_buttons[key]


func show_status(text: String) -> void:
	_status_label.text = text


## Barra de menús de abajo al centro (se oculta en modo construcción).
func get_menu_bar() -> HBoxContainer:
	return _menu_bar


func get_open_button() -> Button:
	return _open_button


func get_exit_button() -> Button:
	return _exit_button


func get_tool_button(tool: String) -> Button:
	return _tool_buttons[tool]


# Pone los botones en filas de hasta MAX_ROW_BUTTONS para que el panel quepa en pantalla.
func _add_tool_rows(parent: Container, entries: Array[Array], group: ButtonGroup) -> void:
	for start: int in range(0, entries.size(), MAX_ROW_BUTTONS):
		_add_tool_row(parent, entries.slice(start, start + MAX_ROW_BUTTONS), group)


func _add_tool_row(parent: Container, entries: Array[Array], group: ButtonGroup) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		var tool: String = entry[0]
		button.pressed.connect(func() -> void: _on_tool_pressed(tool))
		row.add_child(button)
		_tool_buttons[tool] = button
	return row


# Los tipos de habitación de una etapa que aún no se alcanzó quedan deshabilitados (hito 27).
func _refresh_room_locks() -> void:
	for type_id: String in RoomCatalog.get_type_ids():
		var button: Button = _tool_buttons[type_id]
		var unlocked: bool = Company.is_room_unlocked(type_id)
		button.disabled = not unlocked
		button.tooltip_text = Company.room_lock_reason(type_id)
		if not unlocked and button.button_pressed:
			select_tool(BuildController.TOOL_WALL)


func _on_tool_pressed(tool: String) -> void:
	_land_row.visible = tool == BuildController.TOOL_LAND
	tool_selected.emit(tool)
	if _land_row.visible:
		_refresh_land()


func _build_land_row(parent: Container) -> void:
	_land_row = HBoxContainer.new()
	_land_row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(_land_row)
	var sides := ButtonGroup.new()
	for side: String in Builder.SIDES:
		var button := Button.new()
		button.text = SIDE_NAMES[side]
		button.toggle_mode = true
		button.button_group = sides
		button.pressed.connect(func() -> void:
			_land_side = side
			_land_offset = 0
			_refresh_land())
		_land_row.add_child(button)
		_side_buttons[side] = button
	for key: String in ["width", "depth", "offset"]:
		var title := Label.new()
		title.text = {"width": "  Ancho", "depth": "  Fondo", "offset": "  Posición"}[key]
		_land_row.add_child(title)
		var minus := Button.new()
		minus.text = "−"
		minus.pressed.connect(_step_land.bind(key, -1))
		_land_row.add_child(minus)
		_land_buttons[key + "-"] = minus
		var value := Label.new()
		value.custom_minimum_size = Vector2(28, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_land_row.add_child(value)
		_land_labels[key] = value
		var plus := Button.new()
		plus.text = "+"
		plus.pressed.connect(_step_land.bind(key, 1))
		_land_row.add_child(plus)
		_land_buttons[key + "+"] = plus
	_buy_button = Button.new()
	_buy_button.text = "Comprar"
	_buy_button.pressed.connect(func() -> void: land_buy_requested.emit())
	_land_row.add_child(_buy_button)
	_land_row.visible = false


func _step_land(key: String, step: int) -> void:
	match key:
		"width":
			_land_width += step
		"depth":
			_land_depth += step
		"offset":
			_land_offset += step
	_refresh_land()


# Ajusta los valores a lo que cabe en el solar, actualiza la fila y avisa del cambio.
func _refresh_land() -> void:
	var site: Rect2i = OfficeState.site_rect
	var bounds: Rect2i = OfficeState.lot.get_bounds()
	var lengthwise: bool = _land_side == Builder.SIDE_NORTH or _land_side == Builder.SIDE_SOUTH
	var side_length: int = bounds.size.x if lengthwise else bounds.size.y
	var max_width: int = site.size.x if lengthwise else site.size.y
	var max_depth: int = site.size.y if lengthwise else site.size.x
	_land_width = clampi(_land_width, 1, max_width)
	_land_depth = clampi(_land_depth, 1, max_depth)
	# El terreno tiene que compartir al menos una fila (o columna) con el local.
	_land_offset = clampi(_land_offset, 1 - _land_width, side_length - 1)
	_side_buttons[_land_side].button_pressed = true
	_land_labels["width"].text = str(_land_width)
	_land_labels["depth"].text = str(_land_depth)
	_land_labels["offset"].text = str(_land_offset)
	_land_buttons["width-"].disabled = _land_width <= 1
	_land_buttons["width+"].disabled = _land_width >= max_width
	_land_buttons["depth-"].disabled = _land_depth <= 1
	_land_buttons["depth+"].disabled = _land_depth >= max_depth
	_land_buttons["offset-"].disabled = _land_offset <= 1 - _land_width
	_land_buttons["offset+"].disabled = _land_offset >= side_length - 1
	land_changed.emit(_land_side, _land_width, _land_depth, _land_offset)


func _anchor_bottom_center(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	control.offset_top -= MARGIN_BOTTOM
	control.offset_bottom -= MARGIN_BOTTOM
