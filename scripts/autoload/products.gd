# Productos propios (diseño, 7.5 y 13.5; hito 41): proyectos de la empresa sin cliente,
# sin plazo y sin anticipo. Se desarrollan igual que un contrato (fases, puntos por hora
# y errores con Production) y la empresa los paga con los sueldos hasta lanzarlos.
#
# Un producto es {"id", "name", "type", "size", "points": {"design", "programming",
# "testing"}, "total_points", "progress", "bugs_hidden", "bugs_found", "bugs_fixed",
# "fix_progress", "team_id", "worked_by", "state", "started_day", "design_done",
# "design_skill"}; state es "development" mientras se hace y "launched" desde que se
# lanza. team_id usa los mismos valores que un contrato (Projects.CEO_TEAM,
# Projects.NO_TEAM o el id de un equipo). design_done y design_skill suman los puntos de
# diseño y esos puntos por el valor del nivel de quien los hizo (la calidad).
#
# Lanzado (hito 42) suma "launched_day", "quality" (0 a 1), "curve" (parte del pico de
# usuarios por el ciclo de vida), "phase" (growth, plateau o decline), "phase_days",
# "production_bugs", "bug_loss" (parte de los usuarios perdida por esos errores) y, mientras
# se actualiza, "update": un proyecto como el de desarrollo ({"product_id", "points",
# "progress", errores, "team_id", "worked_by"}) que cuenta para el tope. Cada día
# (day_changed) avanza el ciclo y cobra «Ingreso de productos». Los racks de la Sala de
# servidores se reparten en orden de lanzamiento (get_supported_ids).
#
# Se empieza desde la etapa de data/products.json con una Sala de servidores que
# funcione. Los productos en desarrollo y los contratos comparten el tope de proyectos
# en curso (Projects.get_contract_limit) y un equipo lleva un proyecto a la vez: dar un
# producto a un equipo suelta su contrato y al revés (Projects.release_team,
# release_team). Todo el azar (los errores) sale de _rng, cuyo estado se guarda.
extends Node

const STATE_DEVELOPMENT: String = "development"
const STATE_LAUNCHED: String = "launched"
const PHASE_GROWTH: String = "growth"
const PHASE_PLATEAU: String = "plateau"
const PHASE_DECLINE: String = "decline"
const CONCEPT_INCOME: String = "Ingreso de productos"

var products: Array[Dictionary] = []

var _next_id: int = 1
## Cuántos productos se empezaron (elige el nombre del siguiente).
var _started_count: int = 0
## Cuántos productos se lanzaron en la partida (lo pide Mediana empresa).
var launched_count: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(func(_hour: int) -> void: _produce())
	EventBus.staff_changed.connect(_drop_missing_teams)
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: _live_day())


## Prepara los productos de una partida nueva: ninguno.
func new_game() -> void:
	products.clear()
	_next_id = 1
	_started_count = 0
	launched_count = 0
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
		"started_day": GameClock.get_day_count(), "design_done": 0.0, "design_skill": 0.0,
	}
	_next_id += 1
	_started_count += 1
	products.append(product)
	var message: String = "Empezaste %s: %s." % [describe_title(product), Projects.describe_owner(product)]
	EventBus.products_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message, "id": product["id"]}


## Le da un producto (en desarrollo o su actualización) a un equipo (o al CEO, o a nadie
## con Projects.NO_TEAM). Un equipo lleva un proyecto a la vez: si llevaba otro producto o
## un contrato, ese queda sin equipo. Devuelve {"ok", "message"}.
func assign(product_id: int, team_id: int) -> Dictionary:
	var project: Dictionary = get_project(product_id)
	if project.is_empty():
		return {"ok": false, "message": "Ese producto ya no está en desarrollo."}
	if team_id > Projects.CEO_TEAM and Staff.get_team(team_id).is_empty():
		return {"ok": false, "message": "Ese equipo ya no está."}
	if team_id != Projects.NO_TEAM:
		var previous: Dictionary = get_product_of(team_id)
		if not previous.is_empty() and previous != project:
			previous["team_id"] = Projects.NO_TEAM
		Projects.release_team(team_id)
	project["team_id"] = team_id
	EventBus.products_changed.emit()
	return {"ok": true, "message": "%s: %s." % [describe_project(project), Projects.describe_owner(project)]}


## Proyecto en curso de un producto: el producto mismo en desarrollo o su actualización.
func get_project(product_id: int) -> Dictionary:
	var product: Dictionary = get_product(product_id)
	if product.is_empty():
		return {}
	if product["state"] == STATE_DEVELOPMENT:
		return product
	return product.get("update", {})


