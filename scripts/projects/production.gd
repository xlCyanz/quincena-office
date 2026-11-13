# Producción (diseño, 7.2 y 13.3): cuántos puntos rinde una persona por hora y cómo se
# reparten entre las tres fases de un contrato. Son funciones puras: Projects arma la
# lista de quienes trabajaron en la hora y llama a apply.
#
# Fases: diseño, programación y pruebas, en orden. Una fase se abre cuando la anterior
# llega a phase_open_ratio de sus puntos, y su avance nunca pasa del porcentaje de la
# anterior (programación no termina antes que diseño). Cada trabajador suma en la fase
# de su especialidad si tiene lugar; si no, ayuda en la primera fase con lugar rindiendo
# helper_factor. Un generalista (el CEO, phase = "") rinde completo en la primera fase con
# lugar. Lo que no cabe se pierde.
#
# Errores (hito 17): Production solo corrige los encontrados y dice quién hizo qué; el
# azar de generarlos y encontrarlos lo pone Projects con su semilla.
class_name Production
extends RefCounted

## Margen para comparar puntos con decimales.
const EPSILON: float = 0.0001


## Puntos por hora de una persona: los de su nivel, menos si está cansada (energía bajo
## energy_full_from) o desanimada (ánimo bajo mood_full_from) y más con una computadora mejor.
static func get_rate(level: String, energy: float, computer_bonus: float, mood: float = 100.0) -> float:
	var base: float = StaffCatalog.get_points_per_hour(level)
	return base * get_energy_factor(energy) * get_mood_factor(mood) * (1.0 + computer_bonus)


## Cuánto rinde según la energía: 1 desde energy_full_from; debajo baja en línea recta
## hasta energy_min_factor con energía 0.
static func get_energy_factor(energy: float) -> float:
	var full_from: float = float(StaffCatalog.get_production("energy_full_from"))
	var min_factor: float = float(StaffCatalog.get_production("energy_min_factor"))
	if energy >= full_from:
		return 1.0
	return lerpf(min_factor, 1.0, clampf(energy, 0.0, full_from) / full_from)


## Cuánto rinde según el ánimo: 1 desde mood_full_from; debajo baja en línea recta hasta
## mood_min_factor con ánimo 0.
static func get_mood_factor(mood: float) -> float:
	var full_from: float = float(StaffCatalog.get_production("mood_full_from"))
	var min_factor: float = float(StaffCatalog.get_production("mood_min_factor"))
	if mood >= full_from:
		return 1.0
	return lerpf(min_factor, 1.0, clampf(mood, 0.0, full_from) / full_from)


## Bonificación de una computadora (data/furniture.json, production_bonus).
static func get_computer_bonus(computer_id: String) -> float:
	if computer_id.is_empty():
		return 0.0
	return FurnitureCatalog.get_production_bonus(computer_id)


## Fase en que trabaja un cargo: la de su habilidad principal, o "" si no es una fase
## (los vendedores no producen puntos).
static func get_role_phase(role: String) -> String:
	var skill: String = StaffCatalog.get_main_skill(role)
	return skill if ContractCatalog.PHASES.has(skill) else ""


## Fracción hecha de una fase (0 a 1). Una fase sin puntos cuenta como hecha.
static func get_ratio(contract: Dictionary, phase: String) -> float:
	var total: float = float(contract["points"][phase])
	if total <= 0.0:
		return 1.0
	return clampf(float(contract["progress"][phase]) / total, 0.0, 1.0)


## Indica si una fase ya se puede trabajar (la anterior llegó a la mitad).
static func is_open(contract: Dictionary, phase: String) -> bool:
	var index: int = ContractCatalog.PHASES.find(phase)
	if index <= 0:
		return true
	var previous: String = ContractCatalog.PHASES[index - 1]
	return get_ratio(contract, previous) + EPSILON >= float(StaffCatalog.get_production("phase_open_ratio"))


## Puntos que todavía caben en una fase ahora: hasta el porcentaje de la anterior.
static func get_room(contract: Dictionary, phase: String) -> float:
	if not is_open(contract, phase):
		return 0.0
	var total: float = float(contract["points"][phase])
	var limit: float = total
	var index: int = ContractCatalog.PHASES.find(phase)
	if index > 0:
		limit = total * get_ratio(contract, ContractCatalog.PHASES[index - 1])
	var room: float = limit - float(contract["progress"][phase])
	return room if room > EPSILON else 0.0


## Indica si las tres fases están completas.
static func is_finished(contract: Dictionary) -> bool:
	for phase: String in ContractCatalog.PHASES:
		if get_ratio(contract, phase) < 1.0 - EPSILON:
			return false
	return true


