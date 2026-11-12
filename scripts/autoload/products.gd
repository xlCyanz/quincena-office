# Productos propios (diseño, 7.5 y 13.5; hito 41): proyectos de la empresa sin cliente,
# sin plazo y sin anticipo. Se desarrollan igual que un contrato (fases, puntos por hora
# y errores con Production) y la empresa los paga con los sueldos hasta lanzarlos
# (el lanzamiento, los usuarios y el ingreso diario llegan en el hito 42).
#
# Un producto es {"id", "name", "type", "size", "points": {"design", "programming",
# "testing"}, "total_points", "progress", "bugs_hidden", "bugs_found", "bugs_fixed",
# "fix_progress", "team_id", "worked_by", "state", "started_day"}; state es "development"
# mientras se hace. team_id usa los mismos valores que un contrato (Projects.CEO_TEAM,
# Projects.NO_TEAM o el id de un equipo).
#
# Se empieza desde la etapa de data/products.json con una Sala de servidores que
# funcione. Los productos en desarrollo y los contratos comparten el tope de proyectos
# en curso (Projects.get_contract_limit) y un equipo lleva un proyecto a la vez: dar un
# producto a un equipo suelta su contrato y al revés (Projects.release_team,
# release_team). Todo el azar (los errores) sale de _rng, cuyo estado se guarda.
extends Node

const STATE_DEVELOPMENT: String = "development"

var products: Array[Dictionary] = []

var _next_id: int = 1
## Cuántos productos se empezaron (elige el nombre del siguiente).
var _started_count: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(func(_hour: int) -> void: _produce())
	EventBus.staff_changed.connect(_drop_missing_teams)


## Prepara los productos de una partida nueva: ninguno.
func new_game() -> void:
	products.clear()
	_next_id = 1
	_started_count = 0
	_rng.randomize()
	EventBus.products_changed.emit()


## Fija la semilla del azar (las pruebas la usan para tener resultados repetibles).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Por qué no se puede empezar un producto ahora ("" si se puede).
func start_problem() -> String:
	if Company.stage < ProductCatalog.get_min_stage():
		return "Los productos propios se desbloquean en %s." % Company.get_stage_name(ProductCatalog.get_min_stage())
	if OfficeState.get_server_room().is_empty():
		return "Para desarrollar un producto hace falta una Sala de servidores que funcione."
	return Projects.limit_problem()


## Empieza un producto de ese tipo y tamaño y se lo da al primer equipo libre (o al CEO).
## Devuelve {"ok", "message", "id"}.
func start(type_id: String, size: String) -> Dictionary:
	if not ProductCatalog.get_type_ids().has(type_id) or not ProductCatalog.get_size_ids().has(size):
		return {"ok": false, "message": "Ese producto no existe.", "id": 0}
	var problem: String = start_problem()
	if not problem.is_empty():
		return {"ok": false, "message": problem, "id": 0}
	var total: int = ProductCatalog.get_points(size)
	var split: Array[int] = ProductCatalog.get_split(type_id)
	var design: int = roundi(total * split[0] / 100.0)
	var programming: int = roundi(total * split[1] / 100.0)
	var product: Dictionary = {
		"id": _next_id, "name": ProductCatalog.get_product_name(_started_count), "type": type_id, "size": size,
		"points": {"design": design, "programming": programming, "testing": total - design - programming},
		"total_points": total, "progress": {"design": 0.0, "programming": 0.0, "testing": 0.0},
		"bugs_hidden": 0, "bugs_found": 0, "bugs_fixed": 0, "fix_progress": 0.0,
		"team_id": Projects.first_free_team(), "worked_by": [], "state": STATE_DEVELOPMENT,
		"started_day": GameClock.get_day_count(),
	}
	_next_id += 1
	_started_count += 1
	products.append(product)
	var message: String = "Empezaste %s: %s." % [describe_title(product), Projects.describe_owner(product)]
	EventBus.products_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message, "id": product["id"]}


## Le da un producto a un equipo (o al CEO, o a nadie con Projects.NO_TEAM). Un equipo
## lleva un proyecto a la vez: si llevaba otro producto o un contrato, ese queda sin
## equipo. Devuelve {"ok", "message"}.
func assign(product_id: int, team_id: int) -> Dictionary:
	var product: Dictionary = get_product(product_id)
	if product.is_empty():
		return {"ok": false, "message": "Ese producto ya no está."}
	if team_id > Projects.CEO_TEAM and Staff.get_team(team_id).is_empty():
		return {"ok": false, "message": "Ese equipo ya no está."}
	if team_id != Projects.NO_TEAM:
		var previous: Dictionary = get_product_of(team_id)
		if not previous.is_empty() and previous["id"] != product_id:
			previous["team_id"] = Projects.NO_TEAM
		Projects.release_team(team_id)
	product["team_id"] = team_id
	EventBus.products_changed.emit()
	return {"ok": true, "message": "%s: %s." % [describe_title(product), Projects.describe_owner(product)]}


