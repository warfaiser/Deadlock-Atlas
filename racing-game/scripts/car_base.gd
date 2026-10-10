class_name CarBase
extends VehicleBody3D
## Базовый класс машины (VehicleBody3D + 4 колеса VehicleWheel3D).
##
## Что здесь есть:
##   * разгон / торможение / реверс / ручник (Space);
##   * наклон кузова (body roll + pitch) через lerp;
##   * дым из-под колёс при пробуксовке (GPUParticles3D);
##   * следы шин (ImmediateMesh-«decal» в мире, SkidTrail);
##   * звук двигателя: AudioStreamPlayer3D с pitch_scale 0.7–2.0 от скорости;
##   * повреждения: при ударе падает максимальная скорость и сыплются искры;
##   * телепорт на чекпоинт (respawn) и проверка «машина перевёрнута».
##
## Ввод сюда не приходит: подклассы (CarPlayer / CarAI) каждый физический кадр
## заполняют throttle / brake_input / steer_input / handbrake_input, а остальное
## делает _physics_process().

## Удар о препятствие. impact — условная сила удара (больше = сильнее).
signal crashed(impact: float)
## Изменилось состояние кузова (для HUD и эффектов).
signal health_changed(health: float, health_max: float)
## Изменилась скорость в м/с (для спидометра).
signal speed_changed(speed_mps: float)

## Порядок колёс во всех массивах: FL, FR, RL, RR.
const WHEEL_NAMES: Array[String] = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]

## Передаточные числа «коробки» — только для тахометра и звука.
const GEAR_RATIOS: Array[float] = [3.6, 2.4, 1.7, 1.25, 1.0, 0.8]
const FINAL_DRIVE: float = 3.2
const IDLE_RPM: float = 800.0
const MAX_RPM: float = 7200.0

@export_group("Данные")
## Характеристики машины. Задаётся вызовом setup(), но можно назначить и в сцене.
@export var stats: CarStats = null

@export_group("Управление")
## Лимит скорости руля (рад/с) — насколько быстро колёса доворачивают.
@export_range(1.0, 30.0, 0.5) var steer_response: float = 12.0
## Скорость, на которой руль становится «короче» (доля от максималки).
@export_range(0.1, 1.0, 0.05) var steering_falloff_speed: float = 0.6
## Минимальный угол руля на высокой скорости (доля от max_steering).
@export_range(0.15, 1.0, 0.05) var steering_min_ratio: float = 0.42
## Доля максималки для реверса.
@export_range(0.1, 1.0, 0.05) var reverse_speed_ratio: float = 0.35
## Сила реверса относительно силы тяги.
@export_range(0.1, 1.5, 0.05) var reverse_force_scale: float = 0.6

@export_group("Визуал")
## Максимальный крен кузова, радианы.
@export_range(0.0, 0.6, 0.01) var max_body_roll: float = 0.14
## Максимальный тангаж (клевки при разгоне/торможении), радианы.
@export_range(0.0, 0.4, 0.01) var max_body_pitch: float = 0.07
## Скорость возврата кузова в нейтраль.
@export_range(1.0, 20.0, 0.5) var body_lean_speed: float = 7.0
## Рисовать ли следы шин.
@export var skid_marks_enabled: bool = true
## Порог проскальзывания, после которого появляются следы и дым.
@export_range(0.0, 1.0, 0.01) var skid_threshold: float = 0.28

@export_group("Звук")
## Диапазон pitch_scale двигателя (по ТЗ: 0.7–2.0).
@export_range(0.3, 2.0, 0.05) var engine_pitch_min: float = 0.7
@export_range(0.5, 3.0, 0.05) var engine_pitch_max: float = 2.0
@export_range(-60.0, 6.0, 1.0) var engine_volume_db: float = -6.0

@export_group("Повреждения")
## Минимальная сила удара, которая считается аварией.
@export_range(0.0, 20.0, 0.5) var crash_threshold: float = 4.0
## Сколько «здоровья» снимает удар единичной силы.
@export_range(0.01, 10.0, 0.01) var damage_per_impact: float = 0.55

# --- Состояние, которое заполняют подклассы ----------------------------------
## Газ: -1.0 (реверс) .. 1.0 (вперёд).
var throttle: float = 0.0
## Педаль тормоза: 0.0 .. 1.0.
var brake_input: float = 0.0
## Руль: -1.0 (вправо) .. 1.0 (влево).
var steer_input: float = 0.0
## Ручник.
var handbrake_input: bool = false
## Пока false — машина не реагирует на ввод (отсчёт 3-2-1, финиш, пауза).
var control_enabled: bool = false

