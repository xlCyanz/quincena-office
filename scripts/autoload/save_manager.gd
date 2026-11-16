# Guardado y carga: junta el export_state() de cada sistema en un JSON y lo reparte con import_state().
# Autoguardado al pasar a las 00:00 y SLOT_COUNT ranuras manuales. La escena aporta cámara y CEO con
# scene_state_provider y los recibe al abrirse con take_scene_state().
extends Node

const AUTOSAVE: String = "autosave"
const SLOT_COUNT: int = 5
const DEFAULT_SAVE_DIR: String = "user://saves"
## Versión del formato del archivo. Si cambia, los archivos viejos no se cargan.
const FORMAT_VERSION: int = 1

## Carpeta de los archivos de guardado (las pruebas usan otra para no tocar las del jugador).
var save_dir: String = DEFAULT_SAVE_DIR

## true: una partida nueva empieza con la empresa de data/starting_company.json (para probar).
var start_with_demo: bool = false

## Lo pone la escena de juego abierta: devuelve su estado (cámara y CEO). Sin escena no hay autoguardado.
var scene_state_provider := Callable()

var _pending_scene_state: Dictionary = {}
# La partida terminó por embargo: no se autoguarda más.
var _game_over: bool = false


func _ready() -> void:
	# Economy se conecta antes: el autoguardado del día 1 ya incluye el mantenimiento.
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.game_over.connect(_on_game_over)


## Deja todos los sistemas como al empezar una partida nueva.
func new_game() -> void:
	_pending_scene_state = {}
	_game_over = false
	Company.begin_load()
	Tutorial.begin_load()
	OfficeState.new_game()
	Staff.new_game()
	GameClock.new_game()
	Projects.new_game()
	Products.new_game()
	# Después del local: la calificación inicial mira sus muebles.
	Bank.new_game()
	Company.new_game()
	Events.new_game()
	Tutorial.new_game()
	# El saldo va al final: al cambiar, Staff y Bank pagan deudas, y deben ser las de esta partida.
	Economy.new_game()
	if start_with_demo:
		StartingCompany.apply()
		# La empresa de prueba empieza sin tutorial.
		Tutorial.import_state({})
	Company.finish_load()
	Tutorial.finish_load()


## Ids de las ranuras manuales: "slot_1" … "slot_5".
func get_manual_slots() -> Array[String]:
	var slots: Array[String] = []
	for number: int in range(1, SLOT_COUNT + 1):
		slots.append("slot_%d" % number)
	return slots


## Nombre visible de una ranura.
func get_slot_name(slot: String) -> String:
	if slot == AUTOSAVE:
		return "Autoguardado"
	return "Ranura %s" % slot.trim_prefix("slot_")


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))


## Indica si hay alguna partida guardada.
func has_any_save() -> bool:
	if has_save(AUTOSAVE):
		return true
	for slot: String in get_manual_slots():
		if has_save(slot):
			return true
	return false


## Guarda la partida actual en una ranura. Devuelve false si no se pudo escribir.
func save_game(slot: String) -> bool:
	var data: Dictionary = {
		"version": FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"summary": {
			"day": GameClock.get_day(), "month": GameClock.get_month(),
			"hour": GameClock.get_hour(), "balance": Economy.balance,
		},
		"clock": GameClock.export_state(),
		"economy": Economy.export_state(),
		"office": OfficeState.export_state(),
		"staff": Staff.export_state(),
		"projects": Projects.export_state(),
		"products": Products.export_state(),
		"bank": Bank.export_state(),
		"company": Company.export_state(),
		"events": Events.export_state(),
		"tutorial": Tutorial.export_state(),
		"scene": scene_state_provider.call() if scene_state_provider.is_valid() else {},
	}
	DirAccess.make_dir_recursive_absolute(save_dir)
	# Archivo temporal y luego renombrar: un cierre a mitad no rompe el guardado anterior.
	var temporary: String = _path(slot) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo guardar en %s: %s" % [temporary, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(temporary, _path(slot)) == OK


