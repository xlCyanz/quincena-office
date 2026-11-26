# Panel del modo construcción: abajo al centro la barra de menús (Construir, Tienda y los botones que añaden
# otros paneles) o, en construcción, la bandeja: las secciones (Inventario, Estructura, Habitaciones, Terreno),
# el contenido de la sección abierta, el estado, las herramientas para lo ya puesto y «Salir». La Tienda
# (ShopScreen) se abre desde el mapa a pantalla completa; lo comprado aparece en Inventario y de ahí se coloca.
class_name BuildPanel
extends CanvasLayer

## Se entró (true) o se salió (false) del modo construcción.
signal build_mode_changed(active: bool)
## Se eligió una herramienta (ver BuildController).
signal tool_selected(tool: String)
## El jugador respondió la pregunta de confirmación (mudar la Oficina Ejecutiva, vender terreno).
signal confirm_answered(accept: bool)
## Se pulsó Paredes: subir (true) o bajar las paredes.
signal walls_toggled(up: bool)
## Se pidió comprar en la Tienda (main lo pasa a BuildController.buy y devuelve el resultado con show_buy_result).
signal buy_requested(id: String, count: int)

## Secciones de la bandeja en orden: id → nombre del botón (Inventario lleva la cantidad).
const SECTION_FURNITURE: String = "furniture"
const SECTION_STRUCTURE: String = "structure"
const SECTION_ROOMS: String = "rooms"
const SECTION_LAND: String = "land"
const SECTION_NAMES: Dictionary[String, String] = {
	SECTION_FURNITURE: "Inventario", SECTION_STRUCTURE: "Estructura", SECTION_ROOMS: "Habitaciones", SECTION_LAND: "Terreno",
}
## Herramientas para lo ya puesto: siempre a la vista, en cualquier sección.
const EDIT_TOOLS: Array[Array] = [
	[BuildController.TOOL_MOVE, "Mover"], [BuildController.TOOL_ROTATE, "Girar"], [BuildController.TOOL_UPGRADE, "Mejorar"],
	[BuildController.TOOL_STORE, "Guardar"], [BuildController.TOOL_SELL, "Vender"],
]

const MARGIN_BOTTOM: float = 16.0
const INVENTORY_CARD_SIZE := Vector2(128.0, 156.0)
const INVENTORY_IMAGE_HEIGHT: float = 96.0
const EMPTY_INVENTORY_TEXT: String = "Tu inventario está vacío: sal de Construir y compra muebles en la Tienda."