# --- Производные значения ----------------------------------------------------
var health: float = 100.0
var health_max: float = 100.0
var max_speed: float = 55.0
var current_gear: int = 1
var current_rpm: float = IDLE_RPM
var is_skidding: bool = false
## Сколько секунд машина лежит вверх колёсами.
var flipped_time: float = 0.0
## Последний чекпоинт — сюда телепортируемся при восстановлении.
var last_respawn_transform: Transform3D = Transform3D.IDENTITY
## Имя гонщика (для таблицы результатов).
var racer_name: String = "Игрок"
## Множитель сцепления покрытия трассы (снег < 1.0, асфальт = 1.0).
var surface_grip: float = 1.0

# --- Внутренние ссылки -------------------------------------------------------
var _wheels: Array[VehicleWheel3D] = []
var _wheel_meshes: Array[Node3D] = []
var _body_visual: Node3D = null
var _engine_audio: AudioStreamPlayer3D = null
var _squeal_audio: AudioStreamPlayer3D = null
var _smoke: GPUParticles3D = null
var _sparks: GPUParticles3D = null
var _paint_material: StandardMaterial3D = null
var _skid_trail: SkidTrail = null

var _engine_force_max: float = 800.0
var _brake_force_max: float = 40.0
var _prev_speed: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _speed_smooth: float = 0.0
var _roll_visual: float = 0.0
var _pitch_visual: float = 0.0
var _skid_amount: float = 0.0
var _crash_cooldown: float = 0.0
var _spark_timer: float = 0.0
var _last_ground_point_left: Vector3 = Vector3.INF
var _last_ground_point_right: Vector3 = Vector3.INF


func _ready() -> void:
	_cache_nodes()
	if stats != null:
		setup(stats)
	else:
		health_max = health
		max_speed = 55.0
	_apply_paint()
	_prepare_audio()
	_prepare_particles()
	_prepare_skid_trail()
	last_respawn_transform = global_transform
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Кэширует узлы из Car.tscn по относительным путям.
func _cache_nodes() -> void:
	_wheels.clear()
	_wheel_meshes.clear()
	for wheel_name: String in WHEEL_NAMES:
		var wheel := get_node_or_null(wheel_name) as VehicleWheel3D
		if wheel == null:
			push_warning("[CarBase] Не найдено колесо %s" % wheel_name)
			continue
		_wheels.append(wheel)
		var mesh := wheel.get_node_or_null("WheelMesh") as Node3D
		_wheel_meshes.append(mesh if mesh != null else wheel)
	_body_visual = get_node_or_null("BodyVisual") as Node3D
	_engine_audio = get_node_or_null("EngineAudio") as AudioStreamPlayer3D
	_squeal_audio = get_node_or_null("SquealAudio") as AudioStreamPlayer3D
	_smoke = get_node_or_null("TireSmoke") as GPUParticles3D
	_sparks = get_node_or_null("ImpactSparks") as GPUParticles3D


## Применяет характеристики: массу, подвеску, сцепление, привод, цвета.
func setup(p_stats: CarStats) -> void:
	if p_stats == null:
		return
	stats = p_stats
	mass = stats.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Низкий центр тяжести: меньше кувырков на дугах.
	center_of_mass = Vector3(0.0, -0.25, 0.0)
	health_max = stats.health_max
	health = stats.health_max
	max_speed = stats.max_speed
	_engine_force_max = stats.max_engine_force * stats.engine_force_multiplier
	_brake_force_max = stats.brake_force * stats.brake_multiplier
	racer_name = stats.display_name

	for index in _wheels.size():
		var wheel := _wheels[index]
		var is_front: bool = index < 2
		wheel.wheel_radius = stats.wheel_radius
		wheel.wheel_rest_length = stats.wheel_rest_length
		wheel.suspension_stiffness = stats.suspension_stiffness
		wheel.suspension_travel = stats.suspension_travel
		wheel.damping_compression = stats.damping_compression
		wheel.damping_relaxation = stats.damping_relaxation
		var base_slip := stats.wheel_friction_front if is_front else stats.wheel_friction_rear
		wheel.wheel_friction_slip = base_slip * _grip_scale()
		wheel.wheel_roll_influence = stats.wheel_roll_influence
		wheel.use_as_steering = is_front
		wheel.use_as_traction = _is_traction_wheel(index)
	_apply_paint()