## Carga una partida y deja el estado de la escena para cuando se abra. Devuelve false (sin cambiar nada) si no sirve.
func load_game(slot: String) -> bool:
	var data: Dictionary = _read(slot)
	if data.is_empty():
		return false
	_game_over = false
	Company.begin_load()
	Tutorial.begin_load()
	OfficeState.import_state(data["office"])
	Staff.import_state(data.get("staff", {}))
	Projects.import_state(data.get("projects", {}))
	Products.import_state(data.get("products", {}))
	GameClock.import_state(data["clock"])
	Bank.import_state(data.get("bank", {}))
	Company.import_state(data.get("company", {}))
	Events.import_state(data.get("events", {}))
	Tutorial.import_state(data.get("tutorial", {}))
	# El saldo va al final: al cambiar, Staff y Bank pagan deudas, y deben ser las de esta partida.
	Economy.import_state(data["economy"])
	# Los objetivos se revisan con la partida ya entera.
	Company.finish_load()
	Tutorial.finish_load()
	_pending_scene_state = data.get("scene", {})
	return true


## Ranura guardada más reciente, o ""; con la misma hora gana el autoguardado.
func get_latest_slot() -> String:
	var latest: String = ""
	var latest_at: int = -1
	var slots: Array[String] = [AUTOSAVE]
	slots.append_array(get_manual_slots())
	for slot: String in slots:
		var summary: Dictionary = get_summary(slot)
		if not summary.is_empty() and int(summary["saved_at"]) > latest_at:
			latest = slot
			latest_at = int(summary["saved_at"])
	return latest


## Resumen de una ranura ({"day", "month", "hour", "balance", "saved_at"}), o {} si está vacía.
func get_summary(slot: String) -> Dictionary:
	var data: Dictionary = _read(slot)
	if data.is_empty():
		return {}
	var summary: Dictionary = data["summary"].duplicate()
	summary["saved_at"] = int(data.get("saved_at", 0))
	for key: String in ["day", "month", "hour", "balance"]:
		summary[key] = int(summary.get(key, 0))
	return summary


## Texto de una ranura para los menús: "Ranura 1 — Mes 2, día 3, 08:00 · $19,710".
func describe_slot(slot: String) -> String:
	var summary: Dictionary = get_summary(slot)
	if summary.is_empty():
		return "%s — vacía" % get_slot_name(slot)
	return "%s — Mes %d, día %d, %02d:00 · %s" % [get_slot_name(slot), summary["month"], summary["day"],
		summary["hour"], MoneyFormat.format(summary["balance"])]


## Estado de la escena de la última partida cargada ({} si es nueva). Se entrega una sola vez.
func take_scene_state() -> Dictionary:
	var state: Dictionary = _pending_scene_state
	_pending_scene_state = {}
	return state


func _on_day_changed(_day: int, _month: int) -> void:
	if scene_state_provider.is_valid() and not _game_over and bool(Settings.get_value("autosave")):
		save_game(AUTOSAVE)


# Al perder se borra el autoguardado (no volver al embargo); las ranuras manuales quedan.
func _on_game_over(_stats: Dictionary) -> void:
	_game_over = true
	if has_save(AUTOSAVE):
		DirAccess.remove_absolute(_path(AUTOSAVE))


func _path(slot: String) -> String:
	return save_dir.path_join(slot + ".json")


func _read(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	# JSON.new().parse() no imprime errores: un archivo dañado solo da un aviso.
	var json := JSON.new()
	var parsed: Variant = null
	if json.parse(FileAccess.get_file_as_string(_path(slot))) == OK:
		parsed = json.data
	if not parsed is Dictionary:
		push_warning("El guardado %s está dañado." % slot)
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("El guardado %s es de otra versión del juego." % slot)
		return {}
	for key: String in ["summary", "clock", "economy", "office"]:
		if not data.get(key) is Dictionary:
			push_warning("Al guardado %s le falta %s." % [slot, key])
			return {}
	return data