var _help_button: Button
var _walls_button: Button
var _menu_bar: HFlowContainer
var _open_button: Button
var _panel: PanelContainer
var _shop_button: Button
var _shop: ShopScreen
var _section: String = SECTION_FURNITURE
var _section_buttons: Dictionary[String, Button] = {}
# Sección → lo que muestra (Inventario: el desplazamiento con las tarjetas).
var _section_views: Dictionary[String, Control] = {}
var _tool_buttons: Dictionary[String, Button] = {}
# Herramienta → sección (las de EDIT_TOOLS y los muebles no tienen: se ven siempre o en Inventario).
var _tool_sections: Dictionary[String, String] = {}
var _tool_group := ButtonGroup.new()
var _selected: String = BuildController.TOOL_NONE
var _active: bool = false
# Unidades en el inventario en el último repaso (para notar que se acabó lo elegido).
var _stock_before_total: int = 0
var _inventory_row: HBoxContainer
var _inventory_empty: HBoxContainer
var _status_label: Label
var _confirm_row: HBoxContainer
var _confirm_yes: Button
var _confirm_no: Button
var _exit_button: Button
var _land_row: HFlowContainer
# Contenido de la sección abierta: se desplaza si no entra (pantalla chica o interfaz grande).
var _content_scroll: ScrollContainer


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
	# La Tienda se abre desde el mapa, a pantalla completa; lo comprado queda en el Inventario de Construir.
	_shop_button = Button.new()
	_shop_button.name = "ShopButton"
	_shop_button.text = "Tienda"
	Hud.style_bar_button(_shop_button, "shop")
	_shop_button.pressed.connect(func() -> void: set_shop_open(true))
	_menu_bar.add_child(_shop_button)
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
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)
	rows.add_child(_build_top_row())
	rows.add_child(HSeparator.new())
	_content_scroll = ScrollContainer.new()
	rows.add_child(_content_scroll)
	var views := VBoxContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.add_child(views)
	_section_views[SECTION_FURNITURE] = _build_inventory()
	_section_views[SECTION_STRUCTURE] = _build_structure()
	_section_views[SECTION_ROOMS] = _build_rooms()
	_land_row = _build_land_row()
	_section_views[SECTION_LAND] = _land_row
	for section: String in _section_views:
		_section_views[section].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		views.add_child(_section_views[section])
	# Abajo: el estado a la izquierda y las herramientas de edición a la derecha.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	rows.add_child(status_row)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status_label)
	for entry: Array in EDIT_TOOLS:
		var button: Button = _add_tool_button(status_row, entry[0], entry[1], "")
		if entry[0] == BuildController.TOOL_SELL:
			button.theme_type_variation = &"DangerButton"
	# Pregunta de confirmación: Sí / No, oculta hasta que haga falta.
	_confirm_row = HBoxContainer.new()
	_confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_row.add_theme_constant_override("separation", 8)
	_confirm_row.visible = false
	rows.add_child(_confirm_row)
	_confirm_yes = Button.new()
	_confirm_yes.text = "Sí"
	_confirm_yes.pressed.connect(func() -> void: confirm_answered.emit(true))
	_confirm_row.add_child(_confirm_yes)
	_confirm_no = Button.new()
	_confirm_no.text = "No"
	_confirm_no.pressed.connect(func() -> void: confirm_answered.emit(false))
	_confirm_row.add_child(_confirm_no)

	_shop = ShopScreen.new()
	_shop.name = "Shop"
	add_child(_shop)
	_shop.buy_requested.connect(func(id: String, count: int) -> void: buy_requested.emit(id, count))
	_shop.open_changed.connect(_on_shop_open_changed)

	_show_section(SECTION_FURNITURE)
	_panel.visible = false
	_refresh_inventory()
	EventBus.inventory_changed.connect(_refresh_inventory)
	EventBus.stage_changed.connect(func(_stage: int) -> void: _refresh_room_locks())
	EventBus.rooms_unlocked.connect(_refresh_room_locks)
	_refresh_room_locks()


## Entra o sale del modo construcción (al salir se cierra la Tienda). Al entrar, BuildController toma
## la herramienta elegida.
func set_build_mode(active: bool) -> void:
	if not active:
		_shop.set_open(false)
	_active = active
	_menu_bar.visible = not active
	_panel.visible = active
	if active:
		_fit_panel()
	_status_label.text = "El tiempo está en pausa." if active else ""
	build_mode_changed.emit(active)
	if active:
		tool_selected.emit(_selected)


func is_build_mode() -> bool:
	return _active


## Abre o cierra la Tienda a pantalla completa.
func set_shop_open(open: bool) -> void:
	_shop.set_open(open)


func is_shop_open() -> bool:
	return _shop.is_open()


func get_shop() -> ShopScreen:
	return _shop


## Botón Tienda de la barra de menús.
func get_shop_button() -> Button:
	return _shop_button


## Muestra el resultado de una compra en la Tienda.
func show_buy_result(result: Dictionary) -> void:
	_shop.show_result(result)


## Elige una herramienta como si se hubiera pulsado su botón (abre su sección). Un mueble se elige
## aunque no haya en el inventario (entonces se compra al colocarlo).
func select_tool(tool: String) -> void:
	if not _tool_sections.has(tool) and not FurnitureCatalog.get_item(tool).is_empty():
		_show_section(SECTION_FURNITURE)
	elif _tool_sections.has(tool):
		_show_section(_tool_sections[tool])
	_set_selected(tool)
	tool_selected.emit(tool)


