# Prueba del suelo con más detalle (pedido después del hito 69): pisos y terreno se pintan
# con GroundPainter.DETAIL veces más píxeles por casilla y la capa se dibuja achicada y
# suavizada; las casillas siguen midiendo 64×32 en el mundo. El TileSet se pinta una vez y
# lo comparten las partidas; los dibujos se repiten cada casilla sin costuras.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=ground
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	_check_painter()
	await _check_grid()
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _check_painter() -> void:
	var styles: Array[String] = [ConstructionCatalog.BARE_FLOOR, ConstructionCatalog.TERRAIN]
	styles.append_array(ConstructionCatalog.get_floor_types())
	styles.append_array(MapDecor.get_styles().keys())
	for style: String in styles:
		_expect(GroundPainter.MATERIALS.has(style), "%s tiene material" % style)
	_expect(GroundPainter.get_material("wood") == GroundPainter.WOOD and GroundPainter.get_material("grass") == GroundPainter.GRASS,
		"madera y pasto")
	# El ruido y los dibujos se repiten cada casilla: los bordes opuestos coinciden.
	var same: bool = true
	for step: int in range(10):
		var v: float = step / 10.0
		same = same and is_equal_approx(GroundPainter.noise(0.0, v, 5, 7), GroundPainter.noise(1.0, v, 5, 7))
		same = same and is_equal_approx(GroundPainter.noise(v, 0.0, 5, 7), GroundPainter.noise(v, 1.0, 5, 7))
	_expect(same, "el ruido se repite cada casilla")
	var base := Color("c9b48a")
	var other := Color("b39c72")
	var ceramic_a: Color = GroundPainter.shade(GroundPainter.CERAMIC, base, other, 0.25, 0.0001, 0, 0, 1)
	var ceramic_b: Color = GroundPainter.shade(GroundPainter.CERAMIC, base, other, 0.25, 0.9999, 0, 0, 1)
	_expect(ceramic_a.is_equal_approx(ceramic_b), "la junta de la cerámica coincide entre casillas: %s / %s" % [ceramic_a, ceramic_b])
	var middle: Color = GroundPainter.shade(GroundPainter.CERAMIC, base, other, 0.25, 0.25, 0, 0, 1)
	_expect(ceramic_a.v < middle.v, "la junta es más oscura que la losa")
	var gap: Color = GroundPainter.shade(GroundPainter.WOOD, Color("8f6b4a"), Color("7d5c3f"), 0.5, 0.01, 0, 0, 1)
	var plank: Color = GroundPainter.shade(GroundPainter.WOOD, Color("8f6b4a"), Color("7d5c3f"), 0.5, 0.12, 0, 0, 1)
	_expect(gap.v < plank.v, "la ranura entre tablones es más oscura")


func _check_grid() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var floor_layer: TileMapLayer = grid.get_node("Floor")
	var surroundings: TileMapLayer = grid.get_node("Surroundings")
	_expect(floor_layer.tile_set.tile_size == GameConstants.TILE_SIZE * GroundPainter.DETAIL, "losas de textura más grandes")
	_expect(floor_layer.scale.is_equal_approx(Vector2.ONE / GroundPainter.DETAIL) and surroundings.scale == floor_layer.scale,
		"las capas se achican")
	_expect(floor_layer.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "el suelo se suaviza")
	var step: Vector2 = grid.cell_to_world(Vector2i(1, 0)) - grid.cell_to_world(Vector2i(0, 0))
	_expect(step.is_equal_approx(Vector2(GameConstants.TILE_SIZE) / 2.0), "la casilla sigue midiendo 64×32 en el mundo: %s" % step)
	var cell := Vector2i(3, 2)
	_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "ida y vuelta entre casilla y mundo")
	grid.update_hover(grid.cell_to_world(cell))
	var highlight: Node2D = grid.get_node("CellHighlight")
	_expect(highlight.visible and highlight.global_position.is_equal_approx(grid.cell_to_world(cell)), "el resaltado cae en su casilla")
	var source: TileSetAtlasSource = floor_layer.tile_set.get_source(floor_layer.get_cell_source_id(cell))
	_expect(source != null and source.texture.get_image().has_mipmaps(), "la textura trae mipmaps")
	# Otra partida usa el mismo TileSet (se pinta una sola vez).
	var tile_set: TileSet = floor_layer.tile_set
	game.queue_free()
	await get_tree().process_frame
	var started: int = Time.get_ticks_msec()
	var again: Node = GAME_SCENE.instantiate()
	add_child(again)
	await get_tree().process_frame
	_expect(again.get_node("OfficeGrid/Floor").tile_set == tile_set, "la segunda partida reusa el TileSet")
	_expect(Time.get_ticks_msec() - started < 1000, "y abre rápido: %d ms" % (Time.get_ticks_msec() - started))
	again.queue_free()
	await get_tree().process_frame
