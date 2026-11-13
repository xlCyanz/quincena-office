# Interfaz superpuesta mínima (diseño, 12.2): arriba a la izquierda el dinero y arriba
# a la derecha el reloj, con la fecha, la cuenta atrás de la próxima nómina (o lo que
# se debe de ella), la pausa y las velocidades. Arriba al centro aparecen unos segundos
# los avisos de EventBus.notice, sin tapar el dinero ni el reloj (un texto largo se parte
# en líneas). El botón Construir está en BuildPanel, abajo al centro. Se construye
# en código; los botones avisan con señales y la escena de juego decide qué hacer.
class_name Hud
extends CanvasLayer

## Se pulsó el botón de pausa.
signal pause_pressed
## Se eligió una velocidad (índice en GameConstants.CLOCK_SPEEDS).
signal speed_pressed(index: int)
## Se hizo clic en un aviso que lleva a algo (hito 57): el destino de EventBus.send_notice.
signal notice_clicked(target: Dictionary)

const MARGIN: float = 12.0
const WEEKDAY_NAMES: Array[String] = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
const NEGATIVE_COLOR := Color(1.0, 0.45, 0.4)
const REPUTATION_COLOR := Color(1.0, 0.82, 0.35)
const VALUE_COLOR := Color(0.6, 0.85, 1.0)
const MONEY_FONT_SIZE: int = 24
const PANEL_COLOR := Color(0.12, 0.12, 0.14, 0.88)
const PANEL_PADDING: float = 8.0
const PANEL_RADIUS: int = 6
## Segundos reales que se ve un aviso.
const NOTICE_SECONDS: float = 6.0
## Color del texto de un aviso al que se le puede hacer clic, y lo que se le agrega.
const LINK_COLOR := Color(0.65, 0.88, 1.0)
const LINK_SUFFIX: String = "  ›"
## Tamaño de los botones de la barra de menús de abajo (caben nueve en 1280 px).
const MENU_BUTTON_SIZE := Vector2(124.0, 44.0)

