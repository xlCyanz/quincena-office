# Foto de carné de un empleado: cabeza y hombros de su personaje (con su paleta) sobre el color de su área.
class_name EmployeePortrait
extends Control

## Color de fondo por cargo (el del área: programación, diseño, QA, ventas, liderazgo y servicios).
const ROLE_COLORS: Dictionary[String, Color] = {
	"programmer": Color("6fa3ef"), "designer": Color("c38be3"), "qa": Color("7bd389"), "salesperson": Color("f2a541"),
	"team_leader": Color("f2c66d"), "manager": Color("f2c66d"), "executive": Color("f2c66d"),
	"accountant": Color("5bc0be"), "receptionist": Color("9c98ae"), "cleaner": Color("9c98ae"),
}
const DEFAULT_COLOR := Color("9c98ae")
const BORDER_COLOR := UiTheme.OUTLINE
const BORDER: float = 2.0
## Franja más oscura abajo del fondo, como el bisel de los paneles.
const SHADE: float = 0.22

var _look: String = ""
var _color: Color = DEFAULT_COLOR
var _portrait: Dictionary = {}
# Las paletas cambian colores exactos: el fondo y el borde van en otro nodo sin el material.
var _backdrop: Control


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = Control.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.show_behind_parent = true
	_backdrop.use_parent_material = false
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop)


## Muestra la foto de un empleado de Staff.employees.
func set_employee(employee: Dictionary) -> void:
	set_look(Employee.look_for(employee), ROLE_COLORS.get(String(employee["role"]), DEFAULT_COLOR))


func set_look(look: String, color: Color = DEFAULT_COLOR) -> void:
	_look = look
	_color = color
	_portrait = SpriteLibrary.get_portrait(look)
	material = _portrait.get("material", null)
	queue_redraw()
	_backdrop.queue_redraw()


func get_look() -> String:
	return _look


## Indica si hay dibujo (el aspecto tiene hoja).
func has_photo() -> bool:
	return not _portrait.is_empty()


func _draw_backdrop() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_backdrop.draw_rect(rect, _color)
	_backdrop.draw_rect(Rect2(0.0, size.y * (1.0 - SHADE), size.x, size.y * SHADE), Color(0, 0, 0, 0.18))


func _draw() -> void:
	if not _portrait.is_empty():
		draw_texture_rect_region(_portrait["texture"], Rect2(Vector2.ZERO, size), _portrait["source"])
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, BORDER)
