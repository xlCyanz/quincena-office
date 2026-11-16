# Empresa de prueba (data/starting_company.json): arranca en Mediana empresa con 40 empleados con puesto,
# equipos con líder, dirección, apoyo y contratos en curso que avanzan.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=starting_company
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	SaveManager.start_with_demo = false
	_check_company()
	_check_running()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _count(role: String) -> int:
	return Staff.employees.filter(func(employee: Dictionary) -> bool: return employee["role"] == role).size()


func _check_company() -> void:
	_expect(Staff.employees.size() == 40, "40 empleados: %d" % Staff.employees.size())
	_expect(Staff.employees.all(func(employee: Dictionary) -> bool: return Staff.has_working_station(employee)), "todos con su puesto")
	_expect(Company.stage == 3 and Company.get_stage_name() == "Mediana empresa", "en Mediana empresa")
	_expect(Economy.balance >= 250000 and Projects.reputation == 3.5, "saldo y reputación iniciales")
	_expect(Staff.teams.size() == 6, "6 equipos")
	for team: Dictionary in Staff.teams:
		_expect((team["members"] as Array).size() == 4 and not Staff.get_team_leader(team).is_empty(), "%s con 4 miembros y líder" % team["name"])
		_expect(not Staff.get_manager_of(Staff.get_team_leader(team)).is_empty(), "%s con gerente" % team["name"])
	_expect(_count("manager") == 2 and _count("executive") == 2, "2 gerentes y 2 ejecutivos")
	_expect(_count("receptionist") == 1 and _count("accountant") == 1 and _count("cleaner") == 2 and _count("salesperson") == 2, "personal de apoyo")
	_expect(Staff.get_departments().size() == 4, "los 4 departamentos")
	_expect(Projects.visits_enabled(), "la Recepción funciona")
	_expect(Staff.has_accountant() and Economy.get_monthly_maintenance() < Economy.get_maintenance(OfficeState.lot.get_area()), "el contador baja el mantenimiento")
	_expect(Projects.contracts.size() == 7 and Projects.contracts.all(func(contract: Dictionary) -> bool: return int(contract["team_id"]) != Projects.NO_TEAM),
		"7 contratos en curso, todos con quien los lleve")
	_expect(not Economy.movements.any(func(movement: Dictionary) -> bool: return movement["concept"] == Builder.CONCEPT_FURNITURE),
		"la obra no queda en los movimientos")


func _check_running() -> void:
	var done_before: float = 0.0
	for contract: Dictionary in Projects.contracts:
		done_before += float(contract["progress"]["design"]) + float(contract["progress"]["programming"]) + float(contract["progress"]["testing"])
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * 3)
	var done_after: float = 0.0
	for contract: Dictionary in Projects.contracts:
		done_after += float(contract["progress"]["design"]) + float(contract["progress"]["programming"]) + float(contract["progress"]["testing"])
	_expect(done_after > done_before + 300.0, "en 3 días los contratos avanzan: %.0f → %.0f" % [done_before, done_after])
	_expect(Staff.employees.size() == 40 and not Bank.game_over, "sigue funcionando")
