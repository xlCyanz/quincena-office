# Menú Proyectos (lado izquierdo, no pausa): pestañas Contratos (reputación, contratos en curso,
# visitas en la Recepción y ofertas) y Productos; los dos comparten el tope de proyectos en curso.
class_name ProjectsPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal projects_mode_changed(active: bool)

const PANEL_WIDTH: float = 560.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 100.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := UiTheme.MUTED
const STARS: int = 5
const PHASE_LABEL_WIDTH: float = 120.0
const PHASE_VALUE_WIDTH: float = 150.0
const BAR_HEIGHT: float = 14.0
const TAB_CONTRACTS: String = "contracts"
const TAB_PRODUCTS: String = "products"

# Botón «?» de ayuda.
var _help_button: Button
var _open_button: Button
var _panel: PanelContainer
var _reputation_label: Label
var _status_label: Label
var _list: VBoxContainer
var _accept_buttons: Dictionary[int, Button] = {}
var _reject_buttons: Dictionary[int, Button] = {}
var _bars: Dictionary[int, Dictionary] = {}
var _deliver_buttons: Dictionary[int, Button] = {}
var _cancel_buttons: Dictionary[int, Button] = {}
var _confirm_cancel_button: Button
# Contrato cuya cancelación se está confirmando (0 = ninguno).
var _confirming_cancel: int = 0
var _tab: String = TAB_CONTRACTS
var _tab_buttons: Dictionary[String, Button] = {}
# Tipo y tamaño elegidos para el próximo producto.
var _new_type: String = ""
var _new_size: String = ""
var _start_button: Button
var _product_bars: Dictionary[int, Dictionary] = {}
var _owner_choices: Dictionary[int, OptionButton] = {}
var _abandon_buttons: Dictionary[int, Button] = {}
var _confirm_abandon_button: Button
# Producto cuyo abandono se está confirmando (0 = ninguno).
var _confirming_abandon: int = 0
var _launch_buttons: Dictionary[int, Button] = {}
var _update_buttons: Dictionary[int, Button] = {}
var _retire_buttons: Dictionary[int, Button] = {}
var _confirm_retire_button: Button
# Producto lanzado cuyo retiro se está confirmando (0 = ninguno).
var _confirming_retire: int = 0


func _ready() -> void:
	_open_button = Button.new()
	Hud.style_bar_button(_open_button, "projects")
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.pressed.connect(func() -> void: set_open(not is_open()))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = MARGIN + PANEL_WIDTH
	_panel.offset_top = MARGIN_TOP
	_panel.offset_bottom = -MARGIN_BOTTOM
	# Ancho y alto según la pantalla y la barra de menús.
	UiLayout.fit_left_panel(_panel, PANEL_WIDTH)
	EventBus.ui_layout_changed.connect(func() -> void: UiLayout.fit_left_panel(_panel, PANEL_WIDTH))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "Proyectos"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	header.add_child(title)
	_reputation_label = Label.new()
	_reputation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reputation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_reputation_label)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	_help_button = HelpButton.create("projects")
	header.add_child(_help_button)
	header.add_child(close_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_status_label)
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	var group := ButtonGroup.new()
	for tab: String in [TAB_CONTRACTS, TAB_PRODUCTS]:
		var button := Button.new()
		button.text = "Contratos" if tab == TAB_CONTRACTS else "Productos"
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = tab == _tab
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_tab.bind(tab))
		tabs.add_child(button)
		_tab_buttons[tab] = button

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_panel.visible = false
	EventBus.projects_changed.connect(_refresh)
	EventBus.products_changed.connect(_refresh)
	EventBus.staff_changed.connect(_refresh)
	EventBus.office_changed.connect(_refresh)
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: _refresh())
	_refresh()


## Pone el botón "Proyectos" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_status_label.text = ""
		_refresh()
	projects_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


func get_open_button() -> Button:
	return _open_button


