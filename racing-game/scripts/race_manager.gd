extends Node3D
## RaceManager — дирижёр заезда (корень сцены Race.tscn).
##
## Отвечает за:
##   * сборку трассы из TrackData и расстановку на стартовой решётке;
##   * спавн игрока и 3–7 ботов (режим Race) или только игрока (Time Trial);
##   * отсчёт 3-2-1-GO;
##   * чекпоинты: порядок, штраф +5 секунд за пропуск, точка возрождения;
##   * круги и время (по LapTimer на гонщика), позиции в реальном времени;
##   * финиш, запись рекордов в user://records.cfg и переход в Results.
##
## Сцены машин и трассы — экспортируемые PackedScene, чтобы их можно было
## подменить прямо в инспекторе.

## Состояние заезда.
enum RaceState { LOADING, COUNTDOWN, RACING, FINISHED }

## Шаг отсчёта: 3, 2, 1 и 0 (= GO).
signal countdown_step(step: int)
signal race_started
signal racer_finished(racer_name: String, position: int, total_time: float)
signal race_completed(result: Dictionary)

const BOT_NAMES: Array[String] = ["Вихрь", "Стрела", "Гром", "Тень", "Искра", "Комета", "Фобос"]

@export_group("Сцены")
@export var track_scene: PackedScene = preload("res://assets/models/Track.tscn")
@export var player_scene: PackedScene = preload("res://assets/models/CarPlayer.tscn")
@export var ai_scene: PackedScene = preload("res://assets/models/CarAI.tscn")

@export_group("Правила")
## Длительность отсчёта, секунды.
@export_range(0.0, 10.0, 0.5) var countdown_seconds: float = 3.0
## Штраф за пропуск чекпоинта, секунды.
@export_range(0.0, 30.0, 0.5) var checkpoint_penalty: float = 5.0
## Задержка перед экраном результатов после финиша игрока.
@export_range(0.0, 10.0, 0.5) var results_delay: float = 2.5
## Сколько ботов выводить на старт; 0 — брать из GameState.bot_count.
@export_range(0, 7) var bots_override: int = 0

@onready var _track_root: Node3D = $TrackRoot
@onready var _cars_root: Node3D = $Cars
@onready var _timers_root: Node = $LapTimers
@onready var _hud: Node = $HUD
@onready var _pause_menu: Node = $PauseMenu

var state: RaceState = RaceState.LOADING
var track_data: TrackData = null
var player_car: CarBase = null

var _track: TrackBuilder = null
var _race_path: Path3D = null
var _race_curve: Curve3D = null
var _checkpoints: Array[Checkpoint] = []
var _racers: Array[Dictionary] = []
var _player_racer: Dictionary = {}
var _countdown_left: float = 0.0
var _last_countdown_step: int = -1
var _finish_counter: int = 0
var _track_length: float = 0.0
var _total_laps: int = 3
var _prev_player_offset: float = 0.0
var _wrong_way_time: float = 0.0


func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_INHERIT
	track_data = GameState.selected_track
	if track_data == null:
		push_error("[RaceManager] Не выбрана трасса — возвращаемся в меню.")
		GameState.goto_main_menu()
		return
	_total_laps = maxi(1, track_data.laps)
	_build_track()
	_spawn_racers()
	_setup_hud()
	_start_countdown()
	AudioManager.play_music(&"music_race", 1.2)


# --- Подготовка --------------------------------------------------------------


func _build_track() -> void:
	_track = track_scene.instantiate() as TrackBuilder
	if _track == null:
		push_error("[RaceManager] track_scene должен иметь скрипт TrackBuilder.")
		return
	_track_root.add_child(_track)
	_track.build(track_data)
	_race_path = _track.get_race_path()
	_race_curve = _track.race_curve
	_track_length = _track.track_length
	_checkpoints = _track.get_checkpoints()
	for checkpoint: Checkpoint in _checkpoints:
		if not checkpoint.car_passed.is_connected(_on_checkpoint_passed):
			checkpoint.car_passed.connect(_on_checkpoint_passed)


