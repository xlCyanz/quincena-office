# Sprites del juego según data/sprites.json (lo escribe tools/sprites/export_game.py): imagen y
# apoyo. Se dibujan a 1/SCALE (miden la mitad en el mundo). Funciones estáticas.
class_name SpriteLibrary
extends RefCounted

const DATA_PATH: String = "res://data/sprites.json"
const FOLDER: String = "res://assets/sprites/"
## Opacidad de las sombras de piso (el sprite de sombra es opaco).
const SHADOW_ALPHA: float = 0.3

static var _data: Dictionary = {}
static var _textures: Dictionary[String, Texture2D] = {}


## Datos de data/sprites.json (se leen una vez).
static func get_data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


## Px de sprite por px del mundo.
static func get_scale() -> float:
	return maxf(float(get_data().get("scale", 2.0)), 1.0)


## Indica si hay un sprite con ese nombre.
static func has_sprite(sprite: String) -> bool:
	var sprites: Dictionary = get_data().get("sprites", {})
	return sprites.has(sprite)


## Textura de un sprite, o null si no existe.
static func get_texture(sprite: String) -> Texture2D:
	if _textures.has(sprite):
		return _textures[sprite]
	var texture: Texture2D = null
	var sprites: Dictionary = get_data().get("sprites", {})
	if sprites.has(sprite):
		var path: String = FOLDER + String(sprites[sprite]["file"])
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
	_textures[sprite] = texture
	return texture


## Rectángulo en px del mundo del sprite con su apoyo en `at`.
static func get_rect(sprite: String, at: Vector2 = Vector2.ZERO) -> Rect2:
	var sprites: Dictionary = get_data().get("sprites", {})
	if not sprites.has(sprite):
		return Rect2()
	var entry: Dictionary = sprites[sprite]
	var anchor := Vector2(float(entry["anchor"][0]), float(entry["anchor"][1]))
	var size := Vector2(float(entry["size"][0]), float(entry["size"][1]))
	return Rect2(at - anchor / get_scale(), size / get_scale())


## Dibuja un sprite con su apoyo en `at`. False si no existe.
static func draw(canvas: CanvasItem, sprite: String, at: Vector2 = Vector2.ZERO, modulate: Color = Color.WHITE) -> bool:
	var texture: Texture2D = get_texture(sprite)
	if texture == null:
		return false
	canvas.draw_texture_rect(texture, get_rect(sprite, at), false, modulate)
	return true


## Sprite de un mueble con su rotación ("" si no tiene). part: "seat"/"back" en sillas, "shadow" la sombra.
static func get_furniture_sprite(item_id: String, rotation: int, part: String = "") -> String:
	var furniture: Dictionary = get_data().get("furniture", {})
	if not furniture.has(item_id):
		return ""
	var entry: Dictionary = furniture[item_id]
	var sprite: String = String(entry["base"])
	if bool(entry.get("parts", false)) and part != "shadow":
		sprite += "_" + (part if not part.is_empty() else "seat")
	if bool(entry.get("rotated", false)):
		sprite += "_r%d" % posmod(rotation, 4)
	if part == "shadow":
		sprite += "_shadow"
	return sprite if has_sprite(sprite) else ""


## Sprite de un objeto de pared en un borde de ese eje; pick elige entre sus dibujos. "" si no tiene.
static func get_wall_item_sprite(item_id: String, axis: int, pick: int = 0) -> String:
	var items: Dictionary = get_data().get("wall_items", {})
	if not items.has(item_id):
		return ""
	var names: Array = items[item_id]["sprites"]
	var sprite: String = "%s_%s" % [names[posmod(pick, names.size())], "x" if axis == GridEdge.AXIS_X else "y"]
	return sprite if has_sprite(sprite) else ""


## Altura sobre el piso (px del mundo) donde empieza el dibujo de un objeto de pared.
static func get_wall_item_base(item_id: String) -> float:
	var items: Dictionary = get_data().get("wall_items", {})
	return float(items[item_id]["base_z"]) / get_scale() if items.has(item_id) else 0.0


## Dibuja un sprite achicado por factor alrededor de su apoyo en `at`.
static func draw_scaled(canvas: CanvasItem, sprite: String, at: Vector2, factor: float) -> bool:
	var texture: Texture2D = get_texture(sprite)
	if texture == null:
		return false
	var rect: Rect2 = get_rect(sprite)
	canvas.draw_texture_rect(texture, Rect2(at + rect.position * factor, rect.size * factor), false)
	return true


## Sprite del escritorio entero con lo que lleva (el largo), según computadora y pantallas.
## "" si no va así o no tiene computadora.
static func get_desk_set_sprite(desk_id: String, computer_id: String, monitors: int, rotation: int, shadow: bool = false) -> String:
	var base: String = get_desk_set_base(desk_id, computer_id, monitors)
	if base.is_empty():
		return ""
	var sprite: String = "%s_r%d%s" % [base, posmod(rotation, 4), "_shadow" if shadow else ""]
	return sprite if has_sprite(sprite) else ""


## Base del nombre de ese sprite (sin rotación), o "".
static func get_desk_set_base(desk_id: String, computer_id: String, monitors: int) -> String:
	var furniture: Dictionary = get_data().get("furniture", {})
	var sets: Dictionary = furniture.get(desk_id, {}).get("sets", {})
	if not sets.has(computer_id):
		return ""
	var names: Array = sets[computer_id]
	return String(names[clampi(monitors, 0, names.size() - 1)])


