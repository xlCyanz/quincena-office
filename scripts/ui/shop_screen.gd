# Tienda de muebles a pantalla completa (se abre desde Construir): tarjetas con la imagen de cada mueble por
# categoría y, a la derecha, la ficha del elegido con cantidad y Comprar. Lo comprado va al inventario.
class_name ShopScreen
extends CanvasLayer

## Se pidió comprar count unidades de un mueble (BuildController.buy lo hace).
signal buy_requested(id: String, count: int)
## Se abrió (true) o se cerró la tienda.
signal open_changed(open: bool)

## Encima del HUD y de la bandeja; debajo del tutorial.
const LAYER: int = 3
const ALL: String = "all"
const CARD_SIZE := Vector2(168.0, 196.0)
const CARD_IMAGE_HEIGHT: float = 124.0
const DETAIL_WIDTH: float = 360.0
const DETAIL_IMAGE_HEIGHT: float = 260.0
const MAX_COUNT: int = 20
const PLACE_TEXT: Dictionary[String, String] = {
	"floor": "Va en el piso", "wall": "Va en la pared", "desk": "Va sobre un escritorio",
}

var _root: Control
var _grid: GridContainer
var _scroll: ScrollContainer
var _money_label: Label
var _category: String = ALL
var _category_buttons: Dictionary[String, Button] = {}
var _cards: Dictionary[String, Button] = {}
var _card_counts: Dictionary[String, Label] = {}
var _card_prices: Dictionary[String, Label] = {}
var _selected: String = ""
var _count: int = 1
var _image: TextureRect
var _category_label: Label
var _name_label: Label
var _info_label: Label
var _stock_label: Label
var _count_label: Label
var _total_label: Label
var _buy_button: Button
var _message_label: Label
var _back_button: Button
var _top_bar: Control


func _ready() -> void:
	layer = LAYER
	_root = PanelContainer.new()
	_root.theme_type_variation = &"DialogPanel"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := StyleBoxFlat.new()
	background.bg_color = UiTheme.BG
	_root.add_theme_stylebox_override("panel", background)
	add_child(_root)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	_root.add_child(rows)
	_top_bar = _build_top_bar()
	rows.add_child(_top_bar)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	rows.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_scroll.add_child(margin)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	margin.add_child(_grid)
	body.add_child(_build_detail())
	for id: String in FurnitureCatalog.get_ids():
		_add_card(id)
	_root.resized.connect(_fit_columns)
	EventBus.balance_changed.connect(func(_balance: int) -> void: _refresh())
	EventBus.inventory_changed.connect(_refresh)
	visible = false
	_select(FurnitureCatalog.get_ids()[0])
	set_category(ALL)


## Abre o cierra la tienda.
func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	_message_label.text = ""
	if open:
		_refresh()
		_fit_columns()
		EventBus.ui_action.emit("shop_opened")
	open_changed.emit(open)


func is_open() -> bool:
	return visible


## Muestra solo los muebles de una categoría (ALL = todos).
func set_category(category: String) -> void:
	_category = category
	for id: String in _category_buttons:
		_category_buttons[id].set_pressed_no_signal(id == category)
	for id: String in _cards:
		_cards[id].visible = category == ALL or FurnitureCatalog.get_category(id) == category


func get_category() -> String:
	return _category


func get_category_button(category: String) -> Button:
	return _category_buttons.get(category)


## Tarjeta de un mueble.
func get_card(id: String) -> Button:
	return _cards.get(id)


## Elige un mueble (su ficha a la derecha).
func select(id: String) -> void:
	_select(id)


func get_selected() -> String:
	return _selected


## Cuántas unidades se van a comprar.
func set_count(count: int) -> void:
	_count = clampi(count, 1, MAX_COUNT)
	_message_label.text = ""
	_refresh()


func get_count() -> int:
	return _count


func get_buy_button() -> Button:
	return _buy_button


func get_back_button() -> Button:
	return _back_button