func _spawn_racers() -> void:
	var is_time_trial: bool = GameState.is_time_trial()
	var bots := 0
	if not is_time_trial:
		var wanted := bots_override if bots_override > 0 else GameState.bot_count
		bots = clampi(wanted, track_data.bots_min, track_data.bots_max)
		bots = clampi(bots, 3, 7)
	var total := 1 + bots

	for index in total:
		var is_player := index == 0
		var scene: PackedScene = player_scene if is_player else ai_scene
		var car := scene.instantiate() as CarBase
		if car == null:
			push_error("[RaceManager] Не удалось создать машину из сцены.")
			continue
		_cars_root.add_child(car)
		car.name = "PlayerCar" if is_player else "BotCar%02d" % index

		var car_stats := _pick_stats(index, is_player)
		car.setup(car_stats)
		car.surface_grip = track_data.surface_grip
		car.collision_layer = 2
		car.collision_mask = 3
		car.control_enabled = false
		var start := _track.get_start_transform(index, total)
		car.global_transform = start
		car.set_respawn_point(start)

		if not is_player:
			var ai := car as CarAI
			var bot_name := BOT_NAMES[(index - 1) % BOT_NAMES.size()]
			if ai != null:
				ai.setup_ai(_race_path, GameState.difficulty, GameState.difficulty_speed_multiplier(), bot_name)
				ai.ai_respawned.connect(_on_ai_respawned.bind(bot_name))
			else:
				car.racer_name = bot_name
		else:
			player_car = car

		var timer := LapTimer.new()
		timer.name = "Timer_%s" % car.name
		_timers_root.add_child(timer)
		timer.reset(_total_laps)

		var racer := {
			"car": car,
			"timer": timer,
			"name": car.racer_name,
			"is_player": is_player,
			"position": index + 1,
			"finished": false,
			"finish_order": 0,
			"total_time": 0.0,
			"total_progress": 0.0,
			"penalty": 0.0,
			"lane": index % 2,
			# Следующий ожидаемый чекпоинт. Стартуем ПЕРЕД линией, поэтому
			# первым ждём чекпоинт 1, а не 0.
			"next_checkpoint": 1,
			"start_line_passed": false,
		}
		if is_player:
			_player_racer = racer
		_racers.append(racer)


## Игрок едет на выбранной машине, боты — на случайных из гаража.
func _pick_stats(index: int, is_player: bool) -> CarStats:
	if is_player:
		return GameState.selected_car
	var catalog: Array[CarStats] = GameState.cars
	if catalog.is_empty():
		return GameState.selected_car
	return catalog[(index * 3 + randi() % catalog.size()) % catalog.size()]


func _setup_hud() -> void:
	if _hud != null and _hud.has_method("setup"):
		_hud.call("setup", self, player_car)


# --- Отсчёт и старт ----------------------------------------------------------


func _start_countdown() -> void:
	state = RaceState.COUNTDOWN
	_countdown_left = countdown_seconds
	_last_countdown_step = -1
	if _hud != null and _hud.has_method("show_countdown"):
		_hud.call("show_countdown", int(ceil(_countdown_left)))
	AudioManager.play_sfx(&"countdown", 2.0)


func _begin_race() -> void:
	state = RaceState.RACING
	for racer: Dictionary in _racers:
		racer["car"].control_enabled = true
		racer["timer"].start()
	if _hud != null and _hud.has_method("show_go"):
		_hud.call("show_go")
	race_started.emit()


# --- Кадр --------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if state == RaceState.COUNTDOWN:
		_process_countdown(delta)
	elif state == RaceState.RACING or state == RaceState.FINISHED:
		_update_positions()
		_check_wrong_way(delta)
	if _hud != null and _hud.has_method("update_hud"):
		_hud.call("update_hud")


func _process_countdown(delta: float) -> void:
	_countdown_left -= delta
	var step := int(ceil(_countdown_left))
	if step != _last_countdown_step:
		_last_countdown_step = step
		countdown_step.emit(step)
		if _hud != null and _hud.has_method("show_countdown"):
			_hud.call("show_countdown", step)
	if _countdown_left <= 0.0:
		_begin_race()


## Позиции: сначала финишировавшие (по порядку финиша), остальные — по прогрессу.
func _update_positions() -> void:
	for racer: Dictionary in _racers:
		racer["total_progress"] = _total_progress_of(racer)
	var finished: Array[Dictionary] = []
	var running: Array[Dictionary] = []
	for racer: Dictionary in _racers:
		if racer["finished"]:
			finished.append(racer)
		else:
			running.append(racer)
	finished.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["finish_order"] < b["finish_order"])
	running.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total_progress"] > b["total_progress"])
	var order: Array[Dictionary] = []
	order.append_array(finished)
	order.append_array(running)
	for index in order.size():
		order[index]["position"] = index + 1


