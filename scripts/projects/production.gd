# Producción (funciones puras): puntos por hora de cada persona y su reparto en las fases
# diseño → programación → pruebas. Una fase abre con la anterior en phase_open_ratio y nunca
# pasa su %; sin lugar en la suya se ayuda en la primera libre a helper_factor (el CEO,
# phase "", rinde entero). Lo que no cabe se pierde. El azar de errores lo pone Projects.
class_name Production
extends RefCounted

## Margen para comparar puntos con decimales.
const EPSILON: float = 0.0001


## Puntos por hora: los de su nivel × energía × ánimo × (1 + bono de la computadora).
static func get_rate(level: String, energy: float, computer_bonus: float, mood: float = 100.0) -> float:
	var base: float = StaffCatalog.get_points_per_hour(level)
	return base * get_energy_factor(energy) * get_mood_factor(mood) * (1.0 + computer_bonus)


## Factor por energía: 1 desde energy_full_from, baja en línea hasta energy_min_factor en 0.
static func get_energy_factor(energy: float) -> float:
	var full_from: float = float(StaffCatalog.get_production("energy_full_from"))
	var min_factor: float = float(StaffCatalog.get_production("energy_min_factor"))
	if energy >= full_from:
		return 1.0
	return lerpf(min_factor, 1.0, clampf(energy, 0.0, full_from) / full_from)


## Factor por ánimo: 1 desde mood_full_from, baja en línea hasta mood_min_factor en 0.
static func get_mood_factor(mood: float) -> float:
	var full_from: float = float(StaffCatalog.get_production("mood_full_from"))
	var min_factor: float = float(StaffCatalog.get_production("mood_min_factor"))
	if mood >= full_from:
		return 1.0
	return lerpf(min_factor, 1.0, clampf(mood, 0.0, full_from) / full_from)


## Bono de una computadora (furniture.json, production_bonus).
static func get_computer_bonus(computer_id: String) -> float:
	if computer_id.is_empty():
		return 0.0
	return FurnitureCatalog.get_production_bonus(computer_id)


## Fase de un cargo (la de su habilidad principal), o "" si no produce (vendedores).
static func get_role_phase(role: String) -> String:
	var skill: String = StaffCatalog.get_main_skill(role)
	return skill if ContractCatalog.PHASES.has(skill) else ""


## Fracción hecha de una fase (0 a 1); sin puntos cuenta como hecha.
static func get_ratio(contract: Dictionary, phase: String) -> float:
	var total: float = float(contract["points"][phase])
	if total <= 0.0:
		return 1.0
	return clampf(float(contract["progress"][phase]) / total, 0.0, 1.0)


## Indica si una fase ya se puede trabajar.
static func is_open(contract: Dictionary, phase: String) -> bool:
	var index: int = ContractCatalog.PHASES.find(phase)
	if index <= 0:
		return true
	var previous: String = ContractCatalog.PHASES[index - 1]
	return get_ratio(contract, previous) + EPSILON >= float(StaffCatalog.get_production("phase_open_ratio"))


## Puntos que caben ahora en una fase (hasta el % de la anterior).
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


## Suma una hora de trabajo. workers: [{"phase", "rate"}] (phase "" = generalista). Devuelve
## [{"worker", "phase", "amount", "kind"}], kind "work", "review" (QA con pruebas completas)
## o "fix". Antes de avanzar, programadores y generalista corrigen bugs_found a fix_cost c/u.
static func apply(contract: Dictionary, workers: Array[Dictionary]) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	# Especialistas primero, en orden de fases: el diseño de esta hora abre lugar a la programación.
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


# Gasta hasta rate puntos en corregir errores encontrados; devuelve lo gastado.
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


## Con el resultado de apply: programar genera errores ocultos y probar encuentra cada uno con
## probabilidad cobertura × puntos de pruebas / pruebas del proyecto. Anota "bugs" en cada item
## de programación. Para contratos y productos; azar de rng.
static func handle_bugs(project: Dictionary, done: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var testing_total: float = maxf(1.0, float(project["points"]["testing"]))
	for item: Dictionary in done:
		var worker: Dictionary = item["worker"]
		var amount: float = float(item["amount"])
		if item["kind"] == "work" and item["phase"] == "programming":
			# Quién los generó queda en el item (historial del empleado).
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


## Veces que pasa algo con media expected: la parte entera siempre y la fracción con esa probabilidad.
static func roll(expected: float, rng: RandomNumberGenerator) -> int:
	var whole: int = floori(expected)
	return whole + (1 if rng.randf() < expected - whole else 0)


## Anota en el proyecto a quienes sumaron puntos (cuenta para ascensos).
static func note_workers(project: Dictionary, done: Array[Dictionary]) -> void:
	var worked_by: Array = project.get_or_add("worked_by", [])
	for item: Dictionary in done:
		var key: String = item["worker"]["key"]
		if key != "ceo" and float(item["amount"]) > 0.0 and not worked_by.has(key):
			worked_by.append(key)