## Barra de arriba en pantalla (el tutorial se pone debajo mientras la Tienda está abierta).
func get_top_bar_rect() -> Rect2:
	return _top_bar.get_global_rect()


func get_message() -> String:
	return _message_label.text


## Resultado de una compra (Builder.buy): mensaje bajo el botón; si salió bien, vuelve a 1.
func show_result(result: Dictionary) -> void:
	_message_label.text = String(result.get("message", ""))
	_message_label.add_theme_color_override("font_color", UiTheme.POSITIVE if bool(result.get("ok", false)) else UiTheme.NEGATIVE)
	if bool(result.get("ok", false)):
		_count = 1
	_refresh()


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"HeaderPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_back_button = Button.new()
	_back_button.text = "Volver al mapa"
	_back_button.pressed.connect(func() -> void: set_open(false))
	row.add_child(_back_button)
	var title := Label.new()
	title.text = "Tienda"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(title)
	var categories := HFlowContainer.new()
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories.add_theme_constant_override("h_separation", 6)
	categories.add_theme_constant_override("v_separation", 6)
	row.add_child(categories)
	var names: Dictionary = {ALL: "Todos"}
	names.merge(FurnitureCatalog.get_categories())
	for category: String in names:
		var button := Button.new()
		button.text = String(names[category])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_category.bind(category))
		categories.add_child(button)
		_category_buttons[category] = button
	var money := VBoxContainer.new()
	money.add_theme_constant_override("separation", 0)
	row.add_child(money)
	var caption := Label.new()
	caption.text = "Dinero"
	caption.theme_type_variation = &"CaptionLabel"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.add_child(caption)
	_money_label = Label.new()
	_money_label.theme_type_variation = &"StrongLabel"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.add_theme_color_override("font_color", UiTheme.POSITIVE)
	money.add_child(_money_label)
	return bar


func _build_detail() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HeaderPanel"
	panel.custom_minimum_size.x = DETAIL_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"CardPanel"
	frame.custom_minimum_size.y = DETAIL_IMAGE_HEIGHT
	column.add_child(frame)
	_image = _make_image()
	frame.add_child(_image)
	_category_label = Label.new()
	_category_label.theme_type_variation = &"CaptionLabel"
	column.add_child(_category_label)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"HeaderLabel"
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_name_label)
	_info_label = Label.new()
	_info_label.theme_type_variation = &"MutedLabel"
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_info_label)
	_stock_label = Label.new()
	_stock_label.theme_type_variation = &"MutedLabel"
	column.add_child(_stock_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var count_row := HBoxContainer.new()
	column.add_child(count_row)
	var count_caption := Label.new()
	count_caption.text = "Cantidad"
	count_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_caption)
	var less := Button.new()
	less.text = "−"
	less.tooltip_text = "Menos"
	less.custom_minimum_size = Vector2(44.0, 40.0)
	less.pressed.connect(func() -> void: set_count(_count - 1))
	count_row.add_child(less)
	_count_label = Label.new()
	_count_label.theme_type_variation = &"SectionLabel"
	_count_label.custom_minimum_size.x = 44.0
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_row.add_child(_count_label)
	var more := Button.new()
	more.text = "+"
	more.tooltip_text = "Más"
	more.custom_minimum_size = Vector2(44.0, 40.0)
	more.pressed.connect(func() -> void: set_count(_count + 1))
	count_row.add_child(more)
	var total_row := HBoxContainer.new()
	column.add_child(total_row)
	var total_caption := Label.new()
	total_caption.text = "Total"
	total_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_row.add_child(total_caption)
	_total_label = Label.new()
	_total_label.theme_type_variation = &"MoneyLabel"
	total_row.add_child(_total_label)
	_buy_button = Button.new()
	_buy_button.theme_type_variation = &"PrimaryButton"
	_buy_button.custom_minimum_size.y = 52.0
	_buy_button.pressed.connect(func() -> void: buy_requested.emit(_selected, _count))
	column.add_child(_buy_button)
	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.custom_minimum_size.y = 40.0
	column.add_child(_message_label)
	return panel


