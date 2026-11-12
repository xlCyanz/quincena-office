# Prueba sin ventana del hito 18: entrega y reputación.
# Criterio: cada resultado de la tabla 7.4 paga y mueve la reputación como dice; un
# contrato con 3 días de atraso y 2 errores paga el 81%.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_delivery.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_preview()
	_check_deliver()
	_check_cancel()
	_check_client_cancel()
	_check_save()
	await _check_panel()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	_notices.clear()


# Un contrato en curso de $1,000 terminado, a tiempo y sin errores; cada prueba lo cambia.
func _contract(advance: int) -> Dictionary:
	var contract: Dictionary
	if Projects.contracts.is_empty():
		if Projects.offers.is_empty():
			Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
		Projects.accept(Projects.offers[0]["id"])
		contract = Projects.contracts[-1]
	else:
		# Con el tope lleno, una copia del que ya está con otro id.
		contract = Projects.contracts[0].duplicate(true)
		contract["id"] = 5000 + Projects.contracts.size()
		contract["team_id"] = Projects.NO_TEAM
		Projects.contracts.append(contract)
	contract["pay"] = 1000
	contract["advance"] = advance
	contract["points"] = {"design": 50, "programming": 100, "testing": 50}
	contract["total_points"] = 200
	contract["progress"] = {"design": 50.0, "programming": 100.0, "testing": 50.0}
	contract["deadline_day"] = GameClock.get_day_count() + 3
	return contract


func _check_preview() -> void:
	_new_game()
	var contract: Dictionary = _contract(0)
	var clean: Dictionary = Projects.preview_delivery(contract)
	_expect(clean["paid"] == 1000 and _near(clean["reputation_change"], 0.3) and clean["result"] == "a tiempo y limpio",
		"a tiempo y limpio: pago completo y +0.3: %s" % [clean])
	# A tiempo con errores: pago reducido y baja la reputación.
	contract["bugs_hidden"] = 1
	contract["bugs_found"] = 1
	contract["bugs_fixed"] = 5
	var known: Dictionary = Projects.preview_delivery(contract, true)
	_expect(known["bugs"] == 1 and known["paid"] == 980, "la vista del jugador no cuenta los ocultos: %s" % [known])
	var buggy: Dictionary = Projects.preview_delivery(contract)
	_expect(buggy["bugs"] == 2 and buggy["paid"] == 960 and _near(buggy["reputation_change"], -0.1)
		and buggy["result"] == "a tiempo, con 2 errores", "a tiempo con 2 errores: 96%% y −0.1: %s" % [buggy])
	# Tarde: 3 días de atraso y 2 errores pagan el 81%.
	contract["deadline_day"] = GameClock.get_day_count() - 3
	var late: Dictionary = Projects.preview_delivery(contract)
	_expect(late["late_days"] == 3 and late["gross"] == 810 and late["paid"] == 810 and _near(late["reputation_change"], -0.4),
		"3 días tarde y 2 errores: 81%% y −0.4: %s" % [late])
	contract["advance"] = 300
	_expect(Projects.preview_delivery(contract)["paid"] == 510, "el anticipo se resta del pago final")
	contract["advance"] = 900
	_expect(Projects.preview_delivery(contract)["paid"] == 0, "nunca menos de 0")
	# Topes: atraso 50% y errores 30%; la reputación baja hasta 0.5.
	contract["advance"] = 0
	contract["deadline_day"] = GameClock.get_day_count() - 20
	contract["bugs_hidden"] = 40
	var worst: Dictionary = Projects.preview_delivery(contract)
	_expect(_near(worst["late_penalty"], 0.5) and _near(worst["bug_penalty"], 0.3) and worst["paid"] == 200
		and _near(worst["reputation_change"], -0.5), "topes: %s" % [worst])
	# Incompleto: se paga en proporción y no sube la reputación.
	contract["deadline_day"] = GameClock.get_day_count() + 3
	contract["bugs_hidden"] = 0
	contract["bugs_found"] = 0
	contract["progress"] = {"design": 50.0, "programming": 50.0, "testing": 0.0}
	var half: Dictionary = Projects.preview_delivery(contract)
	_expect(_near(half["done"], 0.5) and half["paid"] == 500 and _near(half["reputation_change"], 0.0)
		and half["result"] == "a tiempo, incompleto (50%)", "incompleto: %s" % [half])


func _check_deliver() -> void:
	_new_game()
	var contract: Dictionary = _contract(300)
	contract["deadline_day"] = GameClock.get_day_count() - 3
	contract["bugs_found"] = 2
	var before: int = Economy.balance
	var result: Dictionary = Projects.deliver(contract["id"])
	_expect(result["ok"] and Economy.balance - before == 510, "cobra 81%% menos el anticipo: %d" % (Economy.balance - before))
	_expect(Economy.movements[-1]["concept"] == Projects.CONCEPT_DELIVERY, "movimiento de pago")
	_expect(Projects.contracts.is_empty() and Projects.delivered_count == 1, "deja de estar en curso")
	_expect(_near(Projects.reputation, 1.0), "la reputación no baja de 1")
	_expect(Projects.history.size() == 1 and Projects.history[0]["paid"] == 510
		and String(Projects.history[0]["result"]).contains("tarde (3 días)"), "historial: %s" % [Projects.history])
	_expect(not Projects.deliver(contract["id"])["ok"], "no se entrega dos veces")
	# Entregas limpias suben 0.3 cada una, hasta 5.
	for i: int in range(4):
		Projects.deliver(_contract(0)["id"])
	# Desde el hito 27 los medianos piden la etapa Startup (o un vendedor), no 2 estrellas.
	_expect(_near(Projects.reputation, 2.2) and not Projects.get_allowed_sizes().has("medium"), "4 limpias: 2.2 ★ (medianos desde Startup)")
	_expect(ProjectsPanel.stars(Projects.reputation) == "★★☆☆☆" and ProjectsPanel.stars(1.9) == "★☆☆☆☆", "estrellas enteras")
	Projects.reputation = 4.9
	Projects.deliver(_contract(0)["id"])
	_expect(_near(Projects.reputation, 5.0), "no pasa de 5")
	_expect(Projects.history.size() == 6 and Projects.delivered_count == 6, "historial y entregas")


