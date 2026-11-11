# Panel del modo construcción, parte de la interfaz superpuesta (el dinero y el reloj
# están en Hud). Abajo al centro: la barra de menús con "Construir" (otros paneles,
# como Ajustes, añaden ahí su botón) o, en modo construcción, las herramientas, el
# estado de la última acción y "Salir".
class_name BuildPanel
extends CanvasLayer

## Se entró (true) o se salió (false) del modo construcción.
signal build_mode_changed(active: bool)
## Se eligió una herramienta (ver BuildController).
signal tool_selected(tool: String)

const MARGIN_BOTTOM: float = 16.0

var _menu_bar: HBoxContainer
var _open_button: Button
var _panel: PanelContainer
var _status_label: Label
var _tool_buttons: Dictionary[String, Button] = {}
var _exit_button: Button


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
	_open_button.custom_minimum_size = Vector2(160, 44)
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
	]
	for floor_type: String in ConstructionCatalog.get_floor_types():
		structure.append([floor_type, ConstructionCatalog.get_display_name(floor_type)])
	structure.append([BuildController.TOOL_SELL, "Vender"])
	var furniture: Array[Array] = []
	for id: String in FurnitureCatalog.get_ids():
		var item: Dictionary = FurnitureCatalog.get_item(id)
		furniture.append([id, "%s $%d" % [item["name"], item["price"]]])
	furniture.append([BuildController.TOOL_ROTATE, "Girar"])
	var room_tools: Array[Array] = []
	for type_id: String in RoomCatalog.get_type_ids():
		room_tools.append([type_id, RoomCatalog.get_display_name(type_id)])
	room_tools.append([BuildController.TOOL_UNMARK_ROOM, "Quitar habitación"])
	var structure_row: HBoxContainer = _add_tool_row(rows, structure, group)
	_add_tool_row(rows, furniture, group)
	_add_tool_row(rows, room_tools, group)
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
	tool_selected.emit(tool)


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
		button.pressed.connect(func() -> void: tool_selected.emit(tool))
		row.add_child(button)
		_tool_buttons[tool] = button
	return row


func _anchor_bottom_center(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	control.offset_top -= MARGIN_BOTTOM
	control.offset_bottom -= MARGIN_BOTTOM
