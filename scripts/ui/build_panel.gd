# Panel del modo construcción: abajo al centro la barra de menús (otros paneles añaden su botón) o,
# en construcción, las herramientas por secciones, el estado de la última acción y «Salir».
class_name BuildPanel
extends CanvasLayer

## Se entró (true) o se salió (false) del modo construcción.
signal build_mode_changed(active: bool)
## Se eligió una herramienta (ver BuildController).
signal tool_selected(tool: String)
## El jugador respondió la pregunta de confirmación (mudar la Oficina Ejecutiva).
signal confirm_answered(accept: bool)
## Se pulsó Paredes: subir (true) o bajar las paredes.
signal walls_toggled(up: bool)
## Se pulsó Comprar en la fila del terreno.

## Secciones del panel en orden: id → nombre del botón.
const SECTION_STRUCTURE: String = "structure"
const SECTION_FURNITURE: String = "furniture"
const SECTION_ROOMS: String = "rooms"
const SECTION_LAND: String = "land"
const SECTION_NAMES: Dictionary[String, String] = {
	SECTION_STRUCTURE: "Estructura", SECTION_FURNITURE: "Muebles", SECTION_ROOMS: "Habitaciones", SECTION_LAND: "Terreno",
}

const MARGIN_BOTTOM: float = 16.0
## Ancho del panel de construcción si la pantalla lo deja.
const BUILD_PANEL_WIDTH: float = 1000.0

