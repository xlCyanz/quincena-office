# Tema «Oficina de noche»: paleta, fuentes y cajas con bisel de toda la interfaz. Se arma en código
# y se mezcla en el tema por defecto de Godot (apply), así lo toman también los nodos bajo un
# CanvasLayer, que no heredan el tema de la ventana.
class_name UiTheme
extends RefCounted

# Paleta.
const BG := Color("1b1d2a")
const PANEL := Color("262a3b")
const CARD := Color("22263a")
const HEADER := Color("1f2232")
const BUTTON := Color("30354a")
const BUTTON_HOVER := Color("3a4058")
const BUTTON_DISABLED := Color("2a2e40")
const OUTLINE := Color("0f1018")
const TEXT := Color("f3efe6")
const SOFT := Color("c9c5d6")
const MUTED := Color("b4b0c2")
const FAINT := Color("8f8ba3")
const DISABLED_TEXT := Color("6e6a80")
const ACCENT := Color("f2a541")
const ACCENT_HOVER := Color("ffb95c")
const POSITIVE := Color("7bd389")
const NEGATIVE := Color("e5645c")
const INFO := Color("6fa3ef")
const SELECTED := Color("3a3420")
## Tarjeta que se pulsa: bajo el ratón y elegida.
const CARD_HOVER := Color("282c40")
const CARD_SELECTED := Color("2e2d25")
const ALERT_BG := Color("2e2026")
## Fondo de las tarjetas que flotan sobre la oficina (HUD y paneles laterales).
const FLOAT_BG := Color(0.106, 0.114, 0.165, 0.95)
## Velo sobre la oficina detrás de un diálogo.
const DIM := Color(0.047, 0.051, 0.086, 0.66)

const BODY_FONT_PATH: String = "res://assets/fonts/nunito.ttf"
const PIXEL_FONT_PATH: String = "res://assets/fonts/pixelify_sans.ttf"
const BODY_WEIGHT: int = 600
const STRONG_WEIGHT: int = 800
const PIXEL_WEIGHT: int = 500
const TITLE_WEIGHT: int = 700

const FONT_SIZE: int = 16
const BUTTON_FONT_SIZE: int = 18
const BAR_FONT_SIZE: int = 15
## Alto desde arriba del icono de un botón de la barra y lugar que le deja al texto.
const BAR_ICON_TOP: float = 7.0
const BAR_TEXT_TOP: float = 33.0
const TITLE_FONT_SIZE: int = 56
const HEADER_FONT_SIZE: int = 26
const SECTION_FONT_SIZE: int = 18
const MONEY_FONT_SIZE: int = 28
const CAPTION_FONT_SIZE: int = 13

## Borde oscuro, línea clara de arriba y franja oscura de abajo del bisel (en px).
const BORDER: int = 2
const LIGHT_LINE: int = 2
const DARK_BAND: int = 4
## Sombra que cae debajo de los paneles.
const SHADOW: int = 4
const LIGHT_AMOUNT: float = 0.10
const PANEL_LIGHT_AMOUNT: float = 0.08
const DARK_AMOUNT: float = 0.35
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.3)

static var _body_font: FontVariation
static var _strong_font: FontVariation
static var _pixel_font: FontVariation
static var _title_font: FontVariation


## Mezcla el tema en el de Godot. Se llama una vez al arrancar (Settings).
static func apply() -> void:
	var theme: Theme = build()
	var target: Theme = ThemeDB.get_default_theme()
	target.merge_with(theme)
	target.default_font = theme.default_font
	target.default_font_size = theme.default_font_size


## Fuente del texto corrido (Nunito).
static func body_font() -> Font:
	if _body_font == null:
		_body_font = _variation(BODY_FONT_PATH, BODY_WEIGHT)
	return _body_font


## Nunito en negrita, para cifras y nombres destacados.
static func strong_font() -> Font:
	if _strong_font == null:
		_strong_font = _variation(BODY_FONT_PATH, STRONG_WEIGHT)
	return _strong_font