## Abre una sección; si la herramienta elegida es de otra, elige la primera de esta.
func set_section(section: String) -> void:
	_show_section(section)
	if _tool_fits_section(_selected, section):
		return
	var first: String = ""
	if section == SECTION_LAND:
		first = BuildController.TOOL_LAND
	elif section == SECTION_FURNITURE:
		first = _first_in_stock()
		if first.is_empty():
			first = BuildController.TOOL_NONE
	else:
		var view: Control = _section_views[section]
		for child: Node in view.get_children():
			var button := child as Button
			if button != null and not button.disabled and _tool_buttons.values().has(button):
				first = _tool_buttons.find_key(button)
				break
	if not first.is_empty():
		select_tool(first)


## Categoría de la Tienda abierta.
func get_category() -> String:
	return _shop.get_category()


## Botón de una categoría de la Tienda.
func get_category_button(category: String) -> Button:
	return _shop.get_category_button(category)


## Categoría de un mueble ("" si la herramienta no es un mueble).
func get_category_of(tool: String) -> String:
	return FurnitureCatalog.get_category(tool) if not FurnitureCatalog.get_item(tool).is_empty() else ""


## Botón a pulsar para llegar a una herramienta. Un mueble: su tarjeta del inventario si hay (o la
## pestaña Inventario); sin existencias, la Tienda (y en ella, su tarjeta). Lo demás: su botón o su sección.
func get_button_toward(tool: String) -> Button:
	var furniture: bool = not FurnitureCatalog.get_item(tool).is_empty()
	if furniture and _shop.is_open():
		return _shop.get_card(tool)
	if furniture:
		# Sin inventario se compra en la Tienda, que está afuera de Construir.
		if OfficeState.get_stock(tool) <= 0:
			return _exit_button if _active else _shop_button
		if not _active:
			return _open_button
		return get_tool_button(tool) if _section == SECTION_FURNITURE else _section_buttons[SECTION_FURNITURE]
	if not _active:
		return get_tool_button(tool)
	var button: Button = get_tool_button(tool)
	if button == null or button.is_visible_in_tree():
		return button
	return get_section_button(get_section_of(tool))


## Sección abierta (SECTION_*).
func get_section() -> String:
	return _section


## Sección de una herramienta (los muebles van en Inventario; las de editar, en ninguna).
func get_section_of(tool: String) -> String:
	if not FurnitureCatalog.get_item(tool).is_empty():
		return SECTION_FURNITURE
	return _tool_sections.get(tool, "")


func get_section_button(section: String) -> Button:
	return _section_buttons.get(section)


## Herramienta elegida.
func get_selected_tool() -> String:
	return _selected


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


## Botón de una herramienta; para un mueble, su tarjeta del inventario (null si no hay).
func get_tool_button(tool: String) -> Button:
	return _tool_buttons.get(tool, null)


func get_walls_button() -> Button:
	return _walls_button


## Botón «?» que abre la ayuda del modo construcción.
func get_help_button() -> Button:
	return _help_button


# Fila de arriba: Tienda, secciones, herramientas de editar, Paredes, ayuda y Salir. Va en una sola
# línea; si no entra a lo ancho, se desplaza de lado.
func _build_top_row() -> Control:
	# Tienda, secciones y herramientas se desplazan si no caben; Paredes, ayuda y Salir quedan fijos a la derecha.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(scroll)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	scroll.add_child(row)
	var section_group := ButtonGroup.new()
	for section: String in SECTION_NAMES:
		var section_button := Button.new()
		section_button.text = SECTION_NAMES[section]
		section_button.toggle_mode = true
		section_button.focus_mode = Control.FOCUS_NONE
		section_button.button_group = section_group
		section_button.pressed.connect(set_section.bind(section))
		row.add_child(section_button)
		_section_buttons[section] = section_button
	var fixed := HBoxContainer.new()
	fixed.add_theme_constant_override("separation", 6)
	bar.add_child(fixed)
	fixed.add_child(VSeparator.new())
	# Paredes arriba / abajo: solo la vista (main decide; también con P).
	_walls_button = Button.new()
	_walls_button.name = "WallsButton"
	_walls_button.text = "Paredes"
	_walls_button.tooltip_text = "Paredes arriba / abajo (P)"
	_walls_button.toggle_mode = true
	_walls_button.icon = SpriteLibrary.get_ui_icon("walls")
	_walls_button.focus_mode = Control.FOCUS_NONE
	_walls_button.toggled.connect(func(pressed: bool) -> void: walls_toggled.emit(pressed))
	fixed.add_child(_walls_button)
	_help_button = HelpButton.create("build")
	fixed.add_child(_help_button)
	_exit_button = Button.new()
	_exit_button.text = "Salir"
	_exit_button.pressed.connect(func() -> void: set_build_mode(false))
	fixed.add_child(_exit_button)
	return bar