## Какие колёса тяговые для выбранного привода. index: 0=FL 1=FR 2=RL 3=RR.
func _is_traction_wheel(index: int) -> bool:
	if stats == null:
		return index >= 2
	match stats.drivetrain:
		CarStats.Drivetrain.RWD:
			return index >= 2
		CarStats.Drivetrain.FWD:
			return index < 2
		CarStats.Drivetrain.AWD:
			return true
	return index >= 2


# --- Главный цикл ------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_prev_velocity = linear_velocity
	var speed_before := linear_velocity.length()
	_prev_speed = speed_before

	_apply_drivetrain(delta)
	_update_steering(delta)
	_update_damage(delta)

	var speed_now := linear_velocity.length()
	_speed_smooth = lerpf(_speed_smooth, speed_now, clampf(delta * 8.0, 0.0, 1.0))
	_update_gearbox()
	_update_visuals(delta)
	_update_audio(delta)
	_update_skid_state(delta)
	if skid_marks_enabled and is_skidding:
		_stamp_skid_marks()

	# Резкое падение скорости = столкновение (дополнительно к body_entered).
	var impact := (speed_before - speed_now)
	if impact > crash_threshold and _crash_cooldown <= 0.0:
		take_damage(impact, true)
	speed_changed.emit(_speed_smooth)


## Тяга, тормоза и ручник.
func _apply_drivetrain(_delta: float) -> void:
	var forward := -global_basis.z
	var velocity_forward := linear_velocity.dot(forward)
	var effective_max_speed := get_effective_max_speed()

	var throttle_value := throttle
	var brake_value := brake_input
	var handbrake_now := handbrake_input

	# Нет управления (отсчёт, финиш, пауза) — катимся и тормозим.
	if not control_enabled:
		throttle_value = 0.0
		brake_value = 1.0
		handbrake_now = true

	# Педаль тормоза на почти стоящей машине превращается в реверс.
	if brake_value > 0.05 and throttle_value <= 0.0 and velocity_forward < 1.2:
		throttle_value = -brake_value
		brake_value = 0.0

	var force := 0.0
	if throttle_value > 0.0:
		# Плавное обрезание тяги у максимальной скорости.
		var margin := clampf(1.0 - velocity_forward / maxf(effective_max_speed, 1.0), 0.0, 1.0)
		force = throttle_value * _engine_force_max * smoothstep(0.0, 0.12, margin)
	elif throttle_value < 0.0:
		var reverse_limit := -effective_max_speed * reverse_speed_ratio
		if velocity_forward > reverse_limit:
			force = throttle_value * _engine_force_max * reverse_force_scale

	if handbrake_now:
		force = 0.0

	engine_force = force
	# Базовое торможение идёт на все колёса; ручник дожимает заднюю ось.
	brake = brake_value * _brake_force_max

	var rear_brake := 0.0
	var rear_grip := 1.0
	if handbrake_now:
		rear_brake = _brake_force_max * 1.6
		rear_grip = 0.35  # ломаем сцепление задней оси — начинается занос
	_apply_rear_wheel_override(rear_brake, rear_grip)

	_apply_aerodynamics(forward, velocity_forward)


## Задним колёсам вручную выставляем тормоз и сцепление (ручник / занос).
func _apply_rear_wheel_override(rear_brake: float, grip_multiplier: float) -> void:
	if _wheels.size() < 4 or stats == null:
		return
	for index in [2, 3]:
		var wheel := _wheels[index]
		wheel.brake = rear_brake
		wheel.wheel_friction_slip = stats.wheel_friction_rear * grip_multiplier * _grip_scale()
	# Передние возвращаем к норме, если ручник отпущен.
	if rear_brake <= 0.0:
		for index in [0, 1, 2, 3]:
			var base := stats.wheel_friction_front if index < 2 else stats.wheel_friction_rear
			_wheels[index].wheel_friction_slip = base * _grip_scale()
			_wheels[index].brake = 0.0


## Влияние покрытия трассы на сцепление (снег скользкий).
## Задаётся RaceManager'ом из TrackData.surface_grip.
func _grip_scale() -> float:
	return surface_grip


## Сопротивление воздуха и прижимная сила.
func _apply_aerodynamics(forward: Vector3, velocity_forward: float) -> void:
	if stats == null:
		return
	var drag_force := -forward * stats.drag_coefficient * velocity_forward * absf(velocity_forward)
	apply_central_force(drag_force)
	# Прижимная сила: на скорости машина «прилипает» к асфальту.
	var downforce := Vector3.DOWN * velocity_forward * velocity_forward * 0.02 * (mass / 1200.0)
	apply_central_force(downforce)


