# Prueba de las secciones de Construir (pedido después del hito 69): arriba Estructura,
# Muebles, Habitaciones y Terreno; solo se ven las herramientas de la abierta (los muebles
# además por categoría), así el panel tapa poco del mapa. Terreno muestra solo su fila y
# deja ver el terreno que se compra.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=build_sections
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
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var build: BuildPanel = game.get_node("BuildPanel")
	build.set_build_mode(true)
	await get_tree().process_frame

	_expect(build.get_section() == BuildPanel.SECTION_STRUCTURE, "empieza en Estructura")
	_expect(_visible(build, BuildController.TOOL_WALL) and not _visible(build, "simple_desk")
		and not _visible(build, "work_area") and not build.is_land_row_visible(), "solo se ven las de Estructura")
	var panel: PanelContainer = build.get("_panel")
	var view_height: float = panel.get_viewport_rect().size.y

	# Muebles: categorías; solo se ven los de la abierta.
	build.get_section_button(BuildPanel.SECTION_FURNITURE).pressed.emit()
	await get_tree().process_frame
	_expect(build.get_selected_tool() == "simple_desk" and build.get_category() == "work",
		"Muebles elige el primero de Trabajo: %s" % build.get_selected_tool())
	_expect(_visible(build, "simple_desk") and not _visible(build, "small_plant") and _visible(build, BuildController.TOOL_ROTATE),
		"se ven Trabajo, Girar y Mejorar, no la decoración")
	_expect(panel.get_global_rect().size.y < view_height * 0.4, "Muebles tapa menos de 40 %% de la pantalla: %d" % panel.get_global_rect().size.y)
	build.get_category_button("decor").pressed.emit()
	await get_tree().process_frame
	_expect(build.get_selected_tool() == "small_plant" and _visible(build, "small_plant") and not _visible(build, "simple_desk"),
		"Decoración muestra sus muebles y elige el primero")
	_expect(build.get_button_toward("simple_desk") == build.get_category_button("work"), "para llegar a un escritorio, Trabajo")
	_expect(build.get_button_toward("work_area") == build.get_section_button(BuildPanel.SECTION_ROOMS),
		"para llegar a un tipo de habitación, Habitaciones")

	# Terreno: solo su fila, poco alto.
	build.get_section_button(BuildPanel.SECTION_LAND).pressed.emit()
	await get_tree().process_frame
	_expect(build.get_selected_tool() == BuildController.TOOL_LAND and build.is_land_row_visible(), "Terreno elige la herramienta y su fila")
	_expect(not _visible(build, "small_plant") and not _visible(build, BuildController.TOOL_WALL), "en Terreno no se ve nada más")
	_expect(build.get_land_button("buy").is_visible_in_tree(), "se ve Comprar")
	_expect(panel.get_global_rect().size.y < view_height * 0.25, "Terreno tapa menos de 25 %% de la pantalla: %d" % panel.get_global_rect().size.y)
	var before: int = OfficeState.lot.get_area()
	build.get_land_button("buy").pressed.emit()
	await get_tree().process_frame
	_expect(OfficeState.lot.get_area() > before, "Comprar compra el terreno: %d → %d m²" % [before, OfficeState.lot.get_area()])

	# Elegir una herramienta de otra sección la abre.
	build.select_tool("work_area")
	await get_tree().process_frame
	_expect(build.get_section() == BuildPanel.SECTION_ROOMS and _visible(build, "work_area") and not build.is_land_row_visible(),
		"elegir una habitación abre Habitaciones")
	build.select_tool("aquarium")
	await get_tree().process_frame
	_expect(build.get_section() == BuildPanel.SECTION_FURNITURE and build.get_category() == "decor" and _visible(build, "aquarium"),
		"elegir la pecera abre Muebles en Decoración")
	_expect(FurnitureCatalog.get_ids().all(func(id: String) -> bool: return FurnitureCatalog.get_categories().has(FurnitureCatalog.get_category(id))),
		"cada mueble tiene una categoría")
	game.queue_free()
	await get_tree().process_frame
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _visible(build: BuildPanel, tool: String) -> bool:
	return build.get_tool_button(tool).is_visible_in_tree()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)