# Inventario: tarjetas con la imagen y la cantidad en una fila (se desplaza de lado si no entran).
func _build_inventory() -> Control:
	var box := HBoxContainer.new()
	_inventory_row = HBoxContainer.new()
	_inventory_row.add_theme_constant_override("separation", 8)
	box.add_child(_inventory_row)
	_inventory_empty = HBoxContainer.new()
	_inventory_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_inventory_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_empty.add_theme_constant_override("separation", 12)
	box.add_child(_inventory_empty)
	var empty_label := Label.new()
	empty_label.text = EMPTY_INVENTORY_TEXT
	empty_label.theme_type_variation = &"MutedLabel"
	_inventory_empty.add_child(empty_label)
	return box


func _build_structure() -> Control:
	var row: HFlowContainer = _new_flow()
	for entry: Array in [
		[BuildController.TOOL_WALL, ConstructionCatalog.WALL],
		[BuildController.TOOL_DOOR, ConstructionCatalog.DOOR],
		[BuildController.TOOL_WINDOW, ConstructionCatalog.WINDOW],
	]:
		_add_tool_button(row, entry[0], ConstructionCatalog.get_display_name(entry[1]), SECTION_STRUCTURE)
	for floor_type: String in ConstructionCatalog.get_floor_types():
		_add_tool_button(row, floor_type, ConstructionCatalog.get_display_name(floor_type), SECTION_STRUCTURE)
	return row


func _build_rooms() -> Control:
	var row: HFlowContainer = _new_flow()
	for type_id: String in RoomCatalog.get_type_ids():
		_add_tool_button(row, type_id, RoomCatalog.get_display_name(type_id), SECTION_ROOMS)
	_add_tool_button(row, BuildController.TOOL_UNMARK_ROOM, "Quitar habitación", SECTION_ROOMS)
	return row


# Terreno: un botón oculto mantiene la herramienta en el grupo; se ve solo la ayuda.
func _build_land_row() -> HFlowContainer:
	var row: HFlowContainer = _new_flow()
	var land_tool: Button = _add_tool_button(row, BuildController.TOOL_LAND, "", SECTION_LAND)
	land_tool.visible = false
	var hint := Label.new()
	hint.text = BuildController.LAND_HINT
	row.add_child(hint)
	return row


func _new_flow() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	return row


