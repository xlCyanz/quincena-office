# Botón «?» de ayuda: pide su tema por EventBus.help_requested y HelpDialog lo muestra.
class_name HelpButton
extends RefCounted

const SIZE := Vector2(44.0, 44.0)


## Un botón «?» que abre la ayuda del tema (clave de data/help.json).
static func create(topic: String) -> Button:
	var button := Button.new()
	button.name = "HelpButton"
	button.text = "?"
	button.tooltip_text = "Ayuda"
	button.custom_minimum_size = SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: EventBus.help_requested.emit(topic))
	return button