# Botón «?» de ayuda.
var _help_button: Button
var _walls_button: Button
var _menu_bar: HFlowContainer
# Herramientas en filas que se acomodan al ancho, dentro de un desplazamiento.
var _tools_scroll: ScrollContainer
var _tool_groups: Array[HFlowContainer] = []
# Sección → su grupo de herramientas (Terreno no tiene: solo su fila).
var _section_groups: Dictionary[String, HFlowContainer] = {}
var _section_buttons: Dictionary[String, Button] = {}
# Herramienta → sección.
var _tool_sections: Dictionary[String, String] = {}
var _section: String = SECTION_STRUCTURE
# Categorías de muebles: id → botón y su fila; mueble → categoría; la abierta.
var _category_buttons: Dictionary[String, Button] = {}
var _category_groups: Dictionary[String, HFlowContainer] = {}
var _tool_categories: Dictionary[String, String] = {}
var _category: String = ""
var _open_button: Button
var _panel: PanelContainer
var _status_label: Label
var _confirm_row: HBoxContainer
var _confirm_yes: Button
var _confirm_no: Button
var _tool_buttons: Dictionary[String, Button] = {}
var _exit_button: Button
var _land_row: HFlowContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# La barra se parte en filas si no entra a lo ancho.
	_menu_bar = HFlowContainer.new()
	_menu_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	_menu_bar.add_theme_constant_override("h_separation", 8)
	_menu_bar.add_theme_constant_override("v_separation", 8)
	root.add_child(_menu_bar)
	_open_button = Button.new()
	_open_button.text = "Construir"
	Hud.style_bar_button(_open_button, "build", true)
	_open_button.pressed.connect(func() -> void: set_build_mode(true))
	_menu_bar.add_child(_open_button)
	_menu_bar.anchor_left = 0.0
	_menu_bar.anchor_right = 1.0
	_menu_bar.anchor_top = 1.0
	_menu_bar.anchor_bottom = 1.0
	_menu_bar.offset_left = UiLayout.MARGIN
	_menu_bar.offset_right = -UiLayout.MARGIN
	_menu_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu_bar.offset_top = -MARGIN_BOTTOM
	_menu_bar.offset_bottom = -MARGIN_BOTTOM
	_menu_bar.resized.connect(_update_layout)
	_menu_bar.visibility_changed.connect(_update_layout)
	get_viewport().size_changed.connect(_update_layout)

	_panel = PanelContainer.new()
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	var group := ButtonGroup.new()
	# Grupos de herramientas: estructura, muebles y habitaciones.
	var structure: Array[Array] = [
		[BuildController.TOOL_WALL, ConstructionCatalog.get_display_name(ConstructionCatalog.WALL)],
		[BuildController.TOOL_DOOR, ConstructionCatalog.get_display_name(ConstructionCatalog.DOOR)],
		[BuildController.TOOL_WINDOW, ConstructionCatalog.get_display_name(ConstructionCatalog.WINDOW)],
	]
	for floor_type: String in ConstructionCatalog.get_floor_types():
		structure.append([floor_type, ConstructionCatalog.get_display_name(floor_type)])
	structure.append([BuildController.TOOL_SELL, "Vender"])
	# Muebles: fila de categorías con Girar y Mejorar; debajo, los de la categoría abierta.
	var furniture: Array[Array] = [[BuildController.TOOL_ROTATE, "Girar"], [BuildController.TOOL_UPGRADE, "Mejorar"]]
	var by_category: Dictionary[String, Array] = {}
	for category: String in FurnitureCatalog.get_categories():
		by_category[category] = [] as Array[Array]
	for id: String in FurnitureCatalog.get_ids():
		var item: Dictionary = FurnitureCatalog.get_item(id)
		var category: String = FurnitureCatalog.get_category(id)
		if not by_category.has(category):
			by_category[category] = [] as Array[Array]
		by_category[category].append([id, "%s $%d" % [item["short_name"], item["price"]]])
	var room_tools: Array[Array] = []
	for type_id: String in RoomCatalog.get_type_ids():
		room_tools.append([type_id, RoomCatalog.get_display_name(type_id)])
	room_tools.append([BuildController.TOOL_UNMARK_ROOM, "Quitar habitación"])
	# Fila de secciones, con la ayuda y Salir.
	var sections := HFlowContainer.new()
	sections.alignment = FlowContainer.ALIGNMENT_CENTER
	sections.add_theme_constant_override("h_separation", 4)
	sections.add_theme_constant_override("v_separation", 4)
	rows.add_child(sections)
	var section_group := ButtonGroup.new()
	for section: String in SECTION_NAMES:
		var section_button := Button.new()
		section_button.text = SECTION_NAMES[section]
		section_button.toggle_mode = true
		section_button.focus_mode = Control.FOCUS_NONE
		section_button.button_group = section_group
		section_button.pressed.connect(set_section.bind(section))
		sections.add_child(section_button)
		_section_buttons[section] = section_button
	# Paredes arriba / abajo: solo la vista (main decide; también con P).
	_walls_button = Button.new()
	_walls_button.name = "WallsButton"
	_walls_button.text = "Paredes"
	_walls_button.tooltip_text = "Paredes arriba / abajo (P)"
	_walls_button.toggle_mode = true
	_walls_button.icon = SpriteLibrary.get_ui_icon("walls")
	_walls_button.focus_mode = Control.FOCUS_NONE
	_walls_button.toggled.connect(func(pressed: bool) -> void: walls_toggled.emit(pressed))
	sections.add_child(_walls_button)
	_help_button = HelpButton.create("build")
	sections.add_child(_help_button)
	_exit_button = Button.new()
	_exit_button.text = "Salir"
	_exit_button.pressed.connect(func() -> void: set_build_mode(false))
	sections.add_child(_exit_button)
	rows.add_child(HSeparator.new())
	_tools_scroll = ScrollContainer.new()
	_tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_tools_scroll)
	var tool_rows := VBoxContainer.new()
	tool_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tools_scroll.add_child(tool_rows)
	_section_groups[SECTION_STRUCTURE] = _add_tool_row(tool_rows, structure, group, SECTION_STRUCTURE)
	var furniture_row: HFlowContainer = _add_tool_row(tool_rows, furniture, group, SECTION_FURNITURE)
	_section_groups[SECTION_FURNITURE] = furniture_row
	var category_group := ButtonGroup.new()
	var index: int = 0
	for category: String in by_category:
		var category_button := Button.new()
		category_button.text = String(FurnitureCatalog.get_categories().get(category, category))
		category_button.toggle_mode = true
		category_button.focus_mode = Control.FOCUS_NONE
		category_button.button_group = category_group
		category_button.pressed.connect(set_category.bind(category))
		furniture_row.add_child(category_button)
		furniture_row.move_child(category_button, index)
		index += 1
		_category_buttons[category] = category_button
		var entries: Array[Array] = []
		entries.assign(by_category[category])
		_category_groups[category] = _add_tool_row(tool_rows, entries, group, SECTION_FURNITURE)
		for entry: Array in entries:
			_tool_categories[String(entry[0])] = category
		if _category.is_empty():
			_category = category
	furniture_row.add_child(VSeparator.new())
	furniture_row.move_child(furniture_row.get_child(-1), index)
	_section_groups[SECTION_ROOMS] = _add_tool_row(tool_rows, room_tools, group, SECTION_ROOMS)
	# Terreno: un botón oculto mantiene la herramienta en el grupo; se ve solo su fila.
	var land_tool := Button.new()
	land_tool.toggle_mode = true
	land_tool.button_group = group
	land_tool.visible = false
	tool_rows.add_child(land_tool)
	_tool_buttons[BuildController.TOOL_LAND] = land_tool
	_tool_sections[BuildController.TOOL_LAND] = SECTION_LAND
	_build_land_row(tool_rows)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_status_label)
	# Pregunta de confirmación (mudar la Oficina Ejecutiva): Sí / No, oculta hasta que haga falta.
	_confirm_row = HBoxContainer.new()
	_confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_row.add_theme_constant_override("separation", 8)
	_confirm_row.visible = false
	rows.add_child(_confirm_row)
	_confirm_yes = Button.new()
	_confirm_yes.text = "Sí, mudar"
	_confirm_yes.pressed.connect(func() -> void: confirm_answered.emit(true))
	_confirm_row.add_child(_confirm_yes)
	_confirm_no = Button.new()
	_confirm_no.text = "No"
	_confirm_no.pressed.connect(func() -> void: confirm_answered.emit(false))
	_confirm_row.add_child(_confirm_no)
	_anchor_bottom_center(_panel)

	_tool_buttons[BuildController.TOOL_WALL].button_pressed = true
	_show_section(SECTION_STRUCTURE)
	_panel.visible = false
	EventBus.stage_changed.connect(func(_stage: int) -> void: _refresh_room_locks())
	EventBus.rooms_unlocked.connect(_refresh_room_locks)
	_refresh_room_locks()