func _total_progress_of(racer: Dictionary) -> float:
	var car: CarBase = racer["car"]
	if car == null:
		return 0.0
	var offset := _offset_of(car)
	var lap_index: int = racer["timer"].current_lap
	return offset + _track_length * float(maxi(0, lap_index - 1))


## Расстояние от старта до проекции машины на гоночную линию.
func _offset_of(car: CarBase) -> float:
	if _race_curve == null or _race_path == null:
		return 0.0
	if car is CarAI:
		return (car as CarAI).get_progress_offset()
	var local_point := _race_path.global_transform.affine_inverse() * car.global_position
	return clampf(_race_curve.get_closest_offset(local_point), 0.0, _track_length)


## Подсказка «Не туда!», если игрок едет против шерсти.
func _check_wrong_way(delta: float) -> void:
	if _player_racer.is_empty() or _player_racer["finished"]:
		return
	var offset := _offset_of(_player_racer["car"])
	var delta_offset := offset - _prev_player_offset
	_prev_player_offset = offset
	# Скачок через ноль (пересечение линии старта) не считаем разворотом.
	if absf(delta_offset) > _track_length * 0.5:
		return
	if delta_offset < -0.35 and _player_racer["car"].get_speed_mps() > 4.0:
		_wrong_way_time += delta
	else:
		_wrong_way_time = maxf(0.0, _wrong_way_time - delta * 2.0)
	if _wrong_way_time > 1.2 and _hud != null and _hud.has_method("show_message"):
		_hud.call("show_message", "НЕ ТУДА!", 0.4)
		_wrong_way_time = 0.8


# --- Чекпоинты и круги -------------------------------------------------------


func _on_checkpoint_passed(checkpoint: Checkpoint, car: CarBase) -> void:
	if state != RaceState.RACING:
		return
	var racer := _racer_of(car)
	if racer.is_empty() or bool(racer["finished"]):
		return
	var count := _checkpoints.size()
	if count == 0:
		return
	var expected: int = racer["next_checkpoint"]

	# Штатное прохождение: точка совпала с ожидаемой.
	if checkpoint.index == expected:
		racer["next_checkpoint"] = (expected + 1) % count
		car.set_respawn_point(checkpoint.get_respawn_transform(_lane_offset_for(racer)))
		# Чекпоинт 0 — линия старта/финиша: замыкает круг.
		if checkpoint.index == 0:
			_complete_lap(racer)
		elif bool(racer["is_player"]):
			AudioManager.play_sfx(&"checkpoint", -12.0, 1.25)
		return

	# Старт: машины стоят перед линией и пересекают её сразу после «GO».
	# Это не круг и не штраф — просто отмечаем факт.
	if checkpoint.index == 0 and expected == 1 and not bool(racer["start_line_passed"]):
		racer["start_line_passed"] = true
		return

	# Пропуск чекпоинта: штраф +5 секунд и перенос указателя.
	var timer: LapTimer = racer["timer"]
	timer.add_penalty(checkpoint_penalty)
	racer["penalty"] = float(racer["penalty"]) + checkpoint_penalty
	racer["next_checkpoint"] = (checkpoint.index + 1) % count
	if bool(racer["is_player"]) and _hud != null:
		if _hud.has_method("show_message"):
			_hud.call("show_message", "Пропущен чекпоинт: +%.0f сек" % checkpoint_penalty, 2.0)
		if _hud.has_method("flash_penalty"):
			_hud.call("flash_penalty")


func _complete_lap(racer: Dictionary) -> void:
	var timer: LapTimer = racer["timer"]
	var info := timer.complete_lap()
	if racer["is_player"]:
		if _hud != null and _hud.has_method("notify_lap"):
			_hud.call("notify_lap", info)
		AudioManager.play_sfx(&"checkpoint", -4.0, 1.0 if not info["is_best"] else 1.45)
	if bool(info["finished"]):
		_finish_racer(racer)


