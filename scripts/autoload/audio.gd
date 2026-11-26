# Sonido: efectos y música de data/audio.json. Escucha EventBus (sound_requested, music_requested y
# las señales de "signals"), suena un clic con cada botón y aplica los volúmenes de Settings a los
# buses Music y Sfx. No guarda estado de partida.
extends Node

const DATA_PATH: String = "res://data/audio.json"
const VOLUME_KEYS: Dictionary[String, String] = {
	"master_volume": "Master",
	"music_volume": "music",
	"sfx_volume": "sfx",
}
const HISTORY_SIZE: int = 32

var _data: Dictionary = {}
var _streams: Dictionary[String, AudioStream] = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
## Último momento (ms) en que sonó cada efecto, para no amontonarlos.
var _last_played: Dictionary[String, int] = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_track: String = ""
var _music_tween: Tween
## Con el controlador mudo (--headless) no se reproduce nada: sus reproducciones no se liberan
## al cerrar y Godot avisa de recursos en uso. Lo demás (historial, pista, buses) funciona igual.
var _silent: bool = false
## Efectos que sonaron, en orden (los últimos HISTORY_SIZE); lo leen las pruebas.
var _history: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = AudioServer.get_driver_name() == "Dummy"
	_load_data()
	_make_buses()
	for index: int in range(int(_data.get("players", 8))):
		var player := AudioStreamPlayer.new()
		player.bus = get_bus("sfx")
		add_child(player)
		_players.append(player)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_connect_signals()
	EventBus.sound_requested.connect(play)
	EventBus.music_requested.connect(play_music)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.payment_recorded.connect(_on_payment_recorded)
	get_tree().node_added.connect(_on_node_added)
	apply_volumes()


func _load_data() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_data = data if data is Dictionary else {}


## Datos de data/audio.json.
func get_data() -> Dictionary:
	return _data


## Ids de los efectos que hay.
func get_sound_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _data.get("sounds", {}):
		ids.append(id)
	return ids


## Nombre del bus de "music" o "sfx" (o el de Master).
func get_bus(kind: String) -> String:
	if kind == "Master":
		return "Master"
	return String((_data.get("buses", {}) as Dictionary).get(kind, "Master"))


func _make_buses() -> void:
	for kind: String in ["music", "sfx"]:
		var bus_name: String = get_bus(kind)
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = get_bus("music")
	add_child(player)
	return player


## Stream de un efecto o pista (archivo de folder); null si no existe.
func get_stream(file_name: String) -> AudioStream:
	if _streams.has(file_name):
		return _streams[file_name]
	var path: String = String(_data.get("folder", "res://assets/sounds/")) + file_name
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[file_name] = stream
	return stream


## Suena un efecto. Devuelve false si no existe o sonó hace menos de su min_interval.
func play(sound_id: String) -> bool:
	var sounds: Dictionary = _data.get("sounds", {})
	if not sounds.has(sound_id):
		return false
	var config: Dictionary = sounds[sound_id]
	var now: int = Time.get_ticks_msec()
	var min_ms: int = int(float(config.get("min_interval", 0.0)) * 1000.0)
	if _last_played.has(sound_id) and now - _last_played[sound_id] < min_ms:
		return false
	var stream: AudioStream = get_stream(sound_id + ".wav")
	if stream == null:
		return false
	_last_played[sound_id] = now
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = float(config.get("volume_db", 0.0))
	var jitter: float = float(config.get("pitch_jitter", 0.0))
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	if not _silent:
		player.play()
	_history.append(sound_id)
	if _history.size() > HISTORY_SIZE:
		_history.pop_front()
	return true


## Efectos que sonaron, del más viejo al último.
func get_history() -> Array[String]:
	return _history


func clear_history() -> void:
	_history.clear()
	_last_played.clear()


## Pone una pista de música en bucle ("" la calla), cruzándola con la que sonaba.
func play_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	var fade: float = float(_data.get("fade_seconds", 1.5))
	var old: AudioStreamPlayer = _music_a
	_music_a = _music_b
	_music_b = old
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	var file_name: String = String((_data.get("music", {}) as Dictionary).get(track, ""))
	var stream: AudioStream = get_stream(file_name) if file_name != "" else null
	if stream == null:
		_music_a.stop()
	else:
		_music_a.stream = stream
		_music_a.volume_db = -60.0
		if not _silent:
			_music_a.play()
	if not old.playing and stream == null:
		return
	_music_tween = create_tween().set_parallel()
	if stream != null:
		_music_tween.tween_property(_music_a, "volume_db", 0.0, fade)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -60.0, fade)
		_music_tween.chain().tween_callback(old.stop)


## Pista que suena ("" si ninguna).
func get_music_track() -> String:
	return _music_track


## El reproductor de la pista que suena (para las pruebas).
func get_music_player() -> AudioStreamPlayer:
	return _music_a


# Sin esto Godot se queja al cerrar de streams que siguen en uso.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _players + [_music_a, _music_b]:
		player.stop()
		player.stream = null
	_streams.clear()


## Aplica master_volume, music_volume y sfx_volume (0 a 100) a sus buses; 0 los silencia.
func apply_volumes() -> void:
	for key: String in VOLUME_KEYS:
		var index: int = AudioServer.get_bus_index(get_bus(VOLUME_KEYS[key]))
		if index < 0:
			continue
		var value: Variant = Settings.get_value(key)
		var linear: float = clampf(float(value if value != null else 100) / 100.0, 0.0, 1.0)
		AudioServer.set_bus_mute(index, linear <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


func _on_settings_changed(key: String) -> void:
	if VOLUME_KEYS.has(key):
		apply_volumes()


func _connect_signals() -> void:
	var arg_counts: Dictionary[String, int] = {}
	for info: Dictionary in EventBus.get_signal_list():
		arg_counts[String(info["name"])] = (info["args"] as Array).size()
	var signals: Dictionary = _data.get("signals", {})
	for signal_name: String in signals:
		if not arg_counts.has(signal_name):
			push_warning("Audio: EventBus no tiene la señal %s" % signal_name)
			continue
		var sound_id: String = String(signals[signal_name])
		var callable: Callable = play.bind(sound_id)
		if arg_counts[signal_name] > 0:
			callable = callable.unbind(arg_counts[signal_name])
		EventBus.connect(signal_name, callable)


# La nómina pagada suena a caja; un pago obligatorio atrasado, a alarma.
func _on_payment_recorded(concept: String, on_time: bool) -> void:
	if not on_time:
		play(String(_data.get("late_payment_sound", "")))
	elif concept == Staff.CONCEPT_PAYROLL:
		play(String(_data.get("payroll_sound", "")))


# Todo botón suena al pulsarse (salvo los de la consola de desarrollo); las pestañas, al cambiar.
func _on_node_added(node: Node) -> void:
	if not (node is BaseButton or node is TabBar) or String(node.get_path()).contains("/Panku"):
		return
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("click"))
	else:
		(node as TabBar).tab_clicked.connect(play.bind("click").unbind(1))