func _add_tool_button(parent: Container, tool: String, text: String, section: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.button_group = _tool_group
	button.pressed.connect(func() -> void: select_tool(tool))
	parent.add_child(button)
	_tool_buttons[tool] = button
	if not section.is_empty():
		_tool_sections[tool] = section
	return button


# Rehace las tarjetas del inventario. Si se acabó el mueble elegido, queda sin herramienta.
func _refresh_inventory() -> void:
	for id: String in _tool_buttons.keys():
		if not FurnitureCatalog.get_item(id).is_empty():
			_tool_buttons.erase(id)
	for child: Node in _inventory_row.get_children():
		_inventory_row.remove_child(child)
		child.queue_free()
	var total: int = 0
	for id: String in FurnitureCatalog.get_ids():
		var count: int = OfficeState.get_stock(id)
		if count > 0:
			total += count
			_add_inventory_card(id, count)
	_inventory_empty.visible = total == 0
	_section_buttons[SECTION_FURNITURE].text = "%s (%d)" % [SECTION_NAMES[SECTION_FURNITURE], total]
	if _tool_buttons.has(_selected):
		_tool_buttons[_selected].set_pressed_no_signal(true)
	elif not FurnitureCatalog.get_item(_selected).is_empty() and _panel.visible and total < _stock_before_total:
		select_tool(BuildController.TOOL_NONE)
	_stock_before_total = total
	if _panel.visible:
		_fit_panel()



func _add_inventory_card(id: String, count: int) -> void:
	var info: Dictionary = FurnitureCatalog.get_item(id)
	var card := Button.new()
	card.theme_type_variation = &"CardButton"
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.button_group = _tool_group
	card.custom_minimum_size = INVENTORY_CARD_SIZE
	card.tooltip_text = String(info["name"])
	card.pressed.connect(func() -> void: select_tool(id))
	_inventory_row.add_child(card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.custom_minimum_size.y = INVENTORY_IMAGE_HEIGHT
	image.texture = SpriteLibrary.get_furniture_icon(id)
	column.add_child(image)
	var name_label := Label.new()
	name_label.text = String(info["short_name"])
	name_label.theme_type_variation = &"StrongLabel"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var count_label := Label.new()
	count_label.text = "×%d" % count
	count_label.theme_type_variation = &"SectionLabel"
	count_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(count_label)
	_tool_buttons[id] = card


func _first_in_stock() -> String:
	for id: String in FurnitureCatalog.get_ids():
		if OfficeState.get_stock(id) > 0:
			return id
	return ""


func _tool_fits_section(tool: String, section: String) -> bool:
	if section == SECTION_FURNITURE:
		return (_tool_buttons.has(tool) and not FurnitureCatalog.get_item(tool).is_empty()) or tool == BuildController.TOOL_NONE
	return _tool_sections.get(tool, "") == section


func _set_selected(tool: String) -> void:
	_selected = tool
	var button: Button = _tool_buttons.get(tool)
	if button != null:
		button.set_pressed_no_signal(true)
	else:
		var pressed: BaseButton = _tool_group.get_pressed_button()
		if pressed != null:
			pressed.set_pressed_no_signal(false)


func _show_section(section: String) -> void:
	_section = section
	_section_buttons[section].set_pressed_no_signal(true)
	for id: String in _section_views:
		_section_views[id].visible = id == section
	if _panel != null and _panel.visible:
		_fit_panel()


# Los tipos de habitación de una etapa no alcanzada quedan deshabilitados.
func _refresh_room_locks() -> void:
	for type_id: String in RoomCatalog.get_type_ids():
		var button: Button = _tool_buttons[type_id]
		var unlocked: bool = Company.is_room_unlocked(type_id)
		button.disabled = not unlocked
		button.tooltip_text = Company.room_lock_reason(type_id)
		if not unlocked and _selected == type_id:
			select_tool(BuildController.TOOL_WALL)


func _on_shop_open_changed(open: bool) -> void:
	_panel.visible = _active and not open
	if _panel.visible:
		_fit_panel()


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


# La bandeja va abajo a todo el ancho (menos los márgenes); de alto deja libre arriba el dinero y el
# reloj (UiLayout.top_space): si el contenido no entra, se desplaza.
func _fit_panel() -> void:
	var view: Vector2 = _panel.get_viewport_rect().size
	var width: float = view.x - UiLayout.MARGIN * 2.0
	_panel.custom_minimum_size.x = width
	var shown: Control = _section_views[_section]
	var wanted: float = INVENTORY_CARD_SIZE.y + 16.0
	if shown is HFlowContainer:
		wanted = _flow_height(shown as HFlowContainer, width - 32.0) + 8.0
	_content_scroll.custom_minimum_size.y = 0.0
	var other: float = _panel.get_combined_minimum_size().y - _content_scroll.get_combined_minimum_size().y
	var available: float = view.y - UiLayout.top_space - MARGIN_BOTTOM - other
	_content_scroll.custom_minimum_size.y = clampf(wanted, 40.0, maxf(available, 40.0))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top -= MARGIN_BOTTOM
	_panel.offset_bottom -= MARGIN_BOTTOM


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