func _finish_racer(racer: Dictionary) -> void:
	_finish_counter += 1
	racer["finished"] = true
	racer["finish_order"] = _finish_counter
	racer["total_time"] = float(racer["timer"].get_total_with_penalty())
	racer["car"].control_enabled = false
	racer_finished.emit(racer["name"], racer["position"], racer["total_time"])
	if racer["is_player"]:
		state = RaceState.FINISHED
		_finish_player_race()


func _finish_player_race() -> void:
	if _hud != null and _hud.has_method("show_message"):
		_hud.call("show_message", "ФИНИШ!", 2.5)
	AudioManager.stop_music(1.2)
	await get_tree().create_timer(results_delay).timeout
	if not is_inside_tree():
		return
	_submit_results()


## Собирает итоги, пишет рекорды и отдаёт их в Results.tscn.
func _submit_results() -> void:
	var standings := get_standings()
	var player_index := 0
	for index in standings.size():
		if bool(standings[index]["is_player"]):
			player_index = index
			break
	var player_row: Dictionary = standings[player_index]
	var timer: LapTimer = _player_racer["timer"]
	var records := Records.submit_result(
		track_data.id,
		GameState.selected_car.id,
		float(player_row["total_time"]),
		timer.best_lap_time,
		int(player_row["position"])
	)
	var result := {
		"track_id": track_data.id,
		"track_name": track_data.display_name,
		"car_id": GameState.selected_car.id,
		"car_name": GameState.selected_car.display_name,
		"mode": "Time Trial" if GameState.is_time_trial() else "Гонка",
		"difficulty": GameState.difficulty_name(),
		"laps": _total_laps,
		"position": int(player_row["position"]),
		"total_racers": _racers.size(),
		"total_time": float(player_row["total_time"]),
		"best_lap": timer.best_lap_time,
		"penalty": float(_player_racer["penalty"]),
		"new_lap_record": bool(records["new_lap"]),
		"new_total_record": bool(records["new_total"]),
		"new_position_record": bool(records["new_position"]),
		"rows": standings,
	}
	race_completed.emit(result)
	GameState.show_results(result)


func _racer_of(car: CarBase) -> Dictionary:
	for racer: Dictionary in _racers:
		if racer["car"] == car:
			return racer
	return {}


func _lane_offset_for(racer: Dictionary) -> float:
	var lane: int = racer.get("lane", 0)
	return track_data.road_width * 0.35 * (1.0 if lane == 0 else -1.0)


func _on_ai_respawned(reason: String, bot_name: String) -> void:
	if _hud != null and _hud.has_method("show_message"):
		_hud.call("show_message", "%s: восстановление (%s)" % [bot_name, reason], 1.0)


# --- Публичный API для HUD ---------------------------------------------------


func get_standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for racer: Dictionary in _racers:
		var timer: LapTimer = racer["timer"]
		rows.append({
			"name": racer["name"],
			"is_player": racer["is_player"],
			"position": int(racer["position"]),
			"finished": racer["finished"],
			"total_time": float(racer["total_time"]) if racer["finished"] else timer.get_total_with_penalty(),
			"best_lap": timer.best_lap_time,
			"lap": timer.current_lap,
			"progress": float(racer["total_progress"]),
			"gap": 0.0,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["position"] < b["position"])
	# Отставание от лидера в секундах: разница прогресса в метрах / скорость лидера.
	var leader_speed := 30.0
	if player_car != null:
		leader_speed = maxf(player_car.get_speed_mps(), 15.0)
	if not rows.is_empty():
		var leader_progress := float(rows[0]["progress"])
		for index in range(1, rows.size()):
			rows[index]["gap"] = maxf(0.0, (leader_progress - float(rows[index]["progress"])) / leader_speed)
	return rows


func get_player_racer() -> Dictionary:
	return _player_racer


func get_total_laps() -> int:
	return _total_laps


func get_track_length() -> float:
	return _track_length


func get_checkpoint_count() -> int:
	return _checkpoints.size()


func get_race_path() -> Path3D:
	return _race_path


func get_track_builder() -> TrackBuilder:
	return _track


## Рестарт: просто перезагружаем сцену заезда.
func restart_race() -> void:
	GameState.start_race()


# --- Пауза -------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state == RaceState.FINISHED:
		return
	if event.is_action_pressed(&"pause") and _pause_menu != null and _pause_menu.has_method("toggle"):
		_pause_menu.call("toggle")
