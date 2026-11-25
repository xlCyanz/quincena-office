# Sprites del juego según data/sprites.json (lo escribe tools/sprites/export_game.py): imagen y
# apoyo. Se dibujan a 1/SCALE (miden la mitad en el mundo). Funciones estáticas.
class_name SpriteLibrary
extends RefCounted

const DATA_PATH: String = "res://data/sprites.json"
const FOLDER: String = "res://assets/sprites/"
## Opacidad de las sombras de piso (el sprite de sombra es opaco).
const SHADOW_ALPHA: float = 0.3
## Shader que pone la paleta de cada aspecto sobre la hoja base (tablas en characters.palettes).
const PALETTE_SHADER: Shader = preload("res://scripts/office/character_palette.gdshader")
## Foto de carné: fila de la hoja que mira al frente, lado del recorte (px de hoja) y aire sobre la cabeza.
const PORTRAIT_ROW: int = 1
const PORTRAIT_SIZE: int = 64
const PORTRAIT_HEADROOM: int = 6

static var _data: Dictionary = {}
static var _textures: Dictionary[String, Texture2D] = {}
## Material de paleta por aspecto (null si usa la paleta base).
static var _palette_materials: Dictionary[String, ShaderMaterial] = {}
## Recorte de la foto por hoja (ver get_portrait).
static var _portrait_rects: Dictionary[String, Rect2] = {}


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


## Sprite de un objeto de pared en un borde de ese eje; pick elige entre sus dibujos y back da la vista de
## espaldas (colgado del lado de la pared que no se ve). "" si no tiene.
static func get_wall_item_sprite(item_id: String, axis: int, pick: int = 0, back: bool = false) -> String:
	var items: Dictionary = get_data().get("wall_items", {})
	if not items.has(item_id):
		return ""
	var names: Array = items[item_id]["sprites"]
	var sprite: String = "%s_%s%s" % [names[posmod(pick, names.size())], "back_" if back else "",
		"x" if axis == GridEdge.AXIS_X else "y"]
	return sprite if has_sprite(sprite) else ""


## Cuadros de la animación de un objeto de pared prendido (0 si no se prende, como todos salvo la pantalla).
static func get_wall_item_play_frames(item_id: String) -> int:
	return int(get_data().get("wall_items", {}).get(item_id, {}).get("play_frames", 0))


## Sprite de un objeto de pared prendido: dibujo que toca por pick y cuadro (1 a get_wall_item_play_frames; de
## espaldas no se ve la animación). "" si no tiene.
static func get_wall_item_on_sprite(item_id: String, axis: int, pick: int, back: bool, frame: int) -> String:
	var screens: Array = get_data().get("wall_items", {}).get(item_id, {}).get("on", [])
	if screens.is_empty():
		return ""
	var sprite: String = "%s_%s%s" % [screens[posmod(pick, screens.size())], "back_" if back else "",
		"x" if axis == GridEdge.AXIS_X else "y"]
	if not back:
		sprite += "_play_%d" % frame
	return sprite if has_sprite(sprite) else ""


## Cuadros de abrir de una pieza de borde (0 si no se abre).
static func get_door_frames(piece_kind: String) -> int:
	var doors: Dictionary = get_data().get("doors", {})
	return int(doors.get("frames", 0)) if piece_kind in doors.get("opening", []) else 0


## Cuadro de abrir (1 a get_door_frames) del tramo alto de una puerta; "" si no hay.
static func get_door_frame_sprite(base_sprite: String, frame: int) -> String:
	var sprite: String = "%s_open_%d" % [base_sprite, frame]
	return sprite if has_sprite(sprite) else ""


## Sombra que deja una pared alta de ese eje en la casilla de adentro ("" si no hay).
static func get_wall_shadow_sprite(axis: int) -> String:
	var sprite: String = String(get_data().get("wall_shadow", "")).replace("%s", "x" if axis == GridEdge.AXIS_X else "y")
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