## Entra o sale del modo construcción.
func set_build_mode(active: bool) -> void:
	_menu_bar.visible = not active
	_panel.visible = active
	if active:
		_fit_panel()
	_status_label.text = "El tiempo está en pausa." if active else ""
	build_mode_changed.emit(active)


func is_build_mode() -> bool:
	return _panel.visible


## Elige una herramienta como si se hubiera pulsado su botón (abre su sección).
func select_tool(tool: String) -> void:
	if _tool_categories.has(tool):
		_category = _tool_categories[tool]
	_show_section(get_section_of(tool))
	_tool_buttons[tool].button_pressed = true
	_on_tool_pressed(tool)


## Abre una sección; si la herramienta elegida es de otra, elige la primera de esta.
func set_section(section: String) -> void:
	_show_section(section)
	var current: String = get_selected_tool()
	if get_section_of(current) != section:
		var first: String = BuildController.TOOL_LAND if section == SECTION_LAND else ""
		var tools_row: HFlowContainer = _category_groups[_category] if section == SECTION_FURNITURE \
			else _section_groups.get(section)
		if first.is_empty() and tools_row != null:
			for child: Node in tools_row.get_children():
				var button := child as Button
				if button != null and not button.disabled:
					first = _tool_buttons.find_key(button)
					break
		if not first.is_empty():
			select_tool(first)


