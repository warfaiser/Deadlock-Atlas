class_name CarAI
extends CarBase
## Бот-соперник. Наследник CarBase.
##
## Как едет:
##   1. PathFollow3D, привязанный к Path3D трассы, показывает точку впереди
##      (lookahead растёт со скоростью);
##   2. руль доворачивает на эту точку, смещённую на «свою полосу» (обгон +
##      случайное отклонение от идеальной линии);
##   3. газ/тормоз считаются от кривизны дороги впереди;
##   4. RayCast3D вперёд и по бортам: если впереди машина — перестраиваемся;
##   5. переворот дольше flip_respawn_delay или «залипание» — respawn на
##      последнем чекпоинте.
##
## Сложность (GameState.Difficulty): Easy 0.75x, Normal 0.9x, Hard 1.0x + агрессия.

## Бот возродился на чекпоинте. reason: "flip" или "stuck".
signal ai_respawned(reason: String)

@export_group("Пилотирование")
## Насколько резко бот крутит руль (рад ошибки -> доля руля).
@export_range(0.2, 6.0, 0.1) var steer_gain: float = 2.2
## Минимальная дистанция «взгляда» вперёд, метры.
@export_range(2.0, 40.0, 1.0) var lookahead_min: float = 7.0
## Сколько метров к lookahead добавляет каждый м/с скорости.
@export_range(0.1, 2.0, 0.05) var lookahead_per_speed: float = 0.6
## Запас скорости, после которого бот начинает тормозить (1.12 = +12%).
@export_range(1.0, 2.0, 0.01) var brake_margin: float = 1.12
## Угол поворота впереди, на котором бот режет скорость вдвое.
@export_range(0.2, 2.5, 0.05) var corner_angle_reference: float = 0.9
## Дистанция, на которой меряем кривизну.
@export_range(5.0, 60.0, 1.0) var corner_probe_distance: float = 26.0

@export_group("Обгон")
## Длина луча «впереди машина?», метры.
@export_range(4.0, 40.0, 1.0) var overtake_ray_length: float = 16.0
## Смещение в полосу при обгоне, метры.
@export_range(1.0, 12.0, 0.5) var overtake_lane_offset: float = 3.2
## Пауза между попытками перестроиться, секунды.
@export_range(0.2, 8.0, 0.1) var lane_change_cooldown: float = 1.6

@export_group("Восстановление")
## Сколько секунд лежим вверх колёсами до respawn.
@export_range(0.5, 10.0, 0.25) var flip_respawn_delay: float = 2.0
## Сколько секунд стоим на месте до respawn.
@export_range(1.0, 20.0, 0.5) var stuck_respawn_delay: float = 5.0
## Скорость, ниже которой бот считается застрявшим.
@export_range(0.1, 5.0, 0.1) var stuck_speed: float = 1.6

@export_group("Вариативность")
## Амплитуда случайного «виляния» по трассе, метры.
@export_range(0.0, 4.0, 0.1) var jitter_amplitude: float = 0.9

## Активная сложность (GameState.Difficulty).
var difficulty: int = 1
## Множитель максимальной скорости (0.75 / 0.9 / 1.0).
var speed_multiplier: float = 0.9
## Индивидуальное мастерство: у каждого бота своё, гонки не выглядят клонами.
var skill: float = 1.0
## Агрессия: смелость обгонов и ручника.
var aggression: float = 0.45
## Готов ли бот ехать (нужен setup_ai с Path3D).
var is_racing: bool = false

var _path: Path3D = null
var _curve: Curve3D = null
var _follower: PathFollow3D = null
var _track_length: float = 0.0
var _progress: float = 0.0
var _lane_offset: float = 0.0
var _target_lane: float = 0.0
var _home_lane: float = 0.0
var _jitter_phase: float = 0.0
var _jitter_speed: float = 0.6
var _time_alive: float = 0.0
var _lane_cooldown: float = 0.0
var _stuck_time: float = 0.0
var _ray_front: RayCast3D = null
var _ray_left: RayCast3D = null
var _ray_right: RayCast3D = null


func _physics_process(delta: float) -> void:
	_drive(delta)
	super._physics_process(delta)