## Руль: доворот к цели + уменьшение угла на скорости.
func _update_steering(delta: float) -> void:
	if stats == null:
		return
	var speed := _speed_smooth
	var falloff_speed := maxf(max_speed * steering_falloff_speed, 1.0)
	var ratio := lerpf(1.0, steering_min_ratio, clampf(speed / falloff_speed, 0.0, 1.0))
	var target := steer_input * stats.max_steering * ratio
	if not control_enabled:
		target = 0.0
	steering = move_toward(steering, target, steer_response * delta * maxf(stats.max_steering, 0.1))


# --- Скорость, коробка, тахометр ---------------------------------------------


func get_speed_mps() -> float:
	return _speed_smooth


func get_speed_kmh() -> float:
	return _speed_smooth * 3.6


## Текущая передача 1..6 (псевдо-КПП для тахометра).
func get_gear() -> int:
	return current_gear


func get_rpm() -> float:
	return current_rpm


## Доля оборотов 0..1 — для стрелки тахометра.
func get_rpm_ratio() -> float:
	return clampf((current_rpm - IDLE_RPM) / (MAX_RPM - IDLE_RPM), 0.0, 1.0)


func _update_gearbox() -> void:
	var wheel_circumference := TAU * (stats.wheel_radius if stats != null else 0.35)
	var wheel_rps := _speed_smooth / maxf(wheel_circumference, 0.01)
	var speed_ratio := clampf(_speed_smooth / maxf(max_speed, 1.0), 0.0, 1.0)
	current_gear = clampi(int(floor(speed_ratio * GEAR_RATIOS.size())) + 1, 1, GEAR_RATIOS.size())
	var ratio: float = GEAR_RATIOS[current_gear - 1]
	current_rpm = clampf(IDLE_RPM + wheel_rps * 60.0 * ratio * FINAL_DRIVE * 0.35, IDLE_RPM, MAX_RPM)


## Максимальная скорость с учётом повреждений.
func get_effective_max_speed() -> float:
	if stats == null:
		return max_speed
	var damage_ratio := 1.0 - (1.0 - get_health_ratio()) * stats.damage_speed_loss
	return max_speed * clampf(damage_ratio, 0.2, 1.0)


func get_health_ratio() -> float:
	return clampf(health / maxf(health_max, 0.001), 0.0, 1.0)


# --- Повреждения -------------------------------------------------------------


func _update_damage(delta: float) -> void:
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	_spark_timer = maxf(0.0, _spark_timer - delta)
	if _spark_timer <= 0.0 and _sparks != null:
		_sparks.emitting = false
	# Перевёрнутая машина: копим время (для ИИ и подсказки игроку).
	if is_flipped():
		flipped_time += delta
	else:
		flipped_time = 0.0


## Наносит урон. impact — условная сила удара.
func take_damage(impact: float, play_sound: bool = true) -> void:
	if impact <= 0.0:
		return
	var damage := impact * damage_per_impact * 10.0
	health = clampf(health - damage, 0.0, health_max)
	_crash_cooldown = 0.25
	_spark_timer = 0.35
	if _sparks != null:
		_sparks.emitting = true
		_sparks.restart()
	if play_sound:
		# Громкость удара зависит от силы: от -18 дБ до 0 дБ.
		var volume := clampf(-18.0 + impact * 2.2, -18.0, 2.0)
		AudioManager.play_sfx_3d(&"crash", self, volume, randf_range(0.92, 1.08))
	health_changed.emit(health, health_max)
	crashed.emit(impact)


func repair(full: bool = false) -> void:
	health = health_max if full else clampf(health + health_max * 0.25, 0.0, health_max)
	health_changed.emit(health, health_max)


func _on_body_entered(body: Node) -> void:
	# body_entered не даёт силу удара, поэтому берём падение скорости за кадр.
	var delta_velocity := (_prev_velocity - linear_velocity).length()
	var impact := delta_velocity + linear_velocity.length() * 0.15
	if impact < crash_threshold:
		return
	take_damage(impact)
	if body is VehicleBody3D:
		# Толкаем того, кого задели, чтобы машины не «слипались».
		var other := body as VehicleBody3D
		var push := (other.global_position - global_position).normalized() * impact * 6.0
		other.apply_central_impulse(push + Vector3.UP * impact * 2.0)