func _add_card(id: String) -> void:
	var info: Dictionary = FurnitureCatalog.get_item(id)
	var card := Button.new()
	card.theme_type_variation = &"CardButton"
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = String(info["name"])
	card.pressed.connect(_select.bind(id))
	_grid.add_child(card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	var image: TextureRect = _make_image()
	image.texture = SpriteLibrary.get_furniture_icon(id)
	image.custom_minimum_size.y = CARD_IMAGE_HEIGHT
	column.add_child(image)
	var name_label := Label.new()
	name_label.text = String(info["name"])
	name_label.theme_type_variation = &"StrongLabel"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)
	var price := Label.new()
	price.text = MoneyFormat.format(FurnitureCatalog.get_price(id))
	price.theme_type_variation = &"SectionLabel"
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(price)
	var count := Label.new()
	count.theme_type_variation = &"CaptionLabel"
	count.add_theme_color_override("font_color", UiTheme.INFO)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(count)
	_cards[id] = card
	_card_prices[id] = price
	_card_counts[id] = count


func _make_image() -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _select(id: String) -> void:
	_selected = id
	_count = 1
	_message_label.text = ""
	for other: String in _cards:
		_cards[other].set_pressed_no_signal(other == id)
	var info: Dictionary = FurnitureCatalog.get_item(id)
	_image.texture = SpriteLibrary.get_furniture_icon(id)
	_category_label.text = String(FurnitureCatalog.get_categories().get(FurnitureCatalog.get_category(id), "")).to_upper()
	_name_label.text = String(info["name"])
	var parts: Array[String] = [_place_text(id)]
	if not bool(info["on_desk"]) and not bool(info["wall_mounted"]):
		var size: Vector2i = info["size"]
		parts.append("%d×%d m²" % [size.x, size.y])
	if FurnitureCatalog.get_ambiance_points(id) > 0.0:
		parts.append("+%d ambiente" % roundi(FurnitureCatalog.get_ambiance_points(id)))
	if not FurnitureCatalog.get_upgrade(id).is_empty():
		parts.append("se mejora a %s" % FurnitureCatalog.get_item(FurnitureCatalog.get_upgrade(id))["name"])
	_info_label.text = " · ".join(parts) + "."
	_refresh()


func _place_text(id: String) -> String:
	var info: Dictionary = FurnitureCatalog.get_item(id)
	if bool(info["on_desk"]):
		return PLACE_TEXT["desk"]
	return PLACE_TEXT["wall"] if bool(info["wall_mounted"]) else PLACE_TEXT["floor"]


func _refresh() -> void:
	if _buy_button == null:
		return
	_money_label.text = MoneyFormat.format(Economy.balance)
	for id: String in _cards:
		var stock: int = OfficeState.get_stock(id)
		_card_counts[id].text = "Tienes %d" % stock if stock > 0 else ""
		var affordable: bool = Economy.can_afford(FurnitureCatalog.get_price(id))
		_card_prices[id].add_theme_color_override("font_color", UiTheme.ACCENT if affordable else UiTheme.NEGATIVE)
	if _selected.is_empty():
		return
	var total: int = FurnitureCatalog.get_price(_selected) * _count
	var affordable: bool = Economy.can_afford(total)
	_stock_label.text = "En inventario: %d" % OfficeState.get_stock(_selected)
	_count_label.text = str(_count)
	_total_label.text = MoneyFormat.format(total)
	_total_label.add_theme_color_override("font_color", UiTheme.ACCENT if affordable else UiTheme.NEGATIVE)
	_buy_button.disabled = not affordable
	_buy_button.text = "Comprar" if affordable else "Te faltan %s" % MoneyFormat.format(total - Economy.balance)


# Columnas de la cuadrícula según el ancho que deja la ficha.
func _fit_columns() -> void:
	var width: float = _scroll.size.x - 40.0
	if width <= 0.0:
		width = _root.size.x - DETAIL_WIDTH - 40.0
	_grid.columns = maxi(1, floori((width + 12.0) / (CARD_SIZE.x + 12.0)))
