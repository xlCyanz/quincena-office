# Comprobación de la fase 6: la empresa de test_phase5 con rasgos, baños, almuerzo, pausas, candidatos
# e inversionista. La política suma desde el primer día dos Baños al sur de la Recepción (un inodoro
# cada 10) y desde Startup la Sala de descanso completa al otro lado de la entrada. Criterio: llega
# a la bolsa sin quebrar; baños y Sala de descanso pagan su costo; los rasgos se notan sin decidir
# la partida (comparaciones de 30 días desde Mediana empresa: tal cual, sin esos muebles y sin rasgos).
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=phase6
extends "res://tests/suites/test_phase5.gd"

## Semilla propia y días de cada comparación desde Mediana empresa.
const SEED_6: int = 59
const COMPARE_DAYS: int = 30
## Franja de los baños (x 1 a 2, desde la fila 8): Baño A filas 8 a 12, Baño B 13 a 17.
const BATH_XS: Array[int] = [1, 2]
const BATH_DEPTH: int = 10
const SINKS: Array[Vector2i] = [Vector2i(1, 8), Vector2i(1, 13)]
## Inodoros en orden: la columna de la izquierda (la derecha es el paso) y el fondo.
const TOILET_CELLS: Array[Vector2i] = [Vector2i(1, 9), Vector2i(1, 10), Vector2i(1, 11), Vector2i(1, 12),
	Vector2i(1, 14), Vector2i(1, 15), Vector2i(1, 16), Vector2i(1, 17), Vector2i(2, 17)]
## Franja de la Sala de descanso (x 4 a 5, filas 8 a 22): la columna 4 es el paso.
const BREAK_XS: Array[int] = [4, 5]
const BREAK_DEPTH: int = 15
## [mueble, casilla, giro]; mesas y sofás de 2×1 van de pie (giro 1 y 3).
const BREAK_ITEMS: Array = [
	["coffee_maker", Vector2i(5, 8), 3], ["fridge", Vector2i(5, 9), 3], ["microwave", Vector2i(5, 10), 3],
	["water_dispenser", Vector2i(5, 11), 3], ["vending_machine", Vector2i(5, 12), 3],
	["dining_table", Vector2i(5, 13), 3], ["dining_table", Vector2i(5, 15), 3],
	["sofa", Vector2i(5, 17), 3], ["sofa", Vector2i(5, 19), 3], ["ping_pong", Vector2i(4, 21), 0],
]
## Meta de meses hasta la bolsa: ~16 contra ~20 de la fase 5 (el ánimo retiene y los rasgos suman).
## AMENITIES: los muebles que quita la comparación.
const TARGET_MONTHS_6: Array[int] = [12, 30]
const AMENITIES: Array[String] = ["toilet", "sink", "coffee_maker", "fridge", "microwave", "water_dispenser",
	"vending_machine", "dining_table", "sofa", "ping_pong"]

var _bath_built: bool = false
var _break_built: bool = false
## Lo que costó armar baños y Sala de descanso (terreno, paredes y muebles).
var _amenity_cost: int = 0
## Puntos vistos en cada proyecto, para sumar lo producido en una ventana.
var _seen_points: Dictionary[String, float] = {}
var _investor_accepted: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_target_months = TARGET_MONTHS_6
	Staff.bathrooms_enabled = true
	Staff.company_hiring_enabled = true
	Bank.investor_enabled = true
	EventBus.emergency_loan_offered.connect(func(_offer: Dictionary) -> void: Bank.accept_emergency())
	EventBus.game_over.connect(func(_stats: Dictionary) -> void: _game_over_day = GameClock.get_day_count())
	EventBus.stage_changed.connect(func(stage: int) -> void: _stage_months[stage] = Economy.get_current_month())
	EventBus.event_started.connect(func(_card: Dictionary) -> void: _events_seen += 1)
	_check_growth()
	if Company.stage >= 3 and not Bank.game_over:
		_check_amenities_and_traits()
		_check_ipo_run()
		print("  fase 6: baños y Sala de descanso costaron %s · %d inodoros · inversionistas aceptados: %d · rasgos descubiertos %d de %d" % [
			MoneyFormat.format(_amenity_cost), OfficeState.count_working_toilets(), _investor_accepted, _known_traits(), _all_traits()])
	finished.emit(_failures, _checks)


# Con todos los rasgos (test_phase4 los quitaba).
func _drop_production_traits(_employee: Dictionary) -> void:
	pass


# El ambicioso se molesta si espera un ascenso que la política no da: lo retiene con aumentos.
func _forget_promotion_waits() -> void:
	pass


func _play_day() -> void:
	if not Bank.game_over:
		_build_amenities()
	super._play_day()


func _answer_event() -> void:
	var investor: bool = not Events.card.is_empty() and String(Events.card.get("event_id", "")) == "investor"
	super._answer_event()
	if investor and not Bank.investor.is_empty():
		_investor_accepted += 1


