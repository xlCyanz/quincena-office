# Ventana del préstamo de emergencia: el día de nómina sin dinero, si el banco presta.
# Muestra monto, tasa, cuota y total con Aceptar y Rechazar; la escena de juego pausa mientras tanto.
class_name EmergencyLoanDialog
extends CanvasLayer

## Se respondió la oferta (Bank ya la resolvió).
signal closed

const LAYER: int = 15
const PANEL_WIDTH: float = 520.0
const TITLE_FONT_SIZE: int = 26
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.55)

var _cover: ColorRect
var _title: Label
var _body: Label
var _terms: Label
var _accept_button: Button
var _reject_button: Button


func _ready() -> void:
	layer = LAYER
	_cover = ColorRect.new()
	_cover.color = DIM_COLOR
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(center)
	var panel: PanelContainer = Hud.make_panel()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	_title = Label.new()
	_title.text = "Préstamo de emergencia"
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_body)
	_terms = Label.new()
	_terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_terms)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	rows.add_child(buttons)
	_reject_button = _make_button("Rechazar", buttons)
	_reject_button.pressed.connect(func() -> void:
		Bank.reject_emergency()
		_close())
	_accept_button = _make_button("Aceptar", buttons)
	_accept_button.pressed.connect(func() -> void:
		Bank.accept_emergency()
		_close())
	_cover.visible = false


func _make_button(text: String, parent: Container) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, Hud.MENU_BUTTON_SIZE.y)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


## Abre la ventana con la oferta de Bank.emergency_offer.
func show_offer(offer: Dictionary) -> void:
	var months: int = int(offer["months"])
	_body.text = "No alcanza el dinero para la nómina: faltan %s. El banco te ofrece un préstamo rápido para pagarla hoy." % (
		MoneyFormat.format(int(offer["shortfall"])))
	_terms.text = "\n".join([
		"Monto: %s" % MoneyFormat.format(int(offer["amount"])),
		"Interés: %s %% al mes · %d meses" % [String.num(float(offer["rate"]) * 100.0, 1).trim_suffix(".0"), months],
		"Cuota: %s desde el %s" % [MoneyFormat.format(int(offer["installment"])), Bank.describe_day(int(offer["first_due_day"]))],
		"Total a pagar: %s" % MoneyFormat.format(int(offer["total"])),
		"",
		"Si lo rechazas, la nómina queda debida: baja el ánimo de todos y cuenta como atraso.",
	])
	_cover.visible = true


func is_open() -> bool:
	return _cover.visible


func get_text() -> String:
	return "\n".join([_title.text, _body.text, _terms.text])


func get_accept_button() -> Button:
	return _accept_button


func get_reject_button() -> Button:
	return _reject_button


func _close() -> void:
	_cover.visible = false
	closed.emit()
