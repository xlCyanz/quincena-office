# Sprites del juego (fase 8): dónde está cada imagen y su punto de apoyo, según
# data/sprites.json (lo escribe tools/sprites/export_game.py). Los sprites se dibujan a
# SCALE px por px del mundo, así que en el mundo miden la mitad. Funciones estáticas.
class_name SpriteLibrary
extends RefCounted

const DATA_PATH: String = "res://data/sprites.json"
const FOLDER: String = "res://assets/sprites/"
## Opacidad de las sombras de piso (el sprite de sombra es de un solo tono opaco).
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


## Rectángulo en px del mundo donde va el sprite si su punto de apoyo cae en `at`.
static func get_rect(sprite: String, at: Vector2 = Vector2.ZERO) -> Rect2:
	var sprites: Dictionary = get_data().get("sprites", {})
	if not sprites.has(sprite):
		return Rect2()
	var entry: Dictionary = sprites[sprite]
	var anchor := Vector2(float(entry["anchor"][0]), float(entry["anchor"][1]))
	var size := Vector2(float(entry["size"][0]), float(entry["size"][1]))
	return Rect2(at - anchor / get_scale(), size / get_scale())


## Dibuja un sprite en `canvas` con su punto de apoyo en `at`. Devuelve false si no existe.
static func draw(canvas: CanvasItem, sprite: String, at: Vector2 = Vector2.ZERO, modulate: Color = Color.WHITE) -> bool:
	var texture: Texture2D = get_texture(sprite)
	if texture == null:
		return false
	canvas.draw_texture_rect(texture, get_rect(sprite, at), false, modulate)
	return true


## Nombre del sprite de un mueble del juego con su rotación ("" si no tiene). part es
## "seat" o "back" en los que van en partes (las sillas) y "shadow" da su sombra.
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


## Nombre del sprite de un objeto de pared colgado en un borde de ese eje (GridEdge.AXIS_X o
## AXIS_Y); pick elige entre sus dibujos (los cuadros tienen varios). "" si no tiene.
static func get_wall_item_sprite(item_id: String, axis: int, pick: int = 0) -> String:
	var items: Dictionary = get_data().get("wall_items", {})
	if not items.has(item_id):
		return ""
	var names: Array = items[item_id]["sprites"]
	var sprite: String = "%s_%s" % [names[posmod(pick, names.size())], "x" if axis == GridEdge.AXIS_X else "y"]
	return sprite if has_sprite(sprite) else ""


## A cuántos px del mundo sobre el piso empieza el dibujo de un objeto de pared.
static func get_wall_item_base(item_id: String) -> float:
	var items: Dictionary = get_data().get("wall_items", {})
	return float(items[item_id]["base_z"]) / get_scale() if items.has(item_id) else 0.0


## Dibuja un sprite achicado por factor alrededor de su punto de apoyo, que cae en `at`.
static func draw_scaled(canvas: CanvasItem, sprite: String, at: Vector2, factor: float) -> bool:
	var texture: Texture2D = get_texture(sprite)
	if texture == null:
		return false
	var rect: Rect2 = get_rect(sprite)
	canvas.draw_texture_rect(texture, Rect2(at + rect.position * factor, rect.size * factor), false)
	return true


## Dibuja la sombra de piso de un sprite (a SHADOW_ALPHA). Devuelve false si no existe.
static func draw_shadow(canvas: CanvasItem, sprite: String, at: Vector2 = Vector2.ZERO) -> bool:
	return draw(canvas, sprite, at, Color(1.0, 1.0, 1.0, SHADOW_ALPHA))


## Indica si hay una hoja de personaje con ese aspecto (conjunto de ropa y paleta).
static func has_character_look(look: String) -> bool:
	var looks: Dictionary = get_data().get("characters", {}).get("looks", {})
	return looks.has(look)


## Cuadros de una pose de personaje ("stand", "sit", "idle", "walk", "type"); 0 si no existe.
static func get_character_frames(pose: String) -> int:
	var poses: Dictionary = get_data().get("characters", {}).get("poses", {})
	return int(poses[pose]["frames"]) if poses.has(pose) else 0


## Dibuja un cuadro de un personaje con los pies en `at`: aspecto, pose, dirección (0–3,
## como las rotaciones de los muebles) y cuadro. Devuelve false si no existe.
static func draw_character(canvas: CanvasItem, look: String, pose: String, rotation: int, frame: int,
		at: Vector2 = Vector2.ZERO) -> bool:
	var characters: Dictionary = get_data().get("characters", {})
	var looks: Dictionary = characters.get("looks", {})
	var poses: Dictionary = characters.get("poses", {})
	if not looks.has(look) or not poses.has(pose):
		return false
	var key: String = "character:" + look
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
	canvas.draw_texture_rect_region(texture, Rect2(at - anchor / get_scale(), cell / get_scale()), source)
	return true


## Sombra de piso de un personaje de pie.
static func draw_character_shadow(canvas: CanvasItem, at: Vector2 = Vector2.ZERO) -> bool:
	return draw_shadow(canvas, String(get_data().get("characters", {}).get("shadow", "")), at)


## Atlas del suelo: {file, tile, styles}; vacío si no hay.
static func get_ground() -> Dictionary:
	return get_data().get("ground", {})