# --- Baños y Sala de descanso -----------------------------------------------------


func _build_amenities() -> void:
	if not _bath_built:
		_build_bathrooms()
	if _bath_built:
		_add_toilets()
	if not _break_built and _bath_built and Company.stage >= 1:
		_build_break_room()


# Franja al sur de la Recepción: la Recepción crece hacia ella y unas paredes la parten en dos Baños con lavamanos.
func _build_bathrooms() -> void:
	var offset: int = BATH_XS[0] - OfficeState.lot_rect.position.x
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [_wall(1, 7, y), _wall(2, 7, y, ConstructionCatalog.DOOR), _wall(1, 12, y), _wall(2, 12, y, ConstructionCatalog.DOOR)]
	var cost: int = int(_builder.quote_land(Builder.SIDE_SOUTH, BATH_XS.size(), BATH_DEPTH, offset)["cost"]) \
		+ 500 + SINKS.size() * FurnitureCatalog.get_price("sink") + FurnitureCatalog.get_price("toilet")
	if Economy.balance < cost + 1000 + _reserve_months * _monthly_costs():
		return
	var before: int = Economy.balance
	_ok(_builder.buy_land(Builder.SIDE_SOUTH, BATH_XS.size(), BATH_DEPTH, offset), "terreno de los baños")
	_ok(_builder.apply(walls), "paredes de los baños")
	for sink: Vector2i in SINKS:
		_ok(_builder.mark_room(OfficeState.BATHROOM, sink + Vector2i(1, 0)), "Baño en %s" % sink)
		_ok(_builder.place("sink", sink, 0), "lavamanos en %s" % sink)
	_amenity_cost += before - Economy.balance
	_bath_built = true


# Un inodoro más mientras falten para la plantilla y el CEO (como si estuvieran todos).
func _add_toilets() -> void:
	var needed: int = Staff.get_toilets_needed(Staff.employees.size() + 1)
	var price: int = FurnitureCatalog.get_price("toilet")
	while OfficeState.count_working_toilets() < needed and Economy.balance >= price:
		var free: Array[Vector2i] = TOILET_CELLS.filter(func(cell: Vector2i) -> bool: return OfficeState.find_furniture_at(cell) < 0)
		if free.is_empty():
			return
		_ok(_builder.place("toilet", free[0], 0), "inodoro en %s" % free[0])
		_amenity_cost += price


func _build_break_room() -> void:
	var offset: int = BREAK_XS[0] - OfficeState.lot_rect.position.x
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [_wall(4, 7, y, ConstructionCatalog.DOOR), _wall(5, 7, y)]
	var cost: int = int(_builder.quote_land(Builder.SIDE_SOUTH, BREAK_XS.size(), BREAK_DEPTH, offset)["cost"]) + 500
	for item: Array in BREAK_ITEMS:
		cost += FurnitureCatalog.get_price(item[0])
	if Economy.balance < cost + _reserve_months * _monthly_costs():
		return
	var before: int = Economy.balance
	_ok(_builder.buy_land(Builder.SIDE_SOUTH, BREAK_XS.size(), BREAK_DEPTH, offset), "terreno de la Sala de descanso")
	_ok(_builder.apply(walls), "paredes de la Sala de descanso")
	_ok(_builder.mark_room(OfficeState.BREAK_ROOM, Vector2i(4, 9)), "Sala de descanso")
	for item: Array in BREAK_ITEMS:
		_ok(_builder.place(item[0], item[1], item[2]), "%s en %s" % [item[0], item[1]])
	_amenity_cost += before - Economy.balance
	_break_built = true


# --- Comparaciones ----------------------------------------------------------------