## Abre una categoría de Muebles; si el mueble elegido es de otra, elige el primero de esta.
func set_category(category: String) -> void:
	_category = category
	_show_section(SECTION_FURNITURE)
	var current: String = get_selected_tool()
	var keep: bool = current == BuildController.TOOL_ROTATE or current == BuildController.TOOL_UPGRADE \
		or _tool_categories.get(current, "") == category
	if keep:
		return
	for child: Node in _category_groups[category].get_children():
		var button := child as Button
		if button != null and not button.disabled:
			select_tool(_tool_buttons.find_key(button))
			return


## Botón a pulsar para llegar a una herramienta: el suyo si se ve; si no, el de su sección o categoría.
func get_button_toward(tool: String) -> Button:
	var button: Button = get_tool_button(tool)
	if button == null or button.is_visible_in_tree() or not _panel.visible:
		return button
	if _section != get_section_of(tool):
		return get_section_button(get_section_of(tool))
	return get_category_button(get_category_of(tool)) if _tool_categories.has(tool) else button


## Categoría de muebles abierta.
func get_category() -> String:
	return _category


## Botón de una categoría de muebles.
func get_category_button(category: String) -> Button:
	return _category_buttons.get(category)


## Categoría de un mueble ("" si la herramienta no es un mueble).
func get_category_of(tool: String) -> String:
	return _tool_categories.get(tool, "")


## Sección abierta (SECTION_*).
func get_section() -> String:
	return _section


## Sección de una herramienta.
func get_section_of(tool: String) -> String:
	return _tool_sections.get(tool, SECTION_STRUCTURE)


## Botón de una sección.
func get_section_button(section: String) -> Button:
	return _section_buttons.get(section)


## Herramienta elegida ("" si ninguna).
func get_selected_tool() -> String:
	for tool: String in _tool_buttons:
		if _tool_buttons[tool].button_pressed:
			return tool
	return ""


func _show_section(section: String) -> void:
	_section = section
	_section_buttons[section].set_pressed_no_signal(true)
	for id: String in _section_groups:
		_section_groups[id].visible = id == section
	for id: String in _category_groups:
		_category_groups[id].visible = section == SECTION_FURNITURE and id == _category
	if _category_buttons.has(_category):
		_category_buttons[_category].set_pressed_no_signal(true)
	_land_row.visible = section == SECTION_LAND
	if _panel != null and _panel.visible:
		_fit_panel()


func is_land_row_visible() -> bool:
	return _land_row.visible


func show_status(text: String) -> void:
	_status_label.text = text


## Muestra los botones Sí / No (text vacío los oculta); la pregunta va en el estado.
func show_confirm(text: String) -> void:
	_confirm_row.visible = not text.is_empty()
	if not text.is_empty():
		_status_label.text = text


## Botones de la pregunta de confirmación: "yes" o "no".
func get_confirm_button(key: String) -> Button:
	return _confirm_yes if key == "yes" else _confirm_no


func is_confirm_visible() -> bool:
	return _confirm_row.visible


## Barra de menús de abajo al centro (se oculta en modo construcción).
func get_menu_bar() -> HFlowContainer:
	return _menu_bar


func get_open_button() -> Button:
	return _open_button


func get_exit_button() -> Button:
	return _exit_button


func get_tool_button(tool: String) -> Button:
	return _tool_buttons.get(tool, null)