## Cambia de pestaña: TAB_CONTRACTS o TAB_PRODUCTS.
func set_tab(tab: String) -> void:
	_tab = tab
	_tab_buttons[tab].set_pressed_no_signal(true)
	_status_label.text = ""
	_refresh()


func get_tab() -> String:
	return _tab


func get_tab_button(tab: String) -> Button:
	return _tab_buttons.get(tab)


## Botón "Empezar" del producto nuevo, o null (fuera de la pestaña Productos).
func get_start_button() -> Button:
	return _start_button


## Elige el tipo y el tamaño del próximo producto como en las listas de la pestaña.
func choose_new_product(type_id: String, size: String) -> void:
	_new_type = type_id
	_new_size = size
	_refresh()


## Lista de quién lleva un producto, o null.
func get_owner_choice(product_id: int) -> OptionButton:
	return _owner_choices.get(product_id)


## Botón "Abandonar" de un producto, o null.
func get_abandon_button(product_id: int) -> Button:
	return _abandon_buttons.get(product_id)


## Botón que confirma el abandono pedido, o null.
func get_confirm_abandon_button() -> Button:
	return _confirm_abandon_button


## Botón "Lanzar" de un producto terminado, o null.
func get_launch_button(product_id: int) -> Button:
	return _launch_buttons.get(product_id)


## Botón "Actualizar" de un producto lanzado, o null.
func get_update_button(product_id: int) -> Button:
	return _update_buttons.get(product_id)


## Botón "Retirar" de un producto lanzado, o null.
func get_retire_button(product_id: int) -> Button:
	return _retire_buttons.get(product_id)


## Botón que confirma el retiro pedido, o null.
func get_confirm_retire_button() -> Button:
	return _confirm_retire_button


## Barra de avance de una fase de un producto en desarrollo, o null.
func get_product_bar(product_id: int, phase: String) -> ProgressBar:
	return _product_bars.get(product_id, {}).get(phase)


func get_status_text() -> String:
	return _status_label.text


## Botón "Aceptar" de una oferta, o null.
func get_accept_button(offer_id: int) -> Button:
	return _accept_buttons.get(offer_id)


## Botón "Rechazar" de una oferta, o null.
func get_reject_button(offer_id: int) -> Button:
	return _reject_buttons.get(offer_id)


## Botón "Entregar" de un contrato en curso, o null.
func get_deliver_button(contract_id: int) -> Button:
	return _deliver_buttons.get(contract_id)


## Botón "Cancelar contrato" de un contrato en curso, o null.
func get_cancel_button(contract_id: int) -> Button:
	return _cancel_buttons.get(contract_id)


## Botón que confirma la cancelación pedida, o null si no se está confirmando ninguna.
func get_confirm_cancel_button() -> Button:
	return _confirm_cancel_button


## Barra de avance de una fase de un contrato en curso, o null.
func get_phase_bar(contract_id: int, phase: String) -> ProgressBar:
	return _bars.get(contract_id, {}).get(phase)


## Todo el texto del panel (para las pruebas).
func get_list_text() -> String:
	var texts: Array[String] = [_reputation_label.text]
	for label: Node in _list.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return "\n".join(texts)


## "★☆☆☆☆ 1.6": las estrellas y el valor exacto.
static func describe_reputation(value: float) -> String:
	return "%s %s" % [stars(value), String.num(value, 1) if not is_equal_approx(value, roundf(value)) else str(roundi(value))]


## "★☆☆☆☆" de 1 a 5: solo estrellas completas (1.9 = una), porque las ofertas piden estrellas enteras.
static func stars(value: float) -> String:
	var full: int = clampi(floori(value + 0.0001), 0, STARS)
	return "★".repeat(full) + "☆".repeat(STARS - full)