## Abandona un producto en desarrollo, o la actualización de uno lanzado: se pierde lo
## hecho, sin otro costo (el producto lanzado sigue como estaba).
func abandon(product_id: int) -> Dictionary:
	var product: Dictionary = get_product(product_id)
	if product.is_empty() or get_project(product_id).is_empty():
		return {"ok": false, "message": "Ese producto no está en desarrollo."}
	var message: String
	if product["state"] == STATE_DEVELOPMENT:
		products.erase(product)
		message = "Abandonaste %s; se pierde lo hecho." % describe_title(product)
	else:
		product.erase("update")
		message = "Abandonaste la actualización de %s." % product["name"]
	EventBus.products_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Por qué no se puede lanzar un producto ahora ("" si se puede).
func launch_problem(product_id: int) -> String:
	var product: Dictionary = get_product(product_id)
	if product.is_empty() or product["state"] != STATE_DEVELOPMENT:
		return "Ese producto no está en desarrollo."
	if not Production.is_finished(product):
		return "Todavía no está terminado."
	var free: int = get_free_racks()
	var needed: int = ProductCatalog.get_racks(product["size"])
	if free < needed:
		return "Para lanzarlo %s %d %s en la Sala de servidores y hay %d." % ["hace falta" if needed == 1 else "hacen falta",
			needed, "rack libre" if needed == 1 else "racks libres", free]
	return ""


## Lanza un producto terminado: deja de contar para el tope, ocupa sus racks y empieza a
## tener usuarios. Los errores que quedan (ocultos y encontrados) pasan a producción.
func launch(product_id: int) -> Dictionary:
	var problem: String = launch_problem(product_id)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var product: Dictionary = get_product(product_id)
	product["quality"] = get_quality(product)
	product["production_bugs"] = int(product["bugs_hidden"]) + int(product["bugs_found"])
	product["bug_loss"] = 0.0
	product["curve"] = ProductCatalog.get_lifecycle("start")
	product["phase"] = PHASE_GROWTH
	product["phase_days"] = 0
	product["launched_day"] = GameClock.get_day_count()
	product["team_id"] = Projects.NO_TEAM
	product["state"] = STATE_LAUNCHED
	launched_count += 1
	var message: String = "Lanzaste %s: calidad %d %%%s." % [describe_title(product), roundi(product["quality"] * 100.0),
		"" if product["production_bugs"] == 0 else ", con %d %s" % [product["production_bugs"],
			"error" if product["production_bugs"] == 1 else "errores"]]
	EventBus.products_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Por qué no se puede empezar la actualización de un producto ("" si se puede).
func update_problem(product_id: int) -> String:
	var product: Dictionary = get_product(product_id)
	if product.is_empty() or product["state"] != STATE_LAUNCHED:
		return "Solo se actualiza un producto lanzado."
	if product.has("update"):
		return "Ya se está actualizando."
	return Projects.limit_problem()


## Empieza la actualización de un producto lanzado: un proyecto con una parte de sus puntos
## que se le da al primer equipo libre (o al CEO). Mientras tanto sigue dando ingreso.
func start_update(product_id: int) -> Dictionary:
	var problem: String = update_problem(product_id)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var product: Dictionary = get_product(product_id)
	var total: int = roundi(int(product["total_points"]) * ProductCatalog.get_update_ratio())
	var split: Array[int] = ProductCatalog.get_split(product["type"])
	var design: int = roundi(total * split[0] / 100.0)
	var programming: int = roundi(total * split[1] / 100.0)
	product["update"] = {
		"product_id": product_id, "points": {"design": design, "programming": programming, "testing": total - design - programming},
		"total_points": total, "progress": {"design": 0.0, "programming": 0.0, "testing": 0.0},
		"bugs_hidden": 0, "bugs_found": 0, "bugs_fixed": 0, "fix_progress": 0.0,
		"team_id": Projects.first_free_team(), "worked_by": [],
	}
	var message: String = "Empezaste la actualización de %s: %s." % [product["name"], Projects.describe_owner(product["update"])]
	EventBus.products_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Retira un producto lanzado: deja de dar ingreso y libera sus racks.
func retire(product_id: int) -> Dictionary:
	var product: Dictionary = get_product(product_id)
	if product.is_empty() or product["state"] != STATE_LAUNCHED:
		return {"ok": false, "message": "Ese producto no está lanzado."}
	products.erase(product)
	var message: String = "Retiraste %s; libera %d %s." % [describe_title(product), ProductCatalog.get_racks(product["size"]),
		"rack" if ProductCatalog.get_racks(product["size"]) == 1 else "racks"]
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