func _check_cancel() -> void:
	_new_game()
	Projects.reputation = 3.0
	var contract: Dictionary = _contract(450)
	Economy.charge(Economy.balance - 100, "Prueba")
	var result: Dictionary = Projects.cancel(contract["id"])
	_expect(result["ok"] and Economy.balance == -350 and Economy.movements[-1]["concept"] == Projects.CONCEPT_REFUND,
		"cancelar devuelve el anticipo aunque quede negativo: %d" % Economy.balance)
	_expect(_near(Projects.reputation, 2.5) and Projects.contracts.is_empty(), "cae la reputación")
	_expect(Projects.history[0]["result"] == "Cancelado por la empresa" and Projects.history[0]["paid"] == -450, "historial")
	_expect(Projects.delivered_count == 0, "no cuenta como entregado")


func _check_client_cancel() -> void:
	_new_game()
	Projects.reputation = 3.0
	var contract: Dictionary = _contract(450)
	var contract_id: int = contract["id"]
	var deadline: int = contract["deadline_day"]
	var balance: int = Economy.balance
	# Hasta el día del plazo, nada.
	while GameClock.get_day_count() <= deadline:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(int(Projects.get_contract(contract_id).get("cancel_day", 0)) == Projects.NO_CANCEL_DAY, "a tiempo no se sortea")
	# Al pasar las 9 del primer día de atraso se sortea entre 3 y 10 días.
	var hours: int = posmod(int(ContractCatalog.get_offers("arrival_hour")) - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var cancel_day: int = int(Projects.get_contract(contract_id)["cancel_day"])
	_expect(cancel_day >= deadline + 3 and cancel_day <= deadline + 10, "sorteo entre 3 y 10 días: %d" % (cancel_day - deadline))
	_expect(_notices.any(func(text: String) -> bool: return text.contains("atrasado")), "aviso del atraso")
	while GameClock.get_day_count() < cancel_day:
		_expect(not Projects.get_contract(contract_id).is_empty(), "sigue antes del día %d" % cancel_day)
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(Projects.get_contract(contract_id).is_empty() and GameClock.get_day_count() == cancel_day, "ese día el cliente cancela")
	_expect(Economy.balance == balance and _near(Projects.reputation, 2.5), "no paga más, el anticipo queda y cae la reputación")
	_expect(Projects.history[0]["result"] == "Cancelado por el cliente", "historial")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("canceló")), "aviso de la cancelación")
	# Con la misma semilla, el mismo día.
	_new_game()
	contract = _contract(0)
	while Projects.get_days_late(contract) <= 0:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(int(contract["cancel_day"]) - int(contract["deadline_day"]) == cancel_day - deadline, "mismo sorteo con la misma semilla")


func _check_save() -> void:
	_new_game()
	Projects.deliver(_contract(0)["id"])
	var contract: Dictionary = _contract(0)
	contract["cancel_day"] = 77
	var before: String = JSON.stringify(Projects.export_state())
	_expect(SaveManager.save_game("slot_3"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_3"), "cargar")
	_expect(JSON.stringify(Projects.export_state()) == before and Projects.delivered_count == 1, "historial y sorteo vuelven igual")
	var old: Dictionary = Projects.export_state()
	old.erase("history")
	old.erase("delivered_count")
	(old["contracts"][0] as Dictionary).erase("cancel_day")
	Projects.import_state(old)
	_expect(Projects.history.is_empty() and Projects.delivered_count == 0
		and Projects.contracts[0]["cancel_day"] == Projects.NO_CANCEL_DAY, "partida vieja")


func _check_panel() -> void:
	_new_game()
	var contract: Dictionary = _contract(0)
	var other: Dictionary = _contract(200)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var hud: Hud = game.get_node("Hud")
	_expect(hud.get_reputation_text() == "★☆☆☆☆ 1", "reputación arriba a la izquierda: %s" % hud.get_reputation_text())
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Si entregas hoy: a tiempo y limpio; cobras hasta $1,000 · reputación hasta +0.3"),
		"vista previa: %s" % panel.get_list_text())
	await _click(panel.get_deliver_button(contract["id"]))
	_expect(Projects.get_contract(contract["id"]).is_empty() and panel.get_status_text().begins_with("Entregaste"),
		"entregar desde el panel: %s" % panel.get_status_text())
	await get_tree().process_frame
	_expect(hud.get_reputation_text() == "★☆☆☆☆ 1.3", "la reputación de arriba se actualiza: %s" % hud.get_reputation_text())
	_expect(panel.get_list_text().contains("Historial"), "historial en el panel")
	await _click(panel.get_cancel_button(other["id"]))
	await get_tree().process_frame
	_expect(not Projects.get_contract(other["id"]).is_empty() and panel.get_confirm_cancel_button() != null
		and panel.get_list_text().contains("Devuelves el anticipo de $200"), "cancelar pide confirmación")
	await _click(panel.get_confirm_cancel_button())
	_expect(Projects.get_contract(other["id"]).is_empty() and panel.get_status_text().begins_with("Cancelaste"), "cancelar confirmado")
	game.queue_free()
	await get_tree().process_frame


func _click(control: Control) -> void:
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent != null:
		(parent as ScrollContainer).ensure_control_visible(control)
		await get_tree().process_frame
		await get_tree().process_frame
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