## Подготовка бота к заезду.
func setup_ai(p_path: Path3D, p_difficulty: int, p_speed_multiplier: float, p_name: String) -> void:
	_path = p_path
	racer_name = p_name
	difficulty = p_difficulty
	speed_multiplier = clampf(p_speed_multiplier, 0.3, 1.2)
	if _path == null or _path.curve == null:
		push_warning("[CarAI] setup_ai: трасса без Curve3D, бот не поедет.")
		return
	_curve = _path.curve
	_track_length = _curve.get_baked_length()
	# Индивидуальность: мастерство, «домашняя» полоса, фаза виляния.
	skill = clampf(speed_multiplier * randf_range(0.94, 1.03), 0.4, 1.15)
	aggression = clampf(0.15 + difficulty * 0.3, 0.0, 1.0)
	_home_lane = randf_range(-1.0, 1.0) * minf(_lane_half_width(), 2.0)
	_jitter_phase = randf() * TAU
	_jitter_speed = randf_range(0.25, 0.7)
	_create_follower()
	_create_rays()
	is_racing = true


## Половина ширины полосы: не вылезаем за пределы дороги.
func _lane_half_width() -> float:
	return maxf(over_take_lane_offset * 0.6, 1.0)


func _create_follower() -> void:
	if _follower != null or _path == null:
		return
	_follower = PathFollow3D.new()
	_follower.name = "AIFollower_%s" % name
	_follower.loop = true
	_follower.rotation_mode = PathFollow3D.ROTATION_Y
	_path.add_child(_follower)


func _create_rays() -> void:
	_ray_front = _make_ray(Vector3(0, 0, -overtake_ray_length), "OvertakeFront")
	_ray_left = _make_ray(Vector3(-overtake_ray_length * 0.45, 0, -overtake_ray_length * 0.8), "OvertakeLeft")
	_ray_right = _make_ray(Vector3(overtake_ray_length * 0.45, 0, -overtake_ray_length * 0.8), "OvertakeRight")


## Луч ищет только машины (слой 2), стены и scenery игнорируются.
func _make_ray(target: Vector3, ray_name: String) -> RayCast3D:
	var ray := RayCast3D.new()
	ray.name = ray_name
	ray.target_position = target
	ray.collision_mask = 2
	ray.exclude_parent = true
	ray.enabled = true
	ray.collide_with_areas = false
	add_child(ray)
	return ray


func _exit_tree() -> void:
	# PathFollow3D живёт в Path3D трассы — убираем за собой.
	if _follower != null and is_instance_valid(_follower):
		_follower.queue_free()
		_follower = null


# --- Основная логика ---------------------------------------------------------


func _drive(delta: float) -> void:
	_time_alive += delta
	_lane_cooldown = maxf(0.0, _lane_cooldown - delta)
	if not is_racing or _curve == null or _follower == null:
		throttle = 0.0
		brake_input = 0.0
		steer_input = 0.0
		handbrake_input = false
		return

	_sync_progress()
	_update_recovery(delta)

	var speed := get_speed_mps()
	var lookahead := clampf(speed * lookahead_per_speed, lookahead_min, 34.0)
	_follower.progress = fposmod(_progress + lookahead, _track_length)

	_update_lane(delta, speed)
	_update_steering_target()
	_update_throttle(speed)


## Синхронизируем прогресс бота с его реальной позицией на кривой.
func _sync_progress() -> void:
	if _path == null or _curve == null:
		return
	var local_point := _path.global_transform.affine_inverse() * global_position
	_progress = clampf(_curve.get_closest_offset(local_point), 0.0, _track_length)


## Полоса: обгон + индивидуальное смещение + лёгкое виляние.
func _update_lane(delta: float, _speed: float) -> void:
	var jitter := sin(_time_alive * _jitter_speed * TAU * 0.15 + _jitter_phase) * jitter_amplitude
	var desired := _target_lane + _home_lane + jitter
	_lane_offset = move_toward(_lane_offset, desired, delta * (2.0 + aggression * 3.0))

	if _ray_front == null or not _ray_front.is_colliding():
		# Дорога чистая — постепенно возвращаемся на свою линию.
		_target_lane = move_toward(_target_lane, 0.0, delta * 2.0)
		return
	var blocker := _ray_front.get_collider()
	if not (blocker is CarBase) or _lane_cooldown > 0.0:
		return
	var side := _choose_overtake_side()
	if side != 0:
		_target_lane = side * overtake_lane_offset
		_lane_cooldown = lane_change_cooldown


