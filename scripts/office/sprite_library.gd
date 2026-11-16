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


## Atlas del suelo: {file, tile, styles}; vacío si no hay.
static func get_ground() -> Dictionary:
	return get_data().get("ground", {})