## Hueco (casillas) entre la planta de una mesa y el canto del tablero por lado del modelo (frente −y, +x,
## fondo +y, −x); [] si no se sabe.
static func get_table_edges(base: String) -> Array:
	var edges: Dictionary = get_data().get("edges", {})
	return edges[base] if edges.has(base) else []


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
	if not poses.has(pose):
		# Poses del suape: en la hoja de herramientas del aspecto.
		poses = characters.get("tool_poses", {})
		looks = characters.get("tool_looks", {})
	if not looks.has(look) or not poses.has(pose):
		return false
	# Las paletas comparten la hoja base: la textura se guarda por archivo.
	var path: String = FOLDER + String(looks[look])
	if not _textures.has(path):
		_textures[path] = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var texture: Texture2D = _textures[path]
	if texture == null:
		return false
	var palette: ShaderMaterial = get_character_material(look)
	if canvas.material != palette:
		canvas.material = palette
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


## Hoja y recorte de la foto de carné de un aspecto: cabeza y hombros del cuadro de pie mirando al frente.
## {} si no hay hoja.
static func get_portrait(look: String) -> Dictionary:
	var characters: Dictionary = get_data().get("characters", {})
	var looks: Dictionary = characters.get("looks", {})
	var poses: Dictionary = characters.get("poses", {})
	if not looks.has(look) or not poses.has("stand"):
		return {}
	var path: String = FOLDER + String(looks[look])
	if not _textures.has(path):
		_textures[path] = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var texture: Texture2D = _textures[path]
	if texture == null:
		return {}
	if not _portrait_rects.has(path):
		var cell := Vector2i(int(characters["cell"][0]), int(characters["cell"][1]))
		var frame := Rect2i(Vector2i(int(poses["stand"]["column"]) * cell.x, PORTRAIT_ROW * cell.y), cell)
		var used: Rect2i = texture.get_image().get_region(frame).get_used_rect()
		var center_x: int = frame.position.x + used.position.x + used.size.x / 2
		var top: int = frame.position.y + used.position.y - PORTRAIT_HEADROOM
		_portrait_rects[path] = Rect2(center_x - PORTRAIT_SIZE / 2, top, PORTRAIT_SIZE, PORTRAIT_SIZE)
	return {"texture": texture, "source": _portrait_rects[path], "material": get_character_material(look)}


## Material con la paleta de ese aspecto sobre su hoja base; null si es la paleta base o no existe.
static func get_character_material(look: String) -> ShaderMaterial:
	if _palette_materials.has(look):
		return _palette_materials[look]
	var palette: Dictionary = get_data().get("characters", {}).get("palettes", {}).get(look, {})
	var material: ShaderMaterial = null
	if not palette.is_empty():
		var from_colors := PackedVector3Array()
		var to_colors := PackedVector3Array()
		for index: int in range(palette["from"].size()):
			var from_color := Color(String(palette["from"][index]))
			var to_color := Color(String(palette["to"][index]))
			from_colors.append(Vector3(from_color.r, from_color.g, from_color.b))
			to_colors.append(Vector3(to_color.r, to_color.g, to_color.b))
		material = ShaderMaterial.new()
		material.shader = PALETTE_SHADER
		material.set_shader_parameter("color_count", from_colors.size())
		material.set_shader_parameter("from_colors", from_colors)
		material.set_shader_parameter("to_colors", to_colors)
	_palette_materials[look] = material
	return material


## Sprites de las manchas de suciedad (una casilla cada una).
static func get_dirt_sprites() -> Array[String]:
	var sprites: Array[String] = []
	for sprite: Variant in get_data().get("dirt", []):
		if has_sprite(String(sprite)):
			sprites.append(String(sprite))
	return sprites


## Icono de la barra de la partida (null si no hay).
static func get_ui_icon(icon: String) -> Texture2D:
	var sprite: String = String(get_data().get("ui_icons", {}).get(icon, ""))
	return get_texture(sprite) if has_sprite(sprite) else null


## Sprite del globo de un icono de estado ("" si no hay).
static func get_status_icon_sprite(icon: String) -> String:
	var sprite: String = String(get_data().get("status_icons", {}).get(icon, ""))
	return sprite if has_sprite(sprite) else ""


## Sombra de piso de un personaje de pie.
static func draw_character_shadow(canvas: CanvasItem, at: Vector2 = Vector2.ZERO) -> bool:
	return draw_shadow(canvas, String(get_data().get("characters", {}).get("shadow", "")), at)


## Atlas del suelo: {file, tile, styles}; vacío si no hay.
static func get_ground() -> Dictionary:
	return get_data().get("ground", {})