## Куда свободнее: -1 вправо, +1 влево, 0 — оба борта заняты.
func _choose_overtake_side() -> int:
	var left_free := _ray_left != null and not _ray_left.is_colliding()
	var right_free := _ray_right != null and not _ray_right.is_colliding()
	if left_free and right_free:
		# Предпочитаем сторону, куда ближе текущее смещение (меньше манёвр).
		return 1 if _lane_offset >= 0.0 else -1
	if left_free:
		return 1
	if right_free:
		return -1
	return 0


## Руль: доворачиваем на точку впереди, смещённую в выбранную полосу.
func _update_steering_target() -> void:
	if _follower == null:
		steer_input = 0.0
		return
	var tangent := -_follower.global_basis.z
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		steer_input = 0.0
		return
	tangent = tangent.normalized()
	var right := tangent.cross(Vector3.UP)
	var target := _follower.global_position + right * _lane_offset
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		steer_input = 0.0
		return
	var angle := (-global_basis.z).signed_angle_to(to_target.normalized(), Vector3.UP)
	steer_input = clampf(angle * steer_gain, -1.0, 1.0)


## Газ и тормоз от кривизны дороги впереди.
func _update_throttle(speed: float) -> void:
	var corner := _measure_corner_ahead()
	var grip := clampf(surface_grip, 0.3, 1.4)
	var corner_factor := clampf(1.0 - corner / maxf(corner_angle_reference, 0.05), 0.32, 1.0)
	var limit := get_effective_max_speed() * skill * corner_factor * sqrt(grip)

	handbrake_input = false
	if corner > 0.75 and speed > 16.0 and aggression > 0.55 and absf(steer_input) > 0.6:
		handbrake_input = true  # «агрессивный» бот доворачивает ручником

	if speed > limit * brake_margin:
		throttle = 0.0
		brake_input = clampf((speed - limit) / maxf(limit * 0.35, 1.0), 0.15, 1.0)
	else:
		brake_input = 0.0
		throttle = 1.0 if speed < limit else 0.2


## Суммарный угол поворота трассы впереди, радианы.
func _measure_corner_ahead() -> float:
	var p0 := _point_at(_progress)
	var p1 := _point_at(_progress + corner_probe_distance * 0.5)
	var p2 := _point_at(_progress + corner_probe_distance)
	var d1 := p1 - p0
	var d2 := p2 - p1
	d1.y = 0.0
	d2.y = 0.0
	if d1.length_squared() < 0.01 or d2.length_squared() < 0.01:
		return 0.0
	return absf(d1.normalized().signed_angle_to(d2.normalized(), Vector3.UP))


func _point_at(offset: float) -> Vector3:
	if _path == null or _curve == null:
		return global_position
	return _path.to_global(_curve.sample_baked(fposmod(offset, _track_length)))


## Переворот и «залипание» — возвращаем бота на последний чекпоинт.
func _update_recovery(delta: float) -> void:
	if flipped_time > flip_respawn_delay:
		recover_to_last_checkpoint()
		_stuck_time = 0.0
		ai_respawned.emit("flip")
		return
	var speed := linear_velocity.length()
	if speed < stuck_speed and absf(throttle) > 0.3 and control_enabled:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)
	if _stuck_time > stuck_respawn_delay:
		recover_to_last_checkpoint()
		_stuck_time = 0.0
		ai_respawned.emit("stuck")


## Текущий прогресс в метрах от старта (для таблицы позиций).
func get_progress_offset() -> float:
	return _progress


## Полный прогресс: круги + метры текущего круга.
func get_total_progress(lap_index: int) -> float:
	return _progress + _track_length * float(maxi(0, lap_index - 1))
