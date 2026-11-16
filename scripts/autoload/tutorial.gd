# Tutorial guiado: pasos de data/tutorial.json con texto, resaltado y condición (estado de los
# sistemas o EventBus.ui_action). Aparece en partidas nuevas hasta terminarlo o saltarlo una vez
# (opción tutorial_seen); se retoma desde Ajustes y se guarda. No bloquea nada (TutorialPanel).
extends Node

const TUTORIAL_PATH: String = "res://data/tutorial.json"

## El tutorial se muestra en esta partida.
var active: bool = false
## Índice del paso actual (en data/tutorial.json).
var step_index: int = 0
## Se llegó al final (o se cargó una partida sin tutorial).
var finished: bool = true
## Acciones de la interfaz ya hechas en esta partida (EventBus.ui_action).
var actions: Array[String] = []

var _data: Dictionary = {}
var _loading: bool = false


func _ready() -> void:
	EventBus.ui_action.connect(_on_ui_action)
	EventBus.staff_changed.connect(check)
	EventBus.office_changed.connect(check)
	EventBus.projects_changed.connect(check)


## Partida nueva: empieza en el primer paso si el jugador nunca lo terminó ni lo saltó.
func new_game() -> void:
	actions.clear()
	step_index = 0
	finished = false
	active = not bool(Settings.get_value("tutorial_seen"))
	EventBus.tutorial_changed.emit()


## Mientras se prepara o carga una partida no se revisan los pasos.
func begin_load() -> void:
	_loading = true


func finish_load() -> void:
	_loading = false
	check()


## Pasos de data/tutorial.json.
func get_steps() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for step: Variant in _tutorial_data().get("steps", []):
		steps.append(step as Dictionary)
	return steps


## Paso actual, o vacío si el tutorial no se muestra.
func get_current_step() -> Dictionary:
	var steps: Array[Dictionary] = get_steps()
	if not active or step_index < 0 or step_index >= steps.size():
		return {}
	return steps[step_index]


func is_showing() -> bool:
	return not get_current_step().is_empty()


## Indica si la condición de un paso ya se cumple.
func is_step_met(step: Dictionary) -> bool:
	var condition: Dictionary = step.get("condition", {})
	var count: int = int(condition.get("count", 1))
	match String(condition.get("type", "")):
		"action":
			return actions.has(String(condition.get("action", "")))
		"workstations":
			return Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.WORK_AREA).size() >= count
		"vacancies":
			return Staff.vacancies.size() >= count
	return bool(Company.get_objective_progress({"condition": condition})["met"])


## Pasa los pasos que ya se cumplen; al terminar el último cierra el tutorial con un aviso.
func check() -> void:
	if _loading or not is_showing():
		return
	var changed: bool = false
	while is_showing() and is_step_met(get_current_step()):
		step_index += 1
		changed = true
	if step_index >= get_steps().size():
		active = false
		finished = true
		Settings.set_value("tutorial_seen", true)
		EventBus.notice.emit("Terminaste el tutorial. Sigue los objetivos de la izquierda para hacer crecer la empresa.")
	if changed:
		EventBus.tutorial_changed.emit()


## Salta el tutorial: se cierra en esta partida y las nuevas empiezan sin él.
func skip() -> void:
	if not active:
		return
	active = false
	Settings.set_value("tutorial_seen", true)
	EventBus.notice.emit("Puedes retomar el tutorial desde Ajustes.")
	EventBus.tutorial_changed.emit()


## Retoma el tutorial desde el paso donde quedó (o desde el principio si se terminó).
func resume() -> void:
	if active:
		return
	if finished or step_index >= get_steps().size():
		finished = false
		step_index = 0
	active = true
	EventBus.tutorial_changed.emit()
	check()


func _on_ui_action(action: String) -> void:
	if not actions.has(action):
		actions.append(action)
	check()


func export_state() -> Dictionary:
	var step: String = ""
	var steps: Array[Dictionary] = get_steps()
	if step_index >= 0 and step_index < steps.size():
		step = String(steps[step_index]["id"])
	return {"active": active, "step": step, "finished": finished, "actions": actions.duplicate()}


## Sin estado carga sin tutorial, como terminado; un paso que ya no existe vuelve al primero.
func import_state(state: Dictionary) -> void:
	actions.clear()
	for action: Variant in state.get("actions", []):
		actions.append(String(action))
	finished = bool(state.get("finished", true))
	active = bool(state.get("active", false)) and not finished
	step_index = 0
	var step_id: String = String(state.get("step", ""))
	var steps: Array[Dictionary] = get_steps()
	for index: int in steps.size():
		if String(steps[index]["id"]) == step_id:
			step_index = index
	EventBus.tutorial_changed.emit()


func _tutorial_data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUTORIAL_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data