## Proyecto de producto (en desarrollo o actualización) que lleva un equipo (o el CEO con
## Projects.CEO_TEAM), o vacío.
func get_product_of(team_id: int) -> Dictionary:
	if team_id == Projects.NO_TEAM:
		return {}
	for project: Dictionary in get_active_projects():
		if int(project["team_id"]) == team_id:
			return project
	return {}


func _with_state(state: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for product: Dictionary in products:
		if product["state"] == state:
			list.append(product)
	return list


func get_in_development() -> Array[Dictionary]:
	return _with_state(STATE_DEVELOPMENT)


func get_launched() -> Array[Dictionary]:
	return _with_state(STATE_LAUNCHED)


## Proyectos de productos en curso: los productos en desarrollo y las actualizaciones.
func get_active_projects() -> Array[Dictionary]:
	var list: Array[Dictionary] = get_in_development()
	for product: Dictionary in get_launched():
		if product.has("update"):
			list.append(product["update"])
	return list


## Proyectos de productos en curso (cuentan para el tope de proyectos en curso).
func get_development_count() -> int:
	return get_active_projects().size()


## Productos lanzados que todavía tienen usuarios (los pide Corporación).
func get_active_count() -> int:
	return get_launched().filter(func(product: Dictionary) -> bool: return get_users(product) > 0).size()


## Le quita usuarios a un producto lanzado (un evento: servidor caído o un competidor):
## suma a bug_loss, que una actualización devuelve a 0.
func add_user_loss(product_id: int, amount: float) -> void:
	var product: Dictionary = get_product(product_id)
	if product.is_empty() or product["state"] != STATE_LAUNCHED:
		return
	product["bug_loss"] = minf(ProductCatalog.get_production_bugs("max_loss"), float(product["bug_loss"]) + amount)
	EventBus.products_changed.emit()


## Racks que usan los productos lanzados.
func get_used_racks() -> int:
	var used: int = 0
	for product: Dictionary in get_launched():
		used += ProductCatalog.get_racks(product["size"])
	return used


## Racks de la Sala de servidores que no usa ningún producto lanzado.
func get_free_racks() -> int:
	return maxi(0, OfficeState.get_server_capacity() - get_used_racks())


## Ids de los productos lanzados que tienen sus racks: se reparten en orden de lanzamiento.
func get_supported_ids() -> Array[int]:
	var left: int = OfficeState.get_server_capacity()
	var ids: Array[int] = []
	for product: Dictionary in get_launched():
		var needed: int = ProductCatalog.get_racks(product["size"])
		if needed <= left:
			left -= needed
			ids.append(int(product["id"]))
		else:
			left = 0
	return ids


## Calidad de 0 a 1: el nivel medio de quienes diseñaron y los errores que quedan.
func get_quality(product: Dictionary) -> float:
	var design: float = 0.0
	if float(product.get("design_done", 0.0)) > 0.0:
		design = clampf(float(product["design_skill"]) / float(product["design_done"]), 0.0, 1.0)
	var bugs: int = int(product["bugs_hidden"]) + int(product["bugs_found"])
	var limit: float = maxf(1.0, float(ProductCatalog.get_quality("bugs_per_1000_points")) * int(product["total_points"]) / 1000.0)
	var clean: float = clampf(1.0 - bugs / limit, 0.0, 1.0)
	var weight: float = float(ProductCatalog.get_quality("design_weight"))
	return design * weight + clean * (1.0 - weight)


## Multiplicador del ingreso por la calidad (de min_factor a max_factor).
static func get_quality_factor(quality: float) -> float:
	var low: float = float(ProductCatalog.get_quality("min_factor"))
	return low + (float(ProductCatalog.get_quality("max_factor")) - low) * quality


## Parte del pico de usuarios que tiene hoy un producto lanzado (ciclo de vida, errores en
## producción y racks).
func get_users_ratio(product: Dictionary) -> float:
	if product["state"] != STATE_LAUNCHED:
		return 0.0
	var ratio: float = float(product["curve"]) * (1.0 - float(product["bug_loss"]))
	if not get_supported_ids().has(int(product["id"])):
		ratio *= ProductCatalog.get_missing_racks_factor()
	return ratio


func get_users(product: Dictionary) -> int:
	return roundi(ProductCatalog.get_peak_users(product["size"]) * get_users_ratio(product))


## Ingreso diario de hoy de un producto lanzado.
func get_daily_income(product: Dictionary) -> int:
	if product["state"] != STATE_LAUNCHED:
		return 0
	return roundi(ProductCatalog.get_daily_income(product["size"]) * get_quality_factor(float(product["quality"]))
		* get_users_ratio(product))


## Ingreso diario de todos los productos lanzados.
func get_total_daily_income() -> int:
	var total: int = 0
	for product: Dictionary in get_launched():
		total += get_daily_income(product)
	return total


## Lo que suman los productos al valor de la empresa: días de su ingreso actual.
func get_value() -> int:
	return get_total_daily_income() * ProductCatalog.get_value_days()


## Velocidad con que crecen los usuarios: más con vendedores.
func get_growth_speed() -> float:
	return 1.0 + minf(ProductCatalog.get_lifecycle("max_sales_bonus"),
		ProductCatalog.get_lifecycle("sales_growth_bonus") * Projects.get_salesperson_count())


## "Nimbo · App móvil pequeña".
static func describe_title(product: Dictionary) -> String:
	return "%s · %s %s" % [product["name"], ProductCatalog.get_type_name(product["type"]),
		ProductCatalog.get_size_name(product["size"]).to_lower()]


## Título de un proyecto de producto: el producto o "Actualización de Nimbo".
func describe_project(project: Dictionary) -> String:
	if project.has("product_id"):
		return "Actualización de %s" % get_product(int(project["product_id"])).get("name", "?")
	return describe_title(project)


## "Creciendo", "En su mejor momento" o "Cayendo".
static func describe_phase(product: Dictionary) -> String:
	match String(product.get("phase", "")):
		PHASE_GROWTH:
			return "Creciendo"
		PHASE_PLATEAU:
			return "En su mejor momento"
		PHASE_DECLINE:
			return "Cayendo"
	return ""


func export_state() -> Dictionary:
	return {"products": products.duplicate(true), "next_id": _next_id, "started_count": _started_count,
		"launched_count": launched_count, "rng_state": str(_rng.state)}


## Restaura los productos de una partida guardada. Sin datos (partidas anteriores al
## hito 41) queda sin productos.
func import_state(state: Dictionary) -> void:
	products.clear()
	for saved: Dictionary in state.get("products", []):
		var product: Dictionary = _import_project(saved)
		product["id"] = int(saved.get("id", 0))
		product["state"] = String(saved.get("state", STATE_DEVELOPMENT))
		product["started_day"] = int(saved.get("started_day", 0))
		product["design_done"] = float(saved.get("design_done", 0.0))
		product["design_skill"] = float(saved.get("design_skill", 0.0))
		if product["state"] == STATE_LAUNCHED:
			product["quality"] = float(saved.get("quality", 0.5))
			product["curve"] = float(saved.get("curve", ProductCatalog.get_lifecycle("start")))
			product["phase"] = String(saved.get("phase", PHASE_GROWTH))
			product["phase_days"] = int(saved.get("phase_days", 0))
			product["production_bugs"] = int(saved.get("production_bugs", 0))
			product["bug_loss"] = float(saved.get("bug_loss", 0.0))
			product["launched_day"] = int(saved.get("launched_day", 0))
			if saved.get("update", null) is Dictionary:
				product["update"] = _import_project(saved["update"])
				product["update"]["product_id"] = product["id"]
		products.append(product)
	launched_count = int(state.get("launched_count", get_launched().size()))
	_next_id = int(state.get("next_id", products.size() + 1))
	_started_count = int(state.get("started_count", products.size()))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	EventBus.products_changed.emit()


# Copia tolerante de los campos de avance de un proyecto guardado (producto o actualización).
func _import_project(saved: Dictionary) -> Dictionary:
	var project: Dictionary = saved.duplicate(true)
	var points: Dictionary = saved.get("points", {})
	var progress: Dictionary = saved.get("progress", {})
	project["points"] = {}
	project["progress"] = {}
	for phase: String in ContractCatalog.PHASES:
		project["points"][phase] = int(points.get(phase, 0))
		project["progress"][phase] = float(progress.get(phase, 0.0))
	project["total_points"] = int(saved.get("total_points", 0))
	for key: String in Projects.BUG_KEYS:
		project[key] = int(saved.get(key, 0))
	project["fix_progress"] = float(saved.get("fix_progress", 0.0))
	var team_id: int = int(saved.get("team_id", Projects.NO_TEAM))
	project["team_id"] = team_id if team_id <= Projects.CEO_TEAM or not Staff.get_team(team_id).is_empty() else Projects.NO_TEAM
	var worked_by: Array[String] = []
	for key: Variant in saved.get("worked_by", []):
		worked_by.append(String(key))
	project["worked_by"] = worked_by
	return project


# Suma la hora que acaba de terminar a cada producto en desarrollo y a cada actualización.
func _produce() -> void:
	var ended: int = Staff.get_absolute_hour() - 1
	var changed: bool = false
	var shared: Dictionary = {}
	for project: Dictionary in get_active_projects():
		var workers: Array[Dictionary] = Projects.get_workers(project, ended, shared)
		if workers.is_empty():
			continue
		var was_finished: bool = Production.is_finished(project)
		var done: Array[Dictionary] = Production.apply(project, workers)
		Production.handle_bugs(project, done, _rng)
		Production.note_workers(project, done)
		_note_design(project, done)
		changed = true
		if not was_finished and Production.is_finished(project):
			if project.has("product_id"):
				_finish_update(get_product(int(project["product_id"])))
			else:
				EventBus.notice.emit("Terminado: %s. Listo para lanzar." % describe_title(project))
	if changed:
		EventBus.products_changed.emit()


# Suma los puntos de diseño y su valor por el nivel de quien los hizo (la calidad).
func _note_design(project: Dictionary, done: Array[Dictionary]) -> void:
	if project.has("product_id"):
		return
	for item: Dictionary in done:
		if item["phase"] == "design" and item["kind"] == "work" and float(item["amount"]) > 0.0:
			project["design_done"] = float(project.get("design_done", 0.0)) + float(item["amount"])
			project["design_skill"] = float(project.get("design_skill", 0.0)) + float(item["amount"]) \
				* ProductCatalog.get_level_value(String(item["worker"].get("level", "")))


# Termina una actualización: corrige los errores en producción (quedan los de la
# actualización) y el producto vuelve a su mejor momento.
func _finish_update(product: Dictionary) -> void:
	var update: Dictionary = product["update"]
	product["production_bugs"] = int(update["bugs_hidden"]) + int(update["bugs_found"])
	product["bug_loss"] = 0.0
	product["curve"] = 1.0
	product["phase"] = PHASE_PLATEAU
	product["phase_days"] = 0
	product.erase("update")
	EventBus.notice.emit("Actualización terminada: %s vuelve a su mejor momento." % describe_title(product))


# Un día de vida de los productos lanzados: avanza el ciclo, los errores en producción
# quitan usuarios y se cobra el ingreso del día.
func _live_day() -> void:
	var launched: Array[Dictionary] = get_launched()
	if launched.is_empty():
		return
	var growth_days: float = ProductCatalog.get_lifecycle("growth_days")
	var plateau_days: int = int(ProductCatalog.get_lifecycle("plateau_days"))
	var floor_ratio: float = ProductCatalog.get_lifecycle("floor")
	var fall: float = (1.0 - floor_ratio) / ProductCatalog.get_lifecycle("decline_days")
	var start: float = ProductCatalog.get_lifecycle("start")
	for product: Dictionary in launched:
		match String(product["phase"]):
			PHASE_GROWTH:
				product["curve"] = minf(1.0, float(product["curve"]) + (1.0 - start) / growth_days * get_growth_speed())
				# Con un margen: la suma de los pasos puede quedar apenas debajo de 1.
				if float(product["curve"]) >= 1.0 - Production.EPSILON:
					product["curve"] = 1.0
					product["phase"] = PHASE_PLATEAU
					product["phase_days"] = 0
			PHASE_PLATEAU:
				product["phase_days"] = int(product["phase_days"]) + 1
				if int(product["phase_days"]) >= plateau_days:
					product["phase"] = PHASE_DECLINE
					product["phase_days"] = 0
			PHASE_DECLINE:
				product["phase_days"] = int(product["phase_days"]) + 1
				product["curve"] = maxf(floor_ratio, float(product["curve"]) - fall)
		if int(product["production_bugs"]) > 0:
			product["bug_loss"] = minf(ProductCatalog.get_production_bugs("max_loss"), float(product["bug_loss"])
				+ ProductCatalog.get_production_bugs("loss_per_bug") * int(product["production_bugs"]))
	var income: int = get_total_daily_income()
	if income > 0:
		Economy.earn(income, CONCEPT_INCOME)
	EventBus.products_changed.emit()


# Los productos de un equipo que se borró quedan sin equipo.
func _drop_missing_teams() -> void:
	var changed: bool = false
	for product: Dictionary in get_active_projects():
		var team_id: int = int(product["team_id"])
		if team_id > Projects.CEO_TEAM and Staff.get_team(team_id).is_empty():
			product["team_id"] = Projects.NO_TEAM
			changed = true
	if changed:
		EventBus.products_changed.emit()