## Suma una hora de trabajo al contrato. workers es una lista de {"phase", "rate"}
## (phase = "" para un generalista). Devuelve lo que hizo cada uno: una lista de
## {"worker", "phase", "amount", "kind"} con kind "work" (avance de una fase), "review"
## (QA revisando con las pruebas completas) o "fix" (corrigiendo errores encontrados).
##
## Antes de avanzar, los programadores y el generalista corrigen los errores encontrados
## (bugs_found), a fix_cost puntos cada uno.
static func apply(contract: Dictionary, workers: Array[Dictionary]) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	# Primero los especialistas en el orden de las fases: así la hora de diseño abre
	# lugar para la de programación en la misma hora.
	var ordered: Array[Dictionary] = workers.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _order(a["phase"]) < _order(b["phase"]))
	var helper_factor: float = float(StaffCatalog.get_production("helper_factor"))
	for worker: Dictionary in ordered:
		var phase: String = worker["phase"]
		var rate: float = float(worker["rate"])
		if phase.is_empty() or phase == "programming":
			var fixing: float = _fix(contract, rate)
			if fixing > 0.0:
				done.append({"worker": worker, "phase": "programming", "amount": fixing, "kind": "fix"})
				rate -= fixing
		if rate <= EPSILON:
			continue
		if not phase.is_empty() and get_room(contract, phase) > 0.0:
			done.append({"worker": worker, "phase": phase, "amount": _add(contract, phase, rate), "kind": "work"})
			continue
		# Con las pruebas completas, QA sigue buscando errores.
		if phase == "testing" and get_ratio(contract, phase) >= 1.0 - EPSILON:
			done.append({"worker": worker, "phase": phase, "amount": rate, "kind": "review"})
			continue
		var factor: float = 1.0 if phase.is_empty() else helper_factor
		for other: String in ContractCatalog.PHASES:
			if get_room(contract, other) > 0.0:
				done.append({"worker": worker, "phase": other, "amount": _add(contract, other, rate * factor), "kind": "work"})
				break
	return done


# Gasta hasta rate puntos en corregir errores encontrados. Devuelve lo gastado.
static func _fix(contract: Dictionary, rate: float) -> float:
	var found: int = int(contract.get("bugs_found", 0))
	if found <= 0:
		return 0.0
	var cost: float = float(ContractCatalog.get_bugs("fix_cost"))
	var progress: float = float(contract.get("fix_progress", 0.0))
	var spent: float = minf(rate, found * cost - progress)
	progress += spent
	var fixed: int = mini(floori((progress + EPSILON) / cost), found)
	progress -= fixed * cost
	found -= fixed
	contract["bugs_found"] = found
	contract["bugs_fixed"] = int(contract.get("bugs_fixed", 0)) + fixed
	contract["fix_progress"] = 0.0 if found == 0 else maxf(progress, 0.0)
	return spent


static func _add(contract: Dictionary, phase: String, amount: float) -> float:
	var used: float = minf(amount, get_room(contract, phase))
	contract["progress"][phase] = float(contract["progress"][phase]) + used
	return used


static func _order(phase: String) -> int:
	var index: int = ContractCatalog.PHASES.find(phase)
	return ContractCatalog.PHASES.size() if index < 0 else index


## Con lo que hizo cada uno en la hora (lo que devuelve apply): la programación genera
## errores ocultos y las pruebas (o la revisión de QA) encuentran algunos: cada error
## oculto se encuentra con probabilidad cobertura × puntos de pruebas / puntos de pruebas
## del proyecto. Sirve para contratos y productos; el azar sale de rng. Cada item de
## programación queda con "bugs", los errores ocultos que generó.
static func handle_bugs(project: Dictionary, done: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var testing_total: float = maxf(1.0, float(project["points"]["testing"]))
	for item: Dictionary in done:
		var worker: Dictionary = item["worker"]
		var amount: float = float(item["amount"])
		if item["kind"] == "work" and item["phase"] == "programming":
			# Quién los generó queda en el item (historial del empleado, hito 51).
			item["bugs"] = roll(amount * float(worker["bug_chance"]), rng)
			project["bugs_hidden"] = int(project["bugs_hidden"]) + int(item["bugs"])
		elif item["phase"] == "testing" and int(project["bugs_hidden"]) > 0:
			var coverage: float = float(ContractCatalog.get_bugs("qa_coverage" if worker["phase"] == "testing" else "other_coverage"))
			var chance: float = minf(1.0, coverage * float(worker.get("find_factor", 1.0)) * amount / testing_total)
			var found: int = 0
			for bug: int in range(int(project["bugs_hidden"])):
				if rng.randf() < chance:
					found += 1
			project["bugs_hidden"] = int(project["bugs_hidden"]) - found
			project["bugs_found"] = int(project["bugs_found"]) + found


## Cuántas veces pasa algo que en promedio pasa expected veces: la parte entera siempre
## y la fracción con esa probabilidad.
static func roll(expected: float, rng: RandomNumberGenerator) -> int:
	var whole: int = floori(expected)
	return whole + (1 if rng.randf() < expected - whole else 0)


## Anota en el proyecto a los empleados que sumaron puntos (cuenta para sus ascensos).
static func note_workers(project: Dictionary, done: Array[Dictionary]) -> void:
	var worked_by: Array = project.get_or_add("worked_by", [])
	for item: Dictionary in done:
		var key: String = item["worker"]["key"]
		if key != "ceo" and float(item["amount"]) > 0.0 and not worked_by.has(key):
			worked_by.append(key)