## Fuente pixelada de botones, pestañas y cifras grandes (Pixelify Sans).
static func pixel_font() -> Font:
	if _pixel_font == null:
		_pixel_font = _variation(PIXEL_FONT_PATH, PIXEL_WEIGHT)
	return _pixel_font


## Pixelify en negrita, para títulos.
static func title_font() -> Font:
	if _title_font == null:
		_title_font = _variation(PIXEL_FONT_PATH, TITLE_WEIGHT)
	return _title_font


static func _variation(path: String, weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = load(path) as Font
	var server: TextServer = TextServerManager.get_primary_interface()
	font.variation_opentype = {server.name_to_tag("wght"): weight}
	# Pixelify no trae «fi» ni «fl»: sin ligaduras «oficina» pierde la i.
	font.opentype_features = {server.name_to_tag("liga"): 0}
	return font


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = FONT_SIZE
	_add_labels(theme)
	_add_panels(theme)
	_add_buttons(theme)
	_add_tabs(theme)
	_add_inputs(theme)
	_add_bars(theme)
	return theme


static func _add_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font("bold_font", "RichTextLabel", strong_font())
	_label_variation(theme, "TitleLabel", title_font(), TITLE_FONT_SIZE, TEXT)
	theme.set_color("font_shadow_color", "TitleLabel", OUTLINE)
	theme.set_constant("shadow_offset_x", "TitleLabel", 0)
	theme.set_constant("shadow_offset_y", "TitleLabel", 4)
	_label_variation(theme, "HeaderLabel", title_font(), HEADER_FONT_SIZE, TEXT)
	theme.set_color("font_shadow_color", "HeaderLabel", OUTLINE)
	theme.set_constant("shadow_offset_x", "HeaderLabel", 0)
	theme.set_constant("shadow_offset_y", "HeaderLabel", 3)
	_label_variation(theme, "MoneyLabel", pixel_font(), MONEY_FONT_SIZE, TEXT)
	_label_variation(theme, "SectionLabel", pixel_font(), SECTION_FONT_SIZE, TEXT)
	_label_variation(theme, "CaptionLabel", pixel_font(), CAPTION_FONT_SIZE, MUTED)
	_label_variation(theme, "MutedLabel", body_font(), 14, SOFT)
	_label_variation(theme, "StrongLabel", strong_font(), FONT_SIZE, TEXT)


static func _label_variation(theme: Theme, name: String, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)


static func _add_panels(theme: Theme) -> void:
	var floating: StyleBoxTexture = panel_box(FLOAT_BG, true)
	theme.set_stylebox("panel", "PanelContainer", floating)
	theme.set_stylebox("panel", "Panel", floating)
	theme.set_stylebox("panel", "TooltipPanel", panel_box(BG, false, 8.0))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_type_variation("DialogPanel", "PanelContainer")
	theme.set_stylebox("panel", "DialogPanel", panel_box(PANEL, true, 18.0))
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", flat_box(CARD, 12.0))
	theme.set_type_variation("AlertPanel", "PanelContainer")
	theme.set_stylebox("panel", "AlertPanel", flat_box(ALERT_BG, 12.0))
	theme.set_type_variation("HeaderPanel", "PanelContainer")
	theme.set_stylebox("panel", "HeaderPanel", flat_box(BUTTON, 16.0))
	theme.set_type_variation("SidebarPanel", "PanelContainer")
	var sidebar := StyleBoxFlat.new()
	sidebar.bg_color = Color(BG, 0.94)
	sidebar.border_color = OUTLINE
	sidebar.border_width_right = BORDER
	theme.set_stylebox("panel", "SidebarPanel", sidebar)
	theme.set_stylebox("panel", "PopupMenu", panel_box(BG, false, 6.0))
	theme.set_stylebox("panel", "PopupPanel", panel_box(BG, false, 6.0))
	theme.set_stylebox("hover", "PopupMenu", flat_fill(BUTTON_HOVER))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", DISABLED_TEXT)
	var line := StyleBoxLine.new()
	line.color = OUTLINE
	line.thickness = BORDER
	theme.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = OUTLINE
	vline.thickness = BORDER
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)


