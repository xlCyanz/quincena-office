# Bandeja de Construir (Inventario, Estructura, Habitaciones y Terreno): solo se ve la sección abierta, el
# inventario con sus tarjetas ×N, la Tienda a pantalla completa y Terreno solo su fila.
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

	_expect(build.get_section() == BuildPanel.SECTION_FURNITURE and build.get_selected_tool() == BuildController.TOOL_NONE,
		"empieza en Inventario, vacío y sin herramienta: %s" % build.get_selected_tool())
	_expect(build.get_tool_button("simple_desk") == null and _visible(build, BuildController.TOOL_STORE)
		and _visible(build, BuildController.TOOL_SELL), "inventario vacío: sin tarjetas; Guardar y Vender siempre a la vista")
	_expect(build.get_button_toward("simple_desk") == build.get_exit_button() and not build.get_shop_button().is_visible_in_tree(),
		"sin escritorios, el camino es salir: la Tienda está en la barra del mapa")
	var panel: PanelContainer = build.get("_panel")
	var view_height: float = panel.get_viewport_rect().size.y

	build.get_section_button(BuildPanel.SECTION_STRUCTURE).pressed.emit()
	await get_tree().process_frame
	_expect(build.get_selected_tool() == BuildController.TOOL_WALL and _visible(build, BuildController.TOOL_WALL)
		and not _visible(build, "work_area") and not build.is_land_row_visible(), "Estructura elige la pared y solo muestra lo suyo")

	OfficeState.add_stock("simple_desk", 2)
	OfficeState.add_stock("small_plant", 1)
	await get_tree().process_frame
	_expect(build.get_section_button(BuildPanel.SECTION_FURNITURE).text == "Inventario (3)",
		"la sección cuenta lo que hay: %s" % build.get_section_button(BuildPanel.SECTION_FURNITURE).text)
	_expect(build.get_button_toward("simple_desk") == build.get_section_button(BuildPanel.SECTION_FURNITURE),
		"con escritorios guardados, el camino es Inventario")
	build.get_section_button(BuildPanel.SECTION_FURNITURE).pressed.emit()
	await get_tree().process_frame
	_expect(build.get_selected_tool() != BuildController.TOOL_NONE and _visible(build, "simple_desk") and _visible(build, "small_plant"),
		"Inventario elige el primero y muestra cada tarjeta: %s" % build.get_selected_tool())
	_expect(build.get_tool_button("simple_desk").find_children("*", "Label", true, false).any(
		func(label: Label) -> bool: return label.text == "×2"), "la tarjeta dice ×2")
	_expect(panel.get_global_rect().size.y < view_height * 0.4, "Inventario tapa menos de 40 %% de la pantalla: %d" % panel.get_global_rect().size.y)
	_expect(build.get_button_toward("work_area") == build.get_section_button(BuildPanel.SECTION_ROOMS),
		"para llegar a un tipo de habitación, Habitaciones")

	build.set_shop_open(true)
	await get_tree().process_frame
	_expect(build.is_shop_open() and not panel.is_visible_in_tree() and build.is_build_mode(),
		"la Tienda tapa la bandeja y sigue en construcción")
	_expect(build.get_button_toward("aquarium") == build.get_shop().get_card("aquarium"), "en la Tienda, el camino es la tarjeta")
	build.get_shop().get_back_button().pressed.emit()
	await get_tree().process_frame
	_expect(not build.is_shop_open() and panel.is_visible_in_tree(), "Volver al mapa regresa a la bandeja")

	build.get_section_button(BuildPanel.SECTION_LAND).pressed.emit()
	await get_tree().process_frame
	_expect(build.get_selected_tool() == BuildController.TOOL_LAND and build.is_land_row_visible(), "Terreno elige la herramienta y su fila")
	_expect(not _visible(build, "small_plant") and not _visible(build, BuildController.TOOL_WALL), "en Terreno no se ve nada más")
	_expect(panel.get_global_rect().size.y < view_height * 0.25, "Terreno tapa menos de 25 %% de la pantalla: %d" % panel.get_global_rect().size.y)
	var before: int = OfficeState.lot.get_area()
	var land: BuildController = game.get_node("BuildController")
	_expect(not land.get_land_plots().is_empty(), "Terreno marca lotes para comprar")
	land.buy_land_plot_at((land.get_land_plots()[0]["new_cells"] as Array)[0])
	await get_tree().process_frame
	_expect(OfficeState.lot.get_area() > before, "un clic en un lote compra el terreno: %d → %d m²" % [before, OfficeState.lot.get_area()])

	build.select_tool("work_area")
	await get_tree().process_frame
	_expect(build.get_section() == BuildPanel.SECTION_ROOMS and _visible(build, "work_area") and not build.is_land_row_visible(),
		"elegir una habitación abre Habitaciones")
	build.select_tool("small_plant")
	await get_tree().process_frame
	_expect(build.get_section() == BuildPanel.SECTION_FURNITURE and _visible(build, "small_plant"),
		"elegir un mueble guardado abre Inventario")
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
