# Guardado y carga (diseño, 12.5): reúne el export_state() de cada sistema en un
# archivo JSON y lo reparte con import_state() al cargar. También prepara una partida
# nueva.
#
# Hay un autoguardado, que se escribe solo al final de cada día de juego (al pasar a
# las 00:00), y SLOT_COUNT ranuras de guardado manual. Lo que vive en la escena de
# juego (cámara y CEO) lo aporta la escena con scene_state_provider; al cargar queda
# esperando en take_scene_state() hasta que la escena se abre.
extends Node

const AUTOSAVE: String = "autosave"
const SLOT_COUNT: int = 5
const DEFAULT_SAVE_DIR: String = "user://saves"
## Versión del formato del archivo. Si cambia, los archivos viejos no se cargan.
const FORMAT_VERSION: int = 1

## Carpeta de los archivos de guardado (las pruebas usan otra para no tocar las del jugador).
var save_dir: String = DEFAULT_SAVE_DIR

## Lo pone la escena de juego mientras está abierta: devuelve el estado de la escena
## (cámara y CEO). Sin escena abierta no hay autoguardado.
var scene_state_provider := Callable()

var _pending_scene_state: Dictionary = {}


func _ready() -> void:
	# Economy se conecta antes (va antes en la lista de autoloads), así que el
	# autoguardado del día 1 ya incluye el cobro del mantenimiento.
	EventBus.day_changed.connect(_on_day_changed)


## Deja todos los sistemas como al empezar una partida nueva: el local inicial con
## la Oficina Ejecutiva, el capital inicial y el reloj en el día 1 a la hora de entrada.
func new_game() -> void:
	_pending_scene_state = {}
	Economy.new_game()
	OfficeState.new_game()
	Staff.new_game()
	GameClock.new_game()
	Projects.new_game()
	# Al final: la calificación inicial mira los muebles del local inicial.
	Bank.new_game()


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
		"bank": Bank.export_state(),
		"scene": scene_state_provider.call() if scene_state_provider.is_valid() else {},
	}
	DirAccess.make_dir_recursive_absolute(save_dir)
	# Se escribe primero en un archivo temporal y luego se renombra, para que un cierre
	# a mitad de escritura no deje el guardado anterior roto.
	var temporary: String = _path(slot) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo guardar en %s: %s" % [temporary, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(temporary, _path(slot)) == OK


## Carga una partida: restaura reloj, economía y oficina, y deja el estado de la escena
## para cuando se abra. Devuelve false (sin cambiar nada) si el archivo no sirve.
func load_game(slot: String) -> bool:
	var data: Dictionary = _read(slot)
	if data.is_empty():
		return false
	OfficeState.import_state(data["office"])
	# Las partidas de la fase 1 no tienen personal: se cargan sin vacantes.
	Staff.import_state(data.get("staff", {}))
	Projects.import_state(data.get("projects", {}))
	Economy.import_state(data["economy"])
	GameClock.import_state(data["clock"])
	# Las partidas de antes del hito 21 no tienen banco: se calcula con lo que hay.
	Bank.import_state(data.get("bank", {}))
	_pending_scene_state = data.get("scene", {})
	return true


## Resumen de una ranura ({"day", "month", "hour", "balance", "saved_at"}), o vacío si
## no hay partida ahí.
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


## Estado de la escena de la última partida cargada (vacío si es nueva). Se entrega
## una sola vez.
func take_scene_state() -> Dictionary:
	var state: Dictionary = _pending_scene_state
	_pending_scene_state = {}
	return state


func _on_day_changed(_day: int, _month: int) -> void:
	if scene_state_provider.is_valid():
		save_game(AUTOSAVE)


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