static func _add_buttons(theme: Theme) -> void:
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_font("font", type, pixel_font())
		theme.set_font_size("font_size", type, BUTTON_FONT_SIZE)
		theme.set_stylebox("normal", type, button_box(BUTTON))
		theme.set_stylebox("hover", type, button_box(BUTTON_HOVER))
		theme.set_stylebox("pressed", type, button_box(ACCENT))
		theme.set_stylebox("hover_pressed", type, button_box(ACCENT_HOVER))
		theme.set_stylebox("disabled", type, button_box(BUTTON_DISABLED))
		theme.set_stylebox("focus", type, focus_box())
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, TEXT)
		theme.set_color("font_pressed_color", type, BG)
		theme.set_color("font_hover_pressed_color", type, BG)
		theme.set_color("font_disabled_color", type, DISABLED_TEXT)
		theme.set_color("icon_normal_color", type, TEXT)
		theme.set_color("icon_pressed_color", type, BG)
		theme.set_color("icon_hover_color", type, Color.WHITE)
		theme.set_color("icon_hover_pressed_color", type, BG)
		theme.set_color("icon_focus_color", type, TEXT)
		theme.set_color("icon_disabled_color", type, DISABLED_TEXT)
		theme.set_constant("h_separation", type, 8)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", button_box(ACCENT))
	theme.set_stylebox("hover", "PrimaryButton", button_box(ACCENT_HOVER))
	theme.set_stylebox("pressed", "PrimaryButton", button_box(ACCENT_HOVER))
	theme.set_color("font_color", "PrimaryButton", BG)
	theme.set_color("font_hover_color", "PrimaryButton", BG)
	theme.set_color("font_focus_color", "PrimaryButton", BG)
	theme.set_type_variation("DangerButton", "Button")
	theme.set_color("font_color", "DangerButton", NEGATIVE)
	theme.set_color("font_hover_color", "DangerButton", Color("ff8a80"))
	theme.set_color("font_focus_color", "DangerButton", NEGATIVE)
	theme.set_type_variation("BarButton", "Button")
	theme.set_font_size("font_size", "BarButton", BAR_FONT_SIZE)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBoxTexture = theme.get_stylebox(state, "Button").duplicate() as StyleBoxTexture
		box.content_margin_left = 10.0
		box.content_margin_right = 10.0
		box.content_margin_top = BAR_TEXT_TOP
		theme.set_stylebox(state, "BarButton", box)
	theme.set_type_variation("PrimaryBarButton", "BarButton")
	for state: String in ["normal", "hover", "pressed"]:
		var accent: StyleBoxTexture = theme.get_stylebox(state, "PrimaryButton").duplicate() as StyleBoxTexture
		accent.content_margin_left = 10.0
		accent.content_margin_right = 10.0
		accent.content_margin_top = BAR_TEXT_TOP
		theme.set_stylebox(state, "PrimaryBarButton", accent)
	for color: String in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(color, "PrimaryBarButton", BG)
	# Velocidades del reloj: angostas.
	theme.set_type_variation("SpeedButton", "Button")
	theme.set_font_size("font_size", "SpeedButton", 16)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var speed: StyleBoxTexture = theme.get_stylebox(state, "Button").duplicate() as StyleBoxTexture
		speed.content_margin_left = 6.0
		speed.content_margin_right = 6.0
		theme.set_stylebox(state, "SpeedButton", speed)
	theme.set_type_variation("QuietButton", "Button")
	theme.set_color("font_color", "QuietButton", MUTED)
	theme.set_color("font_focus_color", "QuietButton", MUTED)
	# Tarjeta que se pulsa (empleados en Personal): el contenido va dentro como nodos; la elegida lleva borde de acento.
	theme.set_type_variation("CardButton", "Button")
	theme.set_stylebox("normal", "CardButton", panel_box(CARD, false, 0.0))
	theme.set_stylebox("hover", "CardButton", panel_box(CARD_HOVER, false, 0.0))
	theme.set_stylebox("disabled", "CardButton", panel_box(CARD, false, 0.0))
	var chosen := StyleBoxFlat.new()
	chosen.bg_color = CARD_SELECTED
	chosen.border_color = ACCENT
	chosen.set_border_width_all(BORDER)
	for state: String in ["pressed", "hover_pressed"]:
		theme.set_stylebox(state, "CardButton", chosen)
	# Casillas: texto normal y sin caja.
	for type: String in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(4.0)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			theme.set_stylebox(state, type, empty)
		theme.set_stylebox("focus", type, focus_box())
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, TEXT)
		theme.set_color("font_hover_pressed_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, TEXT)
		theme.set_color("font_disabled_color", type, DISABLED_TEXT)
		for checked: bool in [true, false]:
			var prefix: String = "checked" if checked else "unchecked"
			theme.set_icon(prefix, type, check_icon(checked, true))
			theme.set_icon(prefix + "_disabled", type, check_icon(checked, false))
			theme.set_icon("radio_" + prefix, type, check_icon(checked, true))
			theme.set_icon("radio_" + prefix + "_disabled", type, check_icon(checked, false))
	theme.set_color("font_color", "LinkButton", ACCENT)
	theme.set_color("font_hover_color", "LinkButton", Color("ffd08a"))


static func _add_tabs(theme: Theme) -> void:
	for type: String in ["TabContainer", "TabBar"]:
		theme.set_font("font", type, pixel_font())
		theme.set_font_size("font_size", type, BUTTON_FONT_SIZE)
		theme.set_stylebox("tab_selected", type, tab_box(PANEL, true))
		theme.set_stylebox("tab_unselected", type, tab_box(CARD, false))
		theme.set_stylebox("tab_hovered", type, tab_box(BUTTON, false))
		theme.set_stylebox("tab_disabled", type, tab_box(BUTTON_DISABLED, false))
		theme.set_stylebox("tab_focus", type, focus_box())
		theme.set_color("font_selected_color", type, ACCENT)
		theme.set_color("font_unselected_color", type, SOFT)
		theme.set_color("font_hovered_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, DISABLED_TEXT)
		theme.set_constant("tab_separation", type, 4)
	theme.set_stylebox("panel", "TabContainer", panel_box(PANEL, false, 12.0))
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())


static func _add_inputs(theme: Theme) -> void:
	var field: StyleBoxFlat = flat_box(BG, 8.0)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", focus_box())
	theme.set_stylebox("read_only", "LineEdit", flat_box(CARD, 8.0))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", FAINT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	theme.set_stylebox("normal", "TextEdit", field)
	theme.set_stylebox("focus", "TextEdit", focus_box())
	theme.set_color("font_color", "TextEdit", TEXT)
	theme.set_stylebox("panel", "ItemList", flat_box(CARD, 6.0))
	theme.set_stylebox("selected", "ItemList", flat_fill(SELECTED))
	theme.set_stylebox("selected_focus", "ItemList", flat_fill(SELECTED))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", ACCENT)
	theme.set_stylebox("slider", "HSlider", _meter_back())
	theme.set_stylebox("grabber_area", "HSlider", flat_fill(ACCENT))
	theme.set_stylebox("grabber_area_highlight", "HSlider", flat_fill(ACCENT_HOVER))


static func _add_bars(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _meter_back())
	theme.set_stylebox("fill", "ProgressBar", flat_fill(ACCENT))
	theme.set_color("font_color", "ProgressBar", TEXT)
	theme.set_font_size("font_size", "ProgressBar", CAPTION_FONT_SIZE)
	for type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, flat_fill(Color(OUTLINE, 0.6)))
		theme.set_stylebox("grabber", type, flat_fill(BUTTON_HOVER))
		theme.set_stylebox("grabber_highlight", type, flat_fill(Color("4a5070")))
		theme.set_stylebox("grabber_pressed", type, flat_fill(ACCENT))