## Altura del teclado a lo largo del modelo (casillas desde la punta −x); -1 si no se sabe.
static func get_seat_x(base: String) -> float:
	var seats: Dictionary = get_data().get("seats", {})
	return float(seats[base]) if seats.has(base) else -1.0


## Base del sprite de un mueble (sin parte ni rotación), o "".
static func get_furniture_base(item_id: String) -> String:
	var furniture: Dictionary = get_data().get("furniture", {})
	return String(furniture[item_id]["base"]) if furniture.has(item_id) else ""


## Dibuja una tira vertical de un sprite (columnas from–to en px desde el apoyo). False si no existe.
static func draw_strip(canvas: CanvasItem, sprite: String, at: Vector2, from: float, to: float) -> bool:
	var texture: Texture2D = get_texture(sprite)
	if texture == null:
		return false
	var rect: Rect2 = get_rect(sprite)
	var size: Vector2 = rect.size * get_scale()
	var anchor_x: float = -rect.position.x * get_scale()
	var left: float = clampf(anchor_x + from, 0.0, size.x)
	var right: float = clampf(anchor_x + to, 0.0, size.x)
	if right <= left:
		return true
	var source := Rect2(left, 0.0, right - left, size.y)
	var target := Rect2(at + rect.position + Vector2(left / get_scale(), 0.0), source.size / get_scale())
	canvas.draw_texture_rect_region(texture, target, source)
	return true


## Dibuja la sombra de piso de un sprite (a SHADOW_ALPHA). False si no existe.
static func draw_shadow(canvas: CanvasItem, sprite: String, at: Vector2 = Vector2.ZERO) -> bool:
	return draw(canvas, sprite, at, Color(1.0, 1.0, 1.0, SHADOW_ALPHA))


## Indica si hay hoja de personaje con ese aspecto.
static func has_character_look(look: String) -> bool:
	var looks: Dictionary = get_data().get("characters", {}).get("looks", {})
	return looks.has(look)


## Indica si las hojas traen esa pose (p. ej. "type_basic_chair", con la silla dibujada, o "mop" del suape).
static func has_character_pose(pose: String) -> bool:
	return not _pose_table(pose).is_empty()


## Cuadros de una pose ("stand", "sit", "idle", "walk", "type", "mop", "mopwalk"); 0 si no existe.
static func get_character_frames(pose: String) -> int:
	var poses: Dictionary = _pose_table(pose)
	return int(poses[pose]["frames"]) if not poses.is_empty() else 0


## Indica si ese aspecto tiene las poses del suape (hoja aparte, solo el personal de limpieza).
static func has_tool_look(look: String) -> bool:
	return get_data().get("characters", {}).get("tool_looks", {}).has(look)


## Sprite del cubo que va junto a quien trapea ("" si no hay).
static func get_bucket_sprite() -> String:
	return String(get_data().get("characters", {}).get("bucket", ""))


# Tabla de poses donde está esa pose: la de las hojas comunes o la de las herramientas; vacía si no.
static func _pose_table(pose: String) -> Dictionary:
	var characters: Dictionary = get_data().get("characters", {})
	for table: String in ["poses", "tool_poses"]:
		var poses: Dictionary = characters.get(table, {})
		if poses.has(pose):
			return poses
	return {}


## Dibuja un cuadro de personaje con los pies en `at` (aspecto, pose, dirección 0–3, cuadro).
## band (x desde, y hasta, px sobre los pies) dibuja solo esa franja. False si no existe.
static func draw_character(canvas: CanvasItem, look: String, pose: String, rotation: int, frame: int,
		at: Vector2 = Vector2.ZERO, band: Vector2 = Vector2.ZERO) -> bool:
	var characters: Dictionary = get_data().get("characters", {})
	var poses: Dictionary = characters.get("poses", {})
	var looks: Dictionary = characters.get("looks", {})
	var key: String = "character:" + look
	if not poses.has(pose):
		# Poses del suape: en la hoja de herramientas del aspecto.
		poses = characters.get("tool_poses", {})
		looks = characters.get("tool_looks", {})
		key = "tools:" + look
	if not looks.has(look) or not poses.has(pose):
		return false
	if not _textures.has(key):
		var path: String = FOLDER + String(looks[look])
		_textures[key] = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var texture: Texture2D = _textures[key]
	if texture == null:
		return false
	var cell := Vector2(float(characters["cell"][0]), float(characters["cell"][1]))
	var anchor := Vector2(float(characters["anchor"][0]), float(characters["anchor"][1]))
	var column: int = int(poses[pose]["column"]) + posmod(frame, int(poses[pose]["frames"]))
	var source := Rect2(Vector2(column, posmod(rotation, 4)) * cell, cell)
	var target := Rect2(at - anchor / get_scale(), cell / get_scale())
	if band != Vector2.ZERO:
		var top: float = clampf(anchor.y - band.y, 0.0, cell.y)
		var bottom: float = clampf(anchor.y - band.x, 0.0, cell.y)
		source = Rect2(source.position + Vector2(0.0, top), Vector2(cell.x, bottom - top))
		target = Rect2(target.position + Vector2(0.0, top / get_scale()), source.size / get_scale())
	canvas.draw_texture_rect_region(texture, target, source)
	return true


## Sombra de piso de un personaje de pie.
static func draw_character_shadow(canvas: CanvasItem, at: Vector2 = Vector2.ZERO) -> bool:
	return draw_shadow(canvas, String(get_data().get("characters", {}).get("shadow", "")), at)


## Atlas del suelo: {file, tile, styles}; vacío si no hay.
static func get_ground() -> Dictionary:
	return get_data().get("ground", {})