# --- Восстановление ----------------------------------------------------------


func is_flipped() -> bool:
	return global_basis.y.dot(Vector3.UP) < 0.1


## Мгновенная установка на точку возрождения.
func respawn_at(transform: Transform3D) -> void:
	global_transform = transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	brake = 0.0
	steering = 0.0
	throttle = 0.0
	brake_input = 0.0
	steer_input = 0.0
	flipped_time = 0.0
	_last_ground_point_left = Vector3.INF
	_last_ground_point_right = Vector3.INF
	if _skid_trail != null:
		_skid_trail.break_strip()


## Возврат на последний чекпоинт (кнопка R или авто-восстановление бота).
func recover_to_last_checkpoint() -> void:
	respawn_at(last_respawn_transform)


func set_respawn_point(transform: Transform3D) -> void:
	last_respawn_transform = transform


# --- Визуал ------------------------------------------------------------------


func _update_visuals(delta: float) -> void:
	# Вращение колёс пропорционально скорости.
	var wheel_mesh: Node3D
	for index in _wheel_meshes.size():
		wheel_mesh = _wheel_meshes[index]
		if wheel_mesh == null or index >= _wheels.size():
			continue
		var radius: float = stats.wheel_radius if stats != null else 0.35
		var angular_speed := _speed_smooth / maxf(radius, 0.05)
		var spin := Basis(Vector3.RIGHT, angular_speed * delta)
		wheel_mesh.transform.basis = spin * wheel_mesh.transform.basis

	if _body_visual == null:
		return
	# Крен кузова: наружу от поворота, плавно через lerp.
	var speed_factor := clampf(_speed_smooth / maxf(max_speed, 1.0), 0.0, 1.0)
	var target_roll := steer_input * max_body_roll * speed_factor
	# Тангаж: клюём носом при торможении, задираем при разгоне.
	var accel := clampf((linear_velocity.length() - _prev_speed) / maxf(delta, 0.0001) / 20.0, -1.0, 1.0)
	var target_pitch := clampf(accel, -1.0, 1.0) * max_body_pitch
	var blend := clampf(delta * body_lean_speed, 0.0, 1.0)
	_roll_visual = lerpf(_roll_visual, target_roll, blend)
	_pitch_visual = lerpf(_pitch_visual, target_pitch, blend)
	_body_visual.rotation.z = _roll_visual
	_body_visual.rotation.x = _pitch_visual


## Краска кузова: PBR с clearcoat (лаком) и нормал-маппингом.
func _apply_paint() -> void:
	if _body_visual == null:
		return
	var chassis := _body_visual.get_node_or_null("Chassis") as MeshInstance3D
	if chassis == null:
		return
	var material := chassis.get_active_material(0) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		chassis.material_override = material
	else:
		material = material.duplicate(true) as StandardMaterial3D
		chassis.material_override = material
	material.metallic = 0.85
	material.roughness = 0.28
	material.clearcoat_enabled = true
	material.clearcoat = 1.0
	material.clearcoat_roughness = 0.06
	material.normal_enabled = true
	material.normal_scale = 0.35
	# Процедурная «шагрень» краски вместо внешней нормал-текстуры.
	material.normal_texture = _paint_noise_texture()
	if stats != null:
		material.albedo_color = stats.body_color
	_paint_material = material
	# Акценты (диски/спойлер) красим вторым цветом.
	var accent := _body_visual.get_node_or_null("Spoiler") as MeshInstance3D
	if accent != null and stats != null:
		var accent_material := StandardMaterial3D.new()
		accent_material.albedo_color = stats.accent_color
		accent_material.metallic = 0.4
		accent_material.roughness = 0.5
		accent.material_override = accent_material