## Abandona un producto en desarrollo: se pierde lo hecho, sin otro costo.
func abandon(product_id: int) -> Dictionary:
	var product: Dictionary = get_product(product_id)
	if product.is_empty():
		return {"ok": false, "message": "Ese producto ya no está."}
	products.erase(product)
	var message: String = "Abandonaste %s; se pierde lo hecho." % describe_title(product)
	EventBus.products_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Suelta el producto que lleva un equipo (queda sin equipo); lo usa Projects al darle un
## contrato a ese equipo.
func release_team(team_id: int) -> void:
	var product: Dictionary = get_product_of(team_id)
	if not product.is_empty():
		product["team_id"] = Projects.NO_TEAM
		EventBus.products_changed.emit()


func get_product(product_id: int) -> Dictionary:
	for product: Dictionary in products:
		if product["id"] == product_id:
			return product
	return {}


## Producto en desarrollo que lleva un equipo (o el CEO con Projects.CEO_TEAM), o vacío.
func get_product_of(team_id: int) -> Dictionary:
	if team_id == Projects.NO_TEAM:
		return {}
	for product: Dictionary in get_in_development():
		if int(product["team_id"]) == team_id:
			return product
	return {}


func get_in_development() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for product: Dictionary in products:
		if product["state"] == STATE_DEVELOPMENT:
			list.append(product)
	return list


## Productos en desarrollo (cuentan para el tope de proyectos en curso).
func get_development_count() -> int:
	return get_in_development().size()


## "Nimbo · App móvil pequeña".
static func describe_title(product: Dictionary) -> String:
	return "%s · %s %s" % [product["name"], ProductCatalog.get_type_name(product["type"]),
		ProductCatalog.get_size_name(product["size"]).to_lower()]


func export_state() -> Dictionary:
	return {"products": products.duplicate(true), "next_id": _next_id, "started_count": _started_count,
		"rng_state": str(_rng.state)}


## Restaura los productos de una partida guardada. Sin datos (partidas anteriores al
## hito 41) queda sin productos.
func import_state(state: Dictionary) -> void:
	products.clear()
	for saved: Dictionary in state.get("products", []):
		var product: Dictionary = saved.duplicate(true)
		var points: Dictionary = saved.get("points", {})
		var progress: Dictionary = saved.get("progress", {})
		product["id"] = int(saved.get("id", 0))
		product["points"] = {}
		product["progress"] = {}
		for phase: String in ContractCatalog.PHASES:
			product["points"][phase] = int(points.get(phase, 0))
			product["progress"][phase] = float(progress.get(phase, 0.0))
		product["total_points"] = int(saved.get("total_points", 0))
		for key: String in Projects.BUG_KEYS:
			product[key] = int(saved.get(key, 0))
		product["fix_progress"] = float(saved.get("fix_progress", 0.0))
		var team_id: int = int(saved.get("team_id", Projects.NO_TEAM))
		product["team_id"] = team_id if team_id <= Projects.CEO_TEAM or not Staff.get_team(team_id).is_empty() else Projects.NO_TEAM
		var worked_by: Array[String] = []
		for key: Variant in saved.get("worked_by", []):
			worked_by.append(String(key))
		product["worked_by"] = worked_by
		product["state"] = String(saved.get("state", STATE_DEVELOPMENT))
		product["started_day"] = int(saved.get("started_day", 0))
		products.append(product)
	_next_id = int(state.get("next_id", products.size() + 1))
	_started_count = int(state.get("started_count", products.size()))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	EventBus.products_changed.emit()


# Suma la hora que acaba de terminar a cada producto en desarrollo.
func _produce() -> void:
	var ended: int = Staff.get_absolute_hour() - 1
	var changed: bool = false
	for product: Dictionary in get_in_development():
		var workers: Array[Dictionary] = Projects.get_workers(product, ended)
		if workers.is_empty():
			continue
		var was_finished: bool = Production.is_finished(product)
		var done: Array[Dictionary] = Production.apply(product, workers)
		Production.handle_bugs(product, done, _rng)
		Production.note_workers(product, done)
		changed = true
		if not was_finished and Production.is_finished(product):
			EventBus.notice.emit("Terminado: %s. Listo para lanzar." % describe_title(product))
	if changed:
		EventBus.products_changed.emit()


# Los productos de un equipo que se borró quedan sin equipo.
func _drop_missing_teams() -> void:
	var changed: bool = false
	for product: Dictionary in products:
		var team_id: int = int(product["team_id"])
		if team_id > Projects.CEO_TEAM and Staff.get_team(team_id).is_empty():
			product["team_id"] = Projects.NO_TEAM
			changed = true
	if changed:
		EventBus.products_changed.emit()