# Desde Mediana empresa: COMPARE_DAYS días tal cual, sin baños ni Sala de descanso y sin rasgos;
# después vuelve a la empresa guardada.
func _check_amenities_and_traits() -> void:
	_expect(_bath_built and _break_built, "la política armó baños y Sala de descanso")
	_expect(not OfficeState.get_working_room(OfficeState.BREAK_ROOM).is_empty() and OfficeState.get_lunch_seats() > 0,
		"la Sala de descanso funciona con almuerzo")
	var policy: Dictionary = {"servers": _servers_built, "pending": _pending.duplicate(), "built": _built, "done": _done_day.duplicate()}
	SaveManager.save_game("slot_5")
	var full: Dictionary = _window()
	SaveManager.load_game("slot_5")
	var refund: int = Economy.balance
	for item: Dictionary in OfficeState.furniture.duplicate():
		if AMENITIES.has(String(item["id"])):
			_builder.sell_furniture_at(item["cell"])
	refund = Economy.balance - refund
	_expect(OfficeState.count_working_toilets() == 0 and OfficeState.get_working_room(OfficeState.BREAK_ROOM).is_empty(),
		"sin los muebles no funcionan")
	var bare: Dictionary = _window()
	SaveManager.load_game("slot_5")
	for employee: Dictionary in Staff.employees:
		(employee["traits"] as Array).clear()
	var plain: Dictionary = _window()
	SaveManager.load_game("slot_5")
	_servers_built = policy["servers"]
	_pending = policy["pending"]
	_built = policy["built"]
	_done_day = policy["done"]
	print("  %d días desde Mediana empresa (%d empleados): puntos · ingresos · ánimo medio · energía media" % [COMPARE_DAYS, Staff.employees.size()])
	for row: Array in [["tal cual", full], ["sin baños ni Sala de descanso", bare], ["sin rasgos", plain]]:
		var result: Dictionary = row[1]
		print("    %s: %d · %s · %.0f · %.0f" % [row[0], roundi(result["points"]), MoneyFormat.format(result["income"]), result["mood"], result["energy"]])
	# Valor de los puntos de más, al precio por punto de la empresa tal cual.
	var per_point: float = float(full["income"]) / maxf(1.0, float(full["points"]))
	var gain: int = roundi((float(full["points"]) - float(bare["points"])) * per_point)
	print("    baños y Sala de descanso: %+d puntos ≈ %s en %d días contra %s que costaron (los muebles se revenden por %s)" % [
		roundi(full["points"] - bare["points"]), MoneyFormat.format(gain), COMPARE_DAYS, MoneyFormat.format(_amenity_cost), MoneyFormat.format(refund)])
	_expect(gain >= _amenity_cost, "baños y Sala de descanso compensan su costo en %d días: %s contra %s" % [
		COMPARE_DAYS, MoneyFormat.format(gain), MoneyFormat.format(_amenity_cost)])
	var traits_effect: float = float(full["points"]) / maxf(1.0, float(plain["points"])) - 1.0
	print("    rasgos: %+.1f %% de puntos" % (traits_effect * 100.0))
	_expect(absf(traits_effect) >= 0.01, "los rasgos se notan: %+.1f %%" % (traits_effect * 100.0))
	_expect(absf(traits_effect) <= 0.15, "sin decidir solos la partida: %+.1f %%" % (traits_effect * 100.0))


# COMPARE_DAYS días sin contratar ni construir: puntos producidos, ingresos y ánimo y energía medios al final.
func _window() -> Dictionary:
	Staff.set_seed(SEED_6)
	Projects.set_seed(SEED_6)
	Products.set_seed(SEED_6)
	_seen_points.clear()
	_note_points()
	var points: float = 0.0
	var start: int = Economy.get_current_month()
	var earned: Dictionary[int, int] = {}
	for day: int in range(COMPARE_DAYS):
		var month: int = Economy.get_current_month()
		_manage_contracts()
		GameClock.fast_forward_hours(9)
		if Staff.ceo_at_work:
			Staff.set_ceo_at_work(false)
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - 9)
		points += _note_points()
		earned[month] = _income_of(month)
		earned[Economy.get_current_month()] = _income_of(Economy.get_current_month())
	var income: int = 0
	for month: int in earned:
		income += earned[month]
	var mood: float = 0.0
	var energy: float = 0.0
	for employee: Dictionary in Staff.employees:
		mood += float(employee["mood"])
		energy += float(employee["energy"])
	var count: int = maxi(1, Staff.employees.size())
	return {"points": points, "income": income, "mood": mood / count, "energy": energy / count, "start": start}


func _income_of(month: int) -> int:
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	var income: int = totals.get(Products.CONCEPT_INCOME, 0)
	for concept: String in Bank.get_income_concepts():
		income += totals.get(concept, 0)
	return income


# Lo que avanzó cada proyecto desde la última vez (errores corregidos a 3 puntos).
func _note_points() -> float:
	var added: float = 0.0
	var now: Dictionary[String, float] = {}
	for contract: Dictionary in Projects.contracts:
		now["c%d" % contract["id"]] = _project_points(contract)
	for product: Dictionary in Products.get_in_development():
		now["p%d" % product["id"]] = _project_points(product)
	for product: Dictionary in Products.get_launched():
		if product.has("update"):
			now["u%d" % product["id"]] = _project_points(product["update"])
	for key: String in now:
		added += maxf(0.0, now[key] - _seen_points.get(key, 0.0))
	_seen_points = now
	return added


func _project_points(project: Dictionary) -> float:
	var done: float = 0.0
	for phase: String in ContractCatalog.PHASES:
		done += float(project["progress"][phase])
	return done + 3.0 * int(project.get("bugs_fixed", 0))


func _known_traits() -> int:
	var known: int = 0
	for employee: Dictionary in Staff.employees:
		known += (employee.get("known_traits", []) as Array).size()
	return known


func _all_traits() -> int:
	var total: int = 0
	for employee: Dictionary in Staff.employees:
		total += (employee.get("traits", []) as Array).size()
	return total