static func _meter_back() -> StyleBoxFlat:
	var back: StyleBoxFlat = flat_fill(OUTLINE)
	back.content_margin_top = 4.0
	back.content_margin_bottom = 4.0
	return back


## Relleno liso sin borde.
static func flat_fill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


## Caja lisa con borde oscuro (tarjetas dentro de un panel).
static func flat_box(color: Color, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = OUTLINE
	box.set_border_width_all(BORDER)
	box.set_content_margin_all(padding)
	return box


## Barra de progreso del color dado (ánimo, energía, avance).
static func meter_fill(color: Color) -> StyleBoxFlat:
	return flat_fill(color)


## Casilla de 20 px: borde oscuro y, marcada, un cuadro de acento adentro.
static func check_icon(checked: bool, enabled: bool) -> ImageTexture:
	var size: int = 20
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(OUTLINE)
	image.fill_rect(Rect2i(BORDER, BORDER, size - BORDER * 2, size - BORDER * 2), BUTTON if enabled else BUTTON_DISABLED)
	image.fill_rect(Rect2i(BORDER, BORDER, size - BORDER * 2, LIGHT_LINE / 2), (BUTTON if enabled else BUTTON_DISABLED).lerp(Color.WHITE, LIGHT_AMOUNT))
	if checked:
		var inset: int = 5
		image.fill_rect(Rect2i(inset, inset, size - inset * 2, size - inset * 2), ACCENT if enabled else DISABLED_TEXT)
	return ImageTexture.create_from_image(image)


static func focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = ACCENT
	box.set_border_width_all(BORDER)
	box.set_expand_margin_all(2.0)
	return box


## Botón con bisel: borde oscuro, línea clara arriba y franja oscura abajo.
static func button_box(color: Color) -> StyleBoxTexture:
	var box: StyleBoxTexture = _bevel(color, LIGHT_AMOUNT, DARK_BAND, 0)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 8.0
	return box


## Panel con bisel; con shadow deja caer una sombra corta debajo.
static func panel_box(color: Color, shadow: bool, padding: float = 12.0) -> StyleBoxTexture:
	var box: StyleBoxTexture = _bevel(color, PANEL_LIGHT_AMOUNT, 0, SHADOW if shadow else 0)
	box.set_content_margin_all(padding)
	return box


## Pestaña: borde oscuro sin el de abajo (se une al panel); la elegida lleva una raya de acento arriba.
static func tab_box(color: Color, selected: bool) -> StyleBoxTexture:
	var accent: int = 3 if selected else 0
	var width: int = BORDER * 2 + 4
	var height: int = BORDER + accent + 4
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for y: int in range(height):
		for x: int in range(width):
			if x < BORDER or x >= width - BORDER or y < BORDER:
				image.set_pixel(x, y, OUTLINE)
			elif y < BORDER + accent:
				image.set_pixel(x, y, ACCENT)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left = BORDER
	box.texture_margin_right = BORDER
	box.texture_margin_top = BORDER + accent
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


# Arma la caja desde una imagen chica estirada en nueve partes: borde de BORDER px, línea clara
# arriba, franja oscura abajo (dark) y sombra que sobresale debajo (shadow).
static func _bevel(color: Color, light: float, dark: int, shadow: int) -> StyleBoxTexture:
	var middle: int = 4
	var width: int = BORDER * 2 + middle
	var height: int = BORDER * 2 + LIGHT_LINE + middle + dark + shadow
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var light_color: Color = Color(color.lerp(Color.WHITE, light), color.a)
	var dark_color: Color = Color(color.lerp(Color.BLACK, DARK_AMOUNT), color.a)
	var body_bottom: int = height - shadow
	for y: int in range(height):
		for x: int in range(width):
			var pixel: Color = color
			if y >= body_bottom:
				pixel = SHADOW_COLOR
			elif x < BORDER or x >= width - BORDER or y < BORDER or y >= body_bottom - BORDER:
				pixel = OUTLINE
			elif y < BORDER + LIGHT_LINE:
				pixel = light_color
			elif y >= body_bottom - BORDER - dark:
				pixel = dark_color
			image.set_pixel(x, y, pixel)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left = BORDER
	box.texture_margin_right = BORDER
	box.texture_margin_top = BORDER + LIGHT_LINE
	box.texture_margin_bottom = BORDER + dark + shadow
	box.expand_margin_bottom = shadow
	return box