var _balance_label: Label
var _reputation_label: Label
var _value_label: Label
var _date_label: Label
var _time_label: Label
var _payroll_label: Label
var _pause_button: Button
var _speed_buttons: Array[Button] = []
var _controls_enabled: bool = true
var _notice_panel: PanelContainer
var _notice_label: Label
var _notice_timer: Timer
var _notice_target: Dictionary = {}
var _money_panel: PanelContainer
var _clock_panel: PanelContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dinero, arriba a la izquierda.
	var money_panel: PanelContainer = make_panel()
	_money_panel = money_panel
	root.add_child(money_panel)
	money_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	var money_rows := VBoxContainer.new()
	money_panel.add_child(money_rows)
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 16)
	money_rows.add_child(money_row)
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", MONEY_FONT_SIZE)
	money_row.add_child(_balance_label)
	# Reputación (diseño 12.2: estado de la empresa arriba a la izquierda).
	_reputation_label = Label.new()
	_reputation_label.add_theme_font_size_override("font_size", MONEY_FONT_SIZE)
	_reputation_label.add_theme_color_override("font_color", REPUTATION_COLOR)
	_reputation_label.tooltip_text = "Reputación de la empresa"
	_reputation_label.mouse_filter = Control.MOUSE_FILTER_PASS
	money_row.add_child(_reputation_label)
	# Valor de la empresa (hito 26), en una segunda línea para no ensanchar la esquina.
	_value_label = Label.new()
	_value_label.tooltip_text = "Valor de la empresa: dinero + reventa de los muebles + terreno − deuda con el banco"
	_value_label.mouse_filter = Control.MOUSE_FILTER_PASS
	money_rows.add_child(_value_label)

	# Reloj, arriba a la derecha.
	var clock_panel: PanelContainer = make_panel()
	root.add_child(clock_panel)
	var clock_rows := VBoxContainer.new()
	clock_panel.add_child(clock_rows)
	var time_row := HBoxContainer.new()
	clock_rows.add_child(time_row)
	_date_label = Label.new()
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(_date_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", MONEY_FONT_SIZE)
	time_row.add_child(_time_label)
	_payroll_label = Label.new()
	clock_rows.add_child(_payroll_label)
	_payroll_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	var speed_row := HBoxContainer.new()
	clock_rows.add_child(speed_row)
	_pause_button = _add_toggle(speed_row, "Pausa")
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	for index: int in range(GameConstants.CLOCK_SPEEDS.size()):
		var button: Button = _add_toggle(speed_row, "%dx" % int(GameConstants.CLOCK_SPEEDS[index]))
		button.pressed.connect(func() -> void: speed_pressed.emit(index))
		_speed_buttons.append(button)
	clock_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	clock_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock_panel = clock_panel

	# Avisos, arriba al centro.
	_notice_panel = make_panel()
	root.add_child(_notice_panel)
	_notice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_notice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice_label = Label.new()
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_panel.add_child(_notice_label)
	_notice_panel.visible = false
	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.ignore_time_scale = true
	_notice_timer.timeout.connect(func() -> void: _notice_panel.visible = false)
	add_child(_notice_timer)
	EventBus.notice.connect(func(text: String) -> void: show_notice(text, EventBus.get_notice_target()))
	_notice_panel.gui_input.connect(_on_notice_input)
	get_viewport().size_changed.connect(_fit_notice)
	_notice_panel.minimum_size_changed.connect(_place_notice)

	EventBus.balance_changed.connect(_on_balance_changed)
	EventBus.projects_changed.connect(_update_reputation)
	_update_reputation()
	EventBus.company_value_changed.connect(_update_value)
	_update_value(Company.get_value())
	_on_balance_changed(Economy.balance)
	_update_clock()


func _process(_delta: float) -> void:
	# El reloj no avisa de cada minuto ni de los cambios de velocidad: se lee cada fotograma.
	_update_clock()


## Activa o desactiva la pausa y las velocidades (en modo construcción el tiempo queda
## en pausa).
func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	_update_clock()


func get_pause_button() -> Button:
	return _pause_button


func get_speed_button(index: int) -> Button:
	return _speed_buttons[index]


## Estrellas de reputación que se muestran arriba a la izquierda.
func get_reputation_text() -> String:
	return _reputation_label.text


## Texto del valor de la empresa.
func get_value_text() -> String:
	return _value_label.text


# Se lee el valor actual y no el de la señal: una recompensa pagada mientras se avisaba
# un cambio (hito 28) emite otro aviso adentro, y el de afuera llega después con el viejo.
func _update_value(_value: int = 0) -> void:
	var value: int = Company.get_value()
	_value_label.text = "Valor %s" % MoneyFormat.format(value)
	_value_label.add_theme_color_override("font_color", NEGATIVE_COLOR if value < 0 else VALUE_COLOR)


func _update_reputation() -> void:
	_reputation_label.text = ProjectsPanel.describe_reputation(Projects.reputation)


func get_balance_text() -> String:
	return _balance_label.text


## Muestra un aviso arriba al centro durante NOTICE_SECONDS (reemplaza al anterior).
## Con target (EventBus.target_*) el aviso se ve como enlace y un clic avisa notice_clicked.
func show_notice(text: String, target: Dictionary = {}) -> void:
	_notice_target = target.duplicate()
	_notice_label.text = text + (LINK_SUFFIX if not target.is_empty() else "")
	if target.is_empty():
		_notice_label.remove_theme_color_override("font_color")
	else:
		_notice_label.add_theme_color_override("font_color", LINK_COLOR)
	_notice_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not target.is_empty() else Control.CURSOR_ARROW
	_notice_panel.visible = true
	_fit_notice()
	_notice_timer.start(NOTICE_SECONDS)


## Destino del aviso visible ({} si no lleva a nada o no hay aviso).
func get_notice_target() -> Dictionary:
	return _notice_target if _notice_panel.visible else {}


## Hace lo mismo que un clic en el aviso: si lleva a algo, lo cierra y avisa notice_clicked.
func click_notice() -> void:
	if not _notice_panel.visible or _notice_target.is_empty():
		return
	var target: Dictionary = _notice_target
	_notice_panel.visible = false
	_notice_timer.stop()
	notice_clicked.emit(target)


func _on_notice_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		click_notice()
		_notice_panel.accept_event()


## Rectángulo del aviso en pantalla (para las pruebas).
func get_notice_rect() -> Rect2:
	return _notice_panel.get_global_rect()


## Rectángulos del dinero y del reloj (para las pruebas).
func get_corner_rects() -> Array[Rect2]:
	return [_money_panel.get_global_rect(), _clock_panel.get_global_rect()]


# Ubica el aviso entre el dinero y el reloj, partiendo el texto en líneas si hace falta.
# (Con stretch "expand" el ancho lógico nunca baja de 1280, así que siempre hay lugar.)
func _fit_notice() -> void:
	if _notice_panel == null or not _notice_panel.visible:
		return
	var view: Vector2 = _notice_panel.get_viewport_rect().size
	var side: float = maxf(_money_panel.get_combined_minimum_size().x, _clock_panel.get_combined_minimum_size().x) + MARGIN * 2.0
	var padding: float = PANEL_PADDING * 2.0
	var available: float = view.x - side * 2.0 - padding
	var font: Font = _notice_label.get_theme_font("font")
	var natural: float = font.get_string_size(_notice_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_notice_label.get_theme_font_size("font_size")).x + 2.0
	var width: float = minf(natural, available)
	_notice_label.custom_minimum_size.x = width
	_place_notice()


# Achica el aviso a lo justo y lo centra. Con ajuste de línea el alto se conoce recién
# cuando el texto se acomoda al ancho, así que se repite al cambiar el mínimo del panel.
func _place_notice() -> void:
	if not _notice_panel.visible:
		return
	var view: Vector2 = _notice_panel.get_viewport_rect().size
	_notice_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_notice_panel.size = _notice_panel.get_combined_minimum_size()
	_notice_panel.position = Vector2(roundf((view.x - _notice_panel.size.x) / 2.0), MARGIN)


## Texto del aviso visible, o "" si no hay.
func get_notice_text() -> String:
	return _notice_label.text.trim_suffix(LINK_SUFFIX) if _notice_panel.visible else ""


func get_clock_text() -> String:
	return "%s %s · %s" % [_date_label.text, _time_label.text, _payroll_label.text]


## Días que faltan para la próxima nómina contando desde day (0 si es hoy).
static func days_until_payroll(day: int) -> int:
	for payroll_day: int in GameConstants.PAYROLL_DAYS:
		if payroll_day >= day:
			return payroll_day - day
	return GameConstants.DAYS_PER_MONTH - day + GameConstants.PAYROLL_DAYS[0]


func _update_clock() -> void:
	_date_label.text = "%s %d · Mes %d" % [WEEKDAY_NAMES[GameClock.get_weekday()], GameClock.get_day(),
		GameClock.get_month()]
	_time_label.text = "%02d:%02d" % [GameClock.get_hour(), GameClock.get_minute()]
	var days: int = days_until_payroll(GameClock.get_day())
	var owed: int = Staff.get_total_owed()
	_payroll_label.add_theme_color_override("font_color", NEGATIVE_COLOR if owed > 0 else Color(1.0, 1.0, 1.0, 0.75))
	if owed > 0:
		_payroll_label.text = "Nómina pendiente: %s" % MoneyFormat.format(owed)
	elif days == 0:
		_payroll_label.text = "Nómina: hoy"
	elif days == 1:
		_payroll_label.text = "Nómina: mañana"
	else:
		_payroll_label.text = "Nómina en %d días" % days
	_pause_button.set_pressed_no_signal(GameClock.is_paused)
	_pause_button.disabled = not _controls_enabled
	for index: int in range(_speed_buttons.size()):
		_speed_buttons[index].set_pressed_no_signal(not GameClock.is_paused and GameClock.speed_index == index)
		_speed_buttons[index].disabled = not _controls_enabled


## Panel semitransparente con margen interior y esquinas redondeadas (lo usan también
## otros paneles de la interfaz).
static func make_panel() -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(PANEL_RADIUS)
	style.set_content_margin_all(PANEL_PADDING)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_toggle(parent: Container, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(52, 32)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


# Como _update_value: se lee el saldo actual, no el de la señal (puede llegar viejo).
func _on_balance_changed(_balance: int = 0) -> void:
	var balance: int = Economy.balance
	_balance_label.text = MoneyFormat.format(balance)
	if balance < 0:
		_balance_label.add_theme_color_override("font_color", NEGATIVE_COLOR)
	else:
		_balance_label.remove_theme_color_override("font_color")
