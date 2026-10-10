class_name CarPlayer
extends CarBase
## Машина игрока: читает InputMap, ведёт камеру преследования, трясёт её при ударах.
##
## Ввод (см. project.godot):
##   accelerate — W / ↑ / правый триггер
##   brake      — S / ↓ / левый триггер
##   steer_left / steer_right — A / D / ← / → / стик
##   handbrake  — Space
##   reset_car  — R (вернуться на последний чекпоинт)

@export_group("Камера")
## Дистание камеры до машины, метры.
@export_range(3.0, 20.0, 0.5) var camera_distance: float = 7.5
## Высота камеры над машиной, метры.
@export_range(0.0, 8.0, 0.25) var camera_height: float = 2.6
## Жёсткость преследования (больше — резче).
@export_range(1.0, 30.0, 0.5) var camera_follow_speed: float = 9.0
## Жёсткость доворота камеры по курсу.
@export_range(1.0, 30.0, 0.5) var camera_yaw_speed: float = 6.0
## Насколько расширяется FOV на максимальной скорости.
@export_range(0.0, 30.0, 1.0) var camera_fov_kick: float = 16.0
## Смотреть ли по направлению движения (плавнее на дугах).
@export var camera_use_velocity_direction: bool = true

@export_group("Ощущения")
## Сила тряски камеры при ударах.
@export_range(0.0, 2.0, 0.05) var shake_amount: float = 0.35

var _spring_arm: SpringArm3D = null
var _camera: Camera3D = null
var _shake: float = 0.0
var _base_fov: float = 75.0
## Сигнал для HUD: машина игрока готова.
signal player_ready


func _ready() -> void:
	super._ready()
	_cache_camera()
	if not crashed.is_connected(_on_crashed):
		crashed.connect(_on_crashed)
	control_enabled = true
	player_ready.emit()


func _cache_camera() -> void:
	_spring_arm = get_node_or_null("ChaseRig") as SpringArm3D
	if _spring_arm == null:
		return
	_camera = _spring_arm.get_node_or_null("Camera3D") as Camera3D
	if _camera != null:
		_base_fov = _camera.fov
		_camera.current = true
	_spring_arm.spring_length = camera_distance
	# Ставим камеру сразу за машиной, чтобы не было «перелёта» на первом кадре.
	_spring_arm.global_position = global_position + Vector3.UP * camera_height
	_spring_arm.global_basis = _desired_camera_basis(global_basis)
	_spring_arm.add_excluded_object(get_rid())


func _physics_process(delta: float) -> void:
	_read_input()
	super._physics_process(delta)
	_update_camera(delta)


## Читает действия из InputMap в поля, которые понимает CarBase.
func _read_input() -> void:
	if not control_enabled:
		throttle = 0.0
		brake_input = 0.0
		steer_input = 0.0
		handbrake_input = false
		return
	throttle = Input.get_action_strength(&"accelerate") - Input.get_action_strength(&"brake")
	throttle = clampf(throttle, -1.0, 1.0)
	# Педаль тормоза всегда передаётся как есть: переход в реверс на почти
	# стоящей машине обрабатывает CarBase._apply_drivetrain().
	brake_input = Input.get_action_strength(&"brake")
	steer_input = Input.get_action_strength(&"steer_left") - Input.get_action_strength(&"steer_right")
	steer_input = clampf(steer_input, -1.0, 1.0)
	handbrake_input = Input.is_action_pressed(&"handbrake")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reset_car"):
		recover_to_last_checkpoint()
		AudioManager.play_sfx(&"checkpoint", -10.0, 1.4)


## Камера: плавно догоняет машину, расширяет FOV на скорости, трясётся при ударах.
func _update_camera(delta: float) -> void:
	if _spring_arm == null:
		return
	var anchor := global_position + Vector3.UP * camera_height
	var desired_basis := _desired_camera_basis(global_basis)
	var position_blend := 1.0 - exp(-camera_follow_speed * delta)
	var yaw_blend := 1.0 - exp(-camera_yaw_speed * delta)

	_spring_arm.global_position = _spring_arm.global_position.lerp(anchor, position_blend)
	var from_quat := _spring_arm.global_basis.get_rotation_quaternion()
	var to_quat := desired_basis.get_rotation_quaternion()
	_spring_arm.global_basis = Basis(from_quat.slerp(to_quat, yaw_blend)).orthonormalized()

	_shake = maxf(0.0, _shake - delta * 2.2)
	if _shake > 0.0:
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * _shake * shake_amount
		_spring_arm.global_position += offset

	if _camera != null:
		var speed_ratio := clampf(get_speed_mps() / maxf(max_speed, 1.0), 0.0, 1.0)
		_camera.fov = _base_fov + camera_fov_kick * speed_ratio


## Базис пружины камеры.
## SpringArm3D относит дочерний Camera3D вдоль своего +Z на spring_length,
## поэтому базис пружины совпадает с базисом машины: камера оказывается сзади.
func _desired_camera_basis(car_basis: Basis) -> Basis:
	var reference := car_basis
	var moving_forward := linear_velocity.dot(-car_basis.z) > 0.0
	if camera_use_velocity_direction and moving_forward and linear_velocity.length_squared() > 25.0:
		var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z).normalized()
		if flat.length_squared() > 0.5:
			reference = Basis.looking_at(flat, Vector3.UP)
	return reference


func _on_crashed(impact: float) -> void:
	_shake = clampf(impact * 0.12, 0.0, 1.0)


## Позиция, с которой камера смотрит на машину (для отладки).
func get_camera() -> Camera3D:
	return _camera