# Un grupo de herramientas cuyos botones se parten en filas según el ancho del panel.
func _add_tool_row(parent: Container, entries: Array[Array], group: ButtonGroup, section: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	parent.add_child(row)
	_tool_groups.append(row)
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		var tool: String = entry[0]
		button.pressed.connect(func() -> void: _on_tool_pressed(tool))
		row.add_child(button)
		_tool_buttons[tool] = button
		_tool_sections[tool] = section
	return row


# Los tipos de habitación de una etapa no alcanzada quedan deshabilitados.
func _refresh_room_locks() -> void:
	for type_id: String in RoomCatalog.get_type_ids():
		var button: Button = _tool_buttons[type_id]
		var unlocked: bool = Company.is_room_unlocked(type_id)
		button.disabled = not unlocked
		button.tooltip_text = Company.room_lock_reason(type_id)
		if not unlocked and button.button_pressed:
			select_tool(BuildController.TOOL_WALL)
	if _section_groups.has(_section):
		_show_section(_section)


func _on_tool_pressed(tool: String) -> void:
	tool_selected.emit(tool)


func _build_land_row(parent: Container) -> void:
	_land_row = HFlowContainer.new()
	_land_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_land_row.add_theme_constant_override("h_separation", 8)
	_land_row.add_theme_constant_override("v_separation", 4)
	parent.add_child(_land_row)
	var hint := Label.new()
	hint.text = BuildController.LAND_HINT
	_land_row.add_child(hint)
	_land_row.visible = false


# La barra cambió de alto: guarda cuánto reserva abajo y avisa a los paneles.
# Oculta (Ajustes, pausa, construcción) no cambia.
func _update_layout() -> void:
	if _menu_bar.is_visible_in_tree():
		var view: Vector2 = _menu_bar.get_viewport_rect().size
		var space: float = view.y - _menu_bar.get_global_rect().position.y + UiLayout.BAR_GAP
		if not is_equal_approx(space, UiLayout.bottom_space):
			UiLayout.bottom_space = space
	EventBus.ui_layout_changed.emit()
	if _panel.visible:
		_fit_panel()


# Mide lo que entra en pantalla: todo el ancho y, de alto, deja libre arriba el dinero y el reloj
# (UiLayout.top_space); si las herramientas no entran, se desplazan.
func _fit_panel() -> void:
	var view: Vector2 = _panel.get_viewport_rect().size
	var width: float = minf(BUILD_PANEL_WIDTH, view.x - UiLayout.MARGIN * 2.0)
	_panel.custom_minimum_size.x = width
	_tools_scroll.custom_minimum_size.y = 0.0
	var tools_height: float = 0.0
	for row: HFlowContainer in _tool_groups + [_land_row] as Array[HFlowContainer]:
		# Alto de cada grupo que se ve con el ancho que tendrá.
		if row.visible:
			tools_height += _flow_height(row, width - 16.0) + 4.0
	var other: float = _panel.get_combined_minimum_size().y - _tools_scroll.get_combined_minimum_size().y
	var available: float = view.y - UiLayout.top_space - MARGIN_BOTTOM - other
	_tools_scroll.custom_minimum_size.y = clampf(tools_height, 60.0, maxf(available, 60.0))
	_anchor_bottom_center(_panel)


# Alto que ocupan los botones de un grupo puestos en filas de ese ancho.
func _flow_height(row: HFlowContainer, width: float) -> float:
	var line_width: float = 0.0
	var line_height: float = 0.0
	var total: float = 0.0
	var gap: float = 4.0
	for child: Node in row.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		var size: Vector2 = control.get_combined_minimum_size()
		if line_width > 0.0 and line_width + gap + size.x > width:
			total += line_height + gap
			line_width = 0.0
			line_height = 0.0
		line_width += (gap if line_width > 0.0 else 0.0) + size.x
		line_height = maxf(line_height, size.y)
	return total + line_height


func _anchor_bottom_center(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	control.offset_top -= MARGIN_BOTTOM
	control.offset_bottom -= MARGIN_BOTTOM


## Botón «?» que abre la ayuda del modo construcción.
## Botón Paredes de la fila de secciones.
func get_walls_button() -> Button:
	return _walls_button


func get_help_button() -> Button:
	return _help_button