func _refresh() -> void:
	var count: int = Projects.offers.size()
	_open_button.text = "Proyectos (%d)" % count if count > 0 else "Proyectos"
	if _list == null or not is_open():
		return
	_reputation_label.text = "Reputación %s" % describe_reputation(Projects.reputation)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_accept_buttons.clear()
	_reject_buttons.clear()
	_bars.clear()
	_deliver_buttons.clear()
	_cancel_buttons.clear()
	_confirm_cancel_button = null
	if Projects.get_contract(_confirming_cancel).is_empty():
		_confirming_cancel = 0
	_start_button = null
	_product_bars.clear()
	_owner_choices.clear()
	_abandon_buttons.clear()
	_confirm_abandon_button = null
	_launch_buttons.clear()
	_update_buttons.clear()
	_retire_buttons.clear()
	_confirm_retire_button = null
	if _tab == TAB_PRODUCTS:
		_refresh_products()
		return

	_add_section("En curso (%d de %d)" % [Projects.get_project_count(), Projects.get_contract_limit()])
	if Products.get_development_count() > 0:
		_list.add_child(_muted_label("El tope cuenta también %d %s en desarrollo." % [Products.get_development_count(),
			"producto" if Products.get_development_count() == 1 else "productos"]))
	if Projects.contracts.is_empty():
		_list.add_child(_muted_label("Ningún contrato en curso. Acepta una oferta de la bandeja."))
	for contract: Dictionary in Projects.contracts:
		_add_contract(contract)
	_list.add_child(HSeparator.new())
	_add_section("Ofertas (%d)" % Projects.offers.size())
	if Projects.offers.is_empty():
		_list.add_child(_muted_label("No hay ofertas. Llegan a las %02d:00; más con vendedores y con más reputación." % int(
			ContractCatalog.get_offers("arrival_hour"))))
	for offer: Dictionary in Projects.offers:
		_add_offer(offer)
	if not Projects.visits.is_empty():
		_add_section("En la Recepción (%d)" % Projects.visits.size())
		for visit: Dictionary in Projects.visits:
			var offer: Dictionary = visit["offer"]
			_list.add_child(_muted_label("Cliente de %s · %s %s · espera hasta las %d:00%s" % [offer["client"],
				ContractCatalog.get_type_name(offer["type"]), ContractCatalog.get_size_name(offer["size"]).to_lower(),
				posmod(int(visit["leaves_at"]), GameConstants.HOURS_PER_DAY),
				"" if Staff.is_reception_attended(GameClock.get_weekday(), GameClock.get_hour()) else " · nadie lo atiende"]))
	if not Projects.history.is_empty():
		_add_section("Historial")
		for entry: Dictionary in Projects.history:
			var change: float = float(entry["reputation_change"])
			_list.add_child(_muted_label("Día %d · %s · %s · %s · reputación %s%s" % [int(entry["day"]) + 1, entry["title"],
				entry["result"], MoneyFormat.format(entry["paid"]), "+" if change >= 0.0 else "−", String.num(absf(change), 2)]))


func _add_contract(contract: Dictionary) -> void:
	var days_left: int = Projects.contract_days_left(contract)
	var deadline: String
	if days_left > 1:
		deadline = "quedan %d días" % days_left
	elif days_left == 1:
		deadline = "queda 1 día"
	elif days_left == 0:
		deadline = "vence hoy"
	else:
		deadline = "atrasado %d %s" % [-days_left, "día" if days_left == -1 else "días"]
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var owner_text: String = Projects.describe_owner(contract)
	info.text = "%s · %s\n%s · Pago %s · %s" % [Projects.describe_title(contract), deadline,
		owner_text.left(1).to_upper() + owner_text.substr(1), MoneyFormat.format(contract["pay"]),
		"anticipo cobrado %s" % MoneyFormat.format(contract["advance"]) if int(contract["advance"]) > 0 else "sin anticipo"]
	_list.add_child(info)
	_bars[contract["id"]] = _add_phase_rows(contract)
	_list.add_child(_muted_label(Projects.describe_bugs(contract) + "."))
	var state: String
	var pending: int = int(contract["bugs_found"])
	if Production.is_finished(contract) and pending > 0:
		state = "Terminado, con %d %s por corregir: los programadores siguen." % [pending, "error" if pending == 1 else "errores"]
	elif Production.is_finished(contract):
		state = "Terminado: listo para entregar. Si el equipo tiene QA, sigue buscando errores."
	elif int(contract["team_id"]) == Projects.NO_TEAM:
		state = "Nadie lo lleva: dáselo a un equipo en el menú Equipos."
	else:
		var rate: float = Projects.get_hourly_rate(contract)
		state = "Ahora rinde %s puntos por hora." % String.num(rate, 1).trim_suffix(".0") if rate > 0.0 \
			else "Ahora nadie está trabajando en él."
	_list.add_child(_muted_label(state))
	_add_delivery_actions(contract)