## Плоская шумовая текстура 64×64 для нормал-карты краски.
func _paint_noise_texture() -> ImageTexture:
	var size := 64
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var noise := randf_range(-1.0, 1.0) * 12.0
			image.set_pixel(x, y, Color(0.5 + noise / 255.0, 0.5 + noise / 255.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


# --- Звук --------------------------------------------------------------------


func _prepare_audio() -> void:
	var engine_stream := AudioManager.get_sound(&"engine_loop")
	if _engine_audio != null and engine_stream != null:
		_engine_audio.stream = engine_stream
		_engine_audio.unit_size = 14.0
		_engine_audio.max_distance = 260.0
		_engine_audio.volume_db = engine_volume_db
		_engine_audio.play()
	var squeal_stream := AudioManager.get_sound(&"tire_squeal")
	if _squeal_audio != null and squeal_stream != null:
		_squeal_audio.stream = squeal_stream
		_squeal_audio.unit_size = 10.0
		_squeal_audio.max_distance = 160.0
		_squeal_audio.volume_db = -60.0
		_squeal_audio.play()


func _update_audio(_delta: float) -> void:
	if _engine_audio != null and _engine_audio.playing:
		var ratio := clampf(_speed_smooth / maxf(max_speed, 1.0), 0.0, 1.0)
		var rpm_ratio := get_rpm_ratio()
		var pitch := lerpf(engine_pitch_min, engine_pitch_max, clampf(rpm_ratio * 0.75 + ratio * 0.25, 0.0, 1.0))
		_engine_audio.pitch_scale = clampf(pitch, engine_pitch_min, engine_pitch_max)
		var load_boost := 0.0 if throttle <= 0.0 else 3.0
		_engine_audio.volume_db = engine_volume_db + load_boost - (1.0 - get_health_ratio()) * 4.0
	if _squeal_audio != null and _squeal_audio.playing:
		var target_db := -60.0
		if is_skidding and is_on_ground():
			target_db = clampf(-30.0 + _skid_amount * 22.0, -30.0, -6.0)
		_squeal_audio.volume_db = move_toward(_squeal_audio.volume_db, target_db, 2.5)


# --- Пробуксовка, дым и следы ------------------------------------------------


func _prepare_particles() -> void:
	if _smoke != null:
		_smoke.emitting = false
		_smoke.amount_ratio = 0.0
	if _sparks != null:
		_sparks.emitting = false


func _prepare_skid_trail() -> void:
	if not skid_marks_enabled:
		return
	var parent := get_parent()
	if parent == null:
		return
	# След живёт в отдельном узле на уровне трассы, чтобы не наследовать
	# трансформ машины и не крутиться вместе с ней.
	_skid_trail = SkidTrail.new()
	_skid_trail.name = "%sSkidTrail" % name
	parent.add_child(_skid_trail)


## Скользим ли мы: сравниваем направление движения с направлением носа.
func _update_skid_state(delta: float) -> void:
	var speed := linear_velocity.length()
	var slip := 0.0
	if speed > 1.0:
		var forward := -global_basis.z
		var direction := linear_velocity.normalized()
		slip = 1.0 - absf(forward.dot(direction))
		slip = clampf(slip * 4.0, 0.0, 1.0)
	var wheelspin := 0.0
	if _wheels.size() >= 4 and stats != null:
		# На месте газ в пол тоже даёт дым: считаем от избыточной тяги.
		wheelspin = clampf(absf(engine_force) / maxf(_engine_force_max, 1.0) - 0.75, 0.0, 1.0) * 2.0
	_skid_amount = clampf(maxf(slip, wheelspin * float(is_on_ground())), 0.0, 1.0)
	var skidding_now := _skid_amount > skid_threshold and is_on_ground()
	if skidding_now != is_skidding:
		is_skidding = skidding_now
		if _smoke != null:
			_smoke.emitting = skidding_now
	if _smoke != null:
		_smoke.amount_ratio = _skid_amount if is_skidding else 0.0
		if is_skidding and randf() < delta * 4.0:
			_smoke.restart()


## Ставит «квадрат» следа под задними колёсами.
func _stamp_skid_marks() -> void:
	if _skid_trail == null or _wheels.size() < 4:
		return
	var left := _wheel_ground_point(_wheels[2])
	var right := _wheel_ground_point(_wheels[3])
	if left == Vector3.INF or right == Vector3.INF:
		return
	var half_width := (stats.wheel_radius if stats != null else 0.35) * 0.6
	_skid_trail.add_track(left, right, half_width, _skid_amount)


## Точка контакта колеса с землёй через рейкаст вниз.
func _wheel_ground_point(wheel: VehicleWheel3D) -> Vector3:
	if wheel == null or not wheel.is_in_contact():
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var from := wheel.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
	query.collision_mask = 1  # слой "world" — дорога и стены
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


func is_on_ground() -> bool:
	for wheel: VehicleWheel3D in _wheels:
		if wheel != null and wheel.is_in_contact():
			return true
	return false


## Свободные слоты на старте: куда можно поставить машину (для RaceManager).
func get_front_marker() -> Node3D:
	var marker := get_node_or_null("CameraMount") as Node3D
	return marker