# Las tres filas de avance (diseño, programación y pruebas) de un contrato o producto.
func _add_phase_rows(project: Dictionary) -> Dictionary[String, ProgressBar]:
	var bars: Dictionary[String, ProgressBar] = {}
	for phase: String in ContractCatalog.PHASES:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var name_label := Label.new()
		name_label.text = ContractCatalog.PHASE_NAMES[phase].capitalize()
		name_label.custom_minimum_size = Vector2(PHASE_LABEL_WIDTH, 0)
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
		bar.show_percentage = false
		bar.max_value = maxf(1.0, float(project["points"][phase]))
		bar.value = float(project["progress"][phase])
		row.add_child(bar)
		bars[phase] = bar
		var value := Label.new()
		var closed: bool = not Production.is_open(project, phase)
		value.text = "%d / %d%s" % [floori(float(project["progress"][phase]) + Production.EPSILON), project["points"][phase],
			" (espera)" if closed else ""]
		value.custom_minimum_size = Vector2(PHASE_VALUE_WIDTH, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
	return bars


# Pestaña Productos: empezar uno nuevo y los que están en desarrollo.
func _refresh_products() -> void:
	var types: Array[String] = ProductCatalog.get_type_ids()
	var sizes: Array[String] = ProductCatalog.get_size_ids()
	if not types.has(_new_type):
		_new_type = types[0]
	if not sizes.has(_new_size):
		_new_size = sizes[0]
	_add_section("Nuevo producto")
	_list.add_child(_muted_label("Sin cliente, sin plazo y sin anticipo: lo pagas con los sueldos hasta lanzarlo."))
	var choices := HBoxContainer.new()
	_list.add_child(choices)
	var type_choice := OptionButton.new()
	type_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in range(types.size()):
		type_choice.add_item(ProductCatalog.get_type_name(types[index]), index)
	type_choice.select(types.find(_new_type))
	type_choice.item_selected.connect(func(index: int) -> void: choose_new_product(types[index], _new_size))
	choices.add_child(type_choice)
	var size_choice := OptionButton.new()
	size_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in range(sizes.size()):
		size_choice.add_item(ProductCatalog.get_size_name(sizes[index]), index)
	size_choice.select(sizes.find(_new_size))
	size_choice.item_selected.connect(func(index: int) -> void: choose_new_product(_new_type, sizes[index]))
	choices.add_child(size_choice)
	var racks: int = ProductCatalog.get_racks(_new_size)
	var split: Array[int] = ProductCatalog.get_split(_new_type)
	_list.add_child(_muted_label("%s puntos (diseño %d %%, programación %d %%, pruebas %d %%) · al lanzarlo usa %d %s · hasta %s al día" % [
		MoneyFormat.format(ProductCatalog.get_points(_new_size)).trim_prefix("$"), split[0], split[1], split[2], racks, "rack" if racks == 1 else "racks",
		MoneyFormat.format(ProductCatalog.get_daily_income(_new_size))]))
	var actions := HBoxContainer.new()
	_list.add_child(actions)
	_start_button = Button.new()
	_start_button.text = "Empezar"
	var problem: String = Products.start_problem()
	_start_button.disabled = not problem.is_empty()
	_start_button.pressed.connect(func() -> void: _status_label.text = Products.start(_new_type, _new_size)["message"])
	actions.add_child(_start_button)
	if not problem.is_empty():
		_list.add_child(_muted_label(problem))
	_list.add_child(HSeparator.new())

	var developing: Array[Dictionary] = Products.get_in_development()
	if Products.get_project(_confirming_abandon).is_empty():
		_confirming_abandon = 0
	if Products.get_product(_confirming_retire).is_empty():
		_confirming_retire = 0
	_add_section("En desarrollo (%d) · proyectos en curso %d de %d" % [developing.size(), Projects.get_project_count(),
		Projects.get_contract_limit()])
	if developing.is_empty():
		_list.add_child(_muted_label("Ningún producto en desarrollo."))
	for product: Dictionary in developing:
		_add_product(product)

	var launched: Array[Dictionary] = Products.get_launched()
	_add_section("Lanzados (%d) · racks %d de %d · %s al día" % [launched.size(), Products.get_used_racks(),
		OfficeState.get_server_capacity(), MoneyFormat.format(Products.get_total_daily_income())])
	if launched.is_empty():
		_list.add_child(_muted_label("Ningún producto lanzado. Un producto terminado se lanza con sus racks libres."))
	for product: Dictionary in launched:
		_add_launched(product)


func _add_product(product: Dictionary) -> void:
	var product_id: int = product["id"]
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var days: int = GameClock.get_day_count() - int(product["started_day"])
	info.text = "%s · %s" % [Products.describe_title(product), "empezado hoy" if days == 0 else "hace %d %s" % [days, "día" if days == 1 else "días"]]
	_list.add_child(info)
	_add_project_work(product_id, product)
	if Production.is_finished(product):
		var actions := HBoxContainer.new()
		_list.add_child(actions)
		var launch := Button.new()
		launch.text = "Lanzar (calidad %d %%)" % roundi(Products.get_quality(product) * 100.0)
		var problem: String = Products.launch_problem(product_id)
		launch.disabled = not problem.is_empty()
		launch.pressed.connect(func() -> void: _status_label.text = Products.launch(product_id)["message"])
		actions.add_child(launch)
		_launch_buttons[product_id] = launch
		if not problem.is_empty():
			_list.add_child(_muted_label(problem))
	_list.add_child(HSeparator.new())


func _add_launched(product: Dictionary) -> void:
	var product_id: int = product["id"]
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "%s · %s" % [Products.describe_title(product), Products.describe_phase(product)]
	_list.add_child(info)
	_list.add_child(_muted_label("%s usuarios · %s al día · calidad %d %%" % [MoneyFormat.format(Products.get_users(product)).trim_prefix("$"),
		MoneyFormat.format(Products.get_daily_income(product)), roundi(float(product["quality"]) * 100.0)]))
	var bugs: int = int(product["production_bugs"])
	if bugs > 0:
		_list.add_child(_muted_label("%d %s en producción: pierde %d %% de los usuarios hasta que una actualización %s." % [bugs,
			"error" if bugs == 1 else "errores", roundi(float(product["bug_loss"]) * 100.0), "lo corrija" if bugs == 1 else "los corrija"]))
	if not Products.get_supported_ids().has(product_id):
		_list.add_child(_muted_label("Sin racks suficientes en la Sala de servidores: tiene la mitad de los usuarios."))
	if product.has("update"):
		_list.add_child(_muted_label("Actualización en curso (%s puntos):" % MoneyFormat.format(int(product["update"]["total_points"])).trim_prefix("$")))
		_add_project_work(product_id, product["update"])
	else:
		var actions := HBoxContainer.new()
		_list.add_child(actions)
		var update := Button.new()
		update.text = "Actualizar"
		var problem: String = Products.update_problem(product_id)
		update.disabled = not problem.is_empty()
		update.pressed.connect(func() -> void: _status_label.text = Products.start_update(product_id)["message"])
		actions.add_child(update)
		_update_buttons[product_id] = update
		if _confirming_retire == product_id:
			var question := _muted_label("¿Retirarlo? Deja de dar ingreso.")
			question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			actions.add_child(question)
			_confirm_retire_button = Button.new()
			_confirm_retire_button.text = "Sí, retirar"
			_confirm_retire_button.pressed.connect(func() -> void:
				_confirming_retire = 0
				_status_label.text = Products.retire(product_id)["message"])
			actions.add_child(_confirm_retire_button)
			var keep := Button.new()
			keep.text = "No"
			keep.pressed.connect(func() -> void:
				_confirming_retire = 0
				_refresh())
			actions.add_child(keep)
		else:
			var retire := Button.new()
			retire.text = "Retirar"
			retire.pressed.connect(func() -> void:
				_confirming_retire = product_id
				_refresh())
			actions.add_child(retire)
			_retire_buttons[product_id] = retire
		if not problem.is_empty() and Projects.get_project_count() >= Projects.get_contract_limit():
			_list.add_child(_muted_label("Para actualizarlo hace falta lugar en el tope de proyectos."))
	_list.add_child(HSeparator.new())


# Quién lleva un producto (desarrollo o actualización), avance, estado y Abandonar con confirmación.
func _add_project_work(product_id: int, project: Dictionary) -> void:
	var owner_row := HBoxContainer.new()
	_list.add_child(owner_row)
	var owner_label := Label.new()
	owner_label.text = "Lo lleva:"
	owner_row.add_child(owner_label)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# El id va en la metadata: add_item con id −1 (NO_TEAM) pondría uno automático.
	var owners: Array[int] = [Projects.NO_TEAM, Projects.CEO_TEAM]
	choice.add_item("Nadie")
	choice.add_item("El CEO")
	for team: Dictionary in Staff.teams:
		if not (team["members"] as Array).is_empty():
			choice.add_item(team["name"])
			owners.append(int(team["id"]))
	for index: int in range(owners.size()):
		choice.set_item_metadata(index, owners[index])
	choice.select(maxi(0, owners.find(int(project["team_id"]))))
	choice.item_selected.connect(func(index: int) -> void:
		_status_label.text = Products.assign(product_id, int(choice.get_item_metadata(index)))["message"])
	owner_row.add_child(choice)
	_owner_choices[product_id] = choice
	_product_bars[product_id] = _add_phase_rows(project)
	_list.add_child(_muted_label(Projects.describe_bugs(project) + "."))
	var is_update: bool = project.has("product_id")
	var state: String
	var pending: int = int(project["bugs_found"])
	if Production.is_finished(project) and pending > 0:
		state = "Terminado, con %d %s por corregir: los programadores siguen." % [pending, "error" if pending == 1 else "errores"]
	elif Production.is_finished(project):
		state = "Terminado: listo para lanzar. Si el equipo tiene QA, sigue buscando errores."
	elif int(project["team_id"]) == Projects.NO_TEAM:
		state = "Nadie lo lleva: elige quién lo lleva."
	else:
		var rate: float = Projects.get_hourly_rate(project)
		state = "Ahora rinde %s puntos por hora." % String.num(rate, 1).trim_suffix(".0") if rate > 0.0 \
			else "Ahora nadie está trabajando en él."
	_list.add_child(_muted_label(state))
	var actions := HBoxContainer.new()
	_list.add_child(actions)
	if _confirming_abandon == product_id:
		var question := _muted_label("¿Abandonar la actualización? Se pierde lo hecho." if is_update
			else "¿Abandonarlo? Se pierde todo lo hecho.")
		question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(question)
		_confirm_abandon_button = Button.new()
		_confirm_abandon_button.text = "Sí, abandonar"
		_confirm_abandon_button.pressed.connect(func() -> void:
			_confirming_abandon = 0
			_status_label.text = Products.abandon(product_id)["message"])
		actions.add_child(_confirm_abandon_button)
		var keep := Button.new()
		keep.text = "No"
		keep.pressed.connect(func() -> void:
			_confirming_abandon = 0
			_refresh())
		actions.add_child(keep)
	else:
		var abandon := Button.new()
		abandon.text = "Abandonar la actualización" if is_update else "Abandonar"
		abandon.pressed.connect(func() -> void:
			_confirming_abandon = product_id
			_refresh())
		actions.add_child(abandon)
		_abandon_buttons[product_id] = abandon


func _add_delivery_actions(contract: Dictionary) -> void:
	var contract_id: int = contract["id"]
	# Solo los errores conocidos: los ocultos también descuentan, pero no se ven.
	var preview: Dictionary = Projects.preview_delivery(contract, true)
	var change: float = float(preview["reputation_change"])
	var penalties: Array[String] = []
	if float(preview["late_penalty"]) > 0.0:
		penalties.append("atraso −%d%%" % roundi(float(preview["late_penalty"]) * 100.0))
	if float(preview["bug_penalty"]) > 0.0:
		penalties.append("errores −%d%%" % roundi(float(preview["bug_penalty"]) * 100.0))
	_list.add_child(_muted_label("Si entregas hoy: %s; cobras hasta %s%s · reputación hasta %s%s. Los errores que nadie encontró también descuentan." % [preview["result"],
		MoneyFormat.format(preview["paid"]), " (%s)" % ", ".join(penalties) if not penalties.is_empty() else "",
		"+" if change >= 0.0 else "−", String.num(absf(change), 2)]))
	var actions := HBoxContainer.new()
	_list.add_child(actions)
	if _confirming_cancel == contract_id:
		var advance: int = int(contract["advance"])
		var question := _muted_label("¿Cancelar? %sBaja la reputación." % (
			"Devuelves el anticipo de %s. " % MoneyFormat.format(advance) if advance > 0 else ""))
		question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(question)
		_confirm_cancel_button = Button.new()
		_confirm_cancel_button.text = "Sí, cancelar"
		_confirm_cancel_button.pressed.connect(func() -> void:
			_confirming_cancel = 0
			_status_label.text = Projects.cancel(contract_id)["message"])
		actions.add_child(_confirm_cancel_button)
		var keep := Button.new()
		keep.text = "No"
		keep.pressed.connect(func() -> void:
			_confirming_cancel = 0
			_refresh())
		actions.add_child(keep)
		return
	var deliver := Button.new()
	deliver.text = "Entregar"
	deliver.pressed.connect(func() -> void: _status_label.text = Projects.deliver(contract_id)["message"])
	actions.add_child(deliver)
	_deliver_buttons[contract_id] = deliver
	var cancel := Button.new()
	cancel.text = "Cancelar contrato"
	cancel.pressed.connect(func() -> void:
		_confirming_cancel = contract_id
		_refresh())
	actions.add_child(cancel)
	_cancel_buttons[contract_id] = cancel


func _add_offer(offer: Dictionary) -> void:
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var days_left: int = Projects.offer_days_left(offer)
	var expires: String = "caduca hoy" if days_left == 0 else ("caduca mañana" if days_left == 1 else "caduca en %d días" % days_left)
	info.text = "%s · %s\n%s\n%s" % [Projects.describe_title(offer), expires, Projects.describe_points(offer),
		Projects.describe_terms(offer)]
	_list.add_child(info)
	var actions := HBoxContainer.new()
	_list.add_child(actions)
	var offer_id: int = offer["id"]
	var accept := Button.new()
	accept.text = "Aceptar"
	var problem: String = Projects.accept_problem(offer_id)
	accept.disabled = not problem.is_empty()
	accept.tooltip_text = problem
	accept.pressed.connect(func() -> void: _status_label.text = Projects.accept(offer_id)["message"])
	actions.add_child(accept)
	_accept_buttons[offer_id] = accept
	var reject := Button.new()
	reject.text = "Rechazar"
	reject.pressed.connect(func() -> void: Projects.reject(offer_id))
	actions.add_child(reject)
	_reject_buttons[offer_id] = reject
	if not problem.is_empty():
		_list.add_child(_muted_label(problem))
	_list.add_child(HSeparator.new())


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionLabel"
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_list.add_child(label)


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label


## Botón «?» que abre la ayuda del panel.
func get_help_button() -> Button:
	return _help_button
