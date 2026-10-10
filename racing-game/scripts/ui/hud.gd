extends CanvasLayer
## HUD гонки: спидометр, тахометр, мини-карта, позиция, круг, времена,
## отсчёт 3-2-1-GO, сообщения о штрафах и motion blur на скорости.
##
## Все числа HUD берёт из RaceManager (метод update_hud вызывается менеджером
## каждый физический кадр), а плавную анимацию — в своём _process().

## Порог скорости для motion blur, км/ч (по ТЗ — 100).
@export_range(40.0, 260.0, 5.0) var blur_start_speed_kmh: float = 100.0
## Максимальная сила размытия.
@export_range(0.0, 2.0, 0.05) var blur_max_amount: float = 0.9
## Высота мини-карты над машиной, метры.
@export_range(20.0, 300.0, 5.0) var minimap_height: float = 110.0
## Размер мини-карты по ширине мира, метры (для ортогональной камеры).
@export_range(20.0, 600.0, 5.0) var minimap_view_size: float = 190.0

@onready var _root: Control = $Root
@onready var _motion_blur: ColorRect = $Root/MotionBlur
@onready var _position_label: Label = $Root/TopLeft/InfoBox/PositionLabel
@onready var _lap_label: Label = $Root/TopLeft/InfoBox/LapLabel
@onready var _time_label: Label = $Root/TopLeft/InfoBox/TimeLabel
@onready var _best_label: Label = $Root/TopLeft/InfoBox/BestLabel
@onready var _penalty_label: Label = $Root/TopLeft/InfoBox/PenaltyLabel
@onready var _rivals_box: VBoxContainer = $Root/RivalsPanel/RivalsBox
@onready var _countdown_label: Label = $Root/CountdownLabel
@onready var _message_label: Label = $Root/MessageLabel
@onready var _speedometer: Control = $Root/Speedo
@onready var _progress_bar: ProgressBar = $Root/ProgressBar
@onready var _minimap_viewport: SubViewport = $Root/MinimapPanel/MinimapView/MinimapViewport
@onready var _minimap_camera: Camera3D = $Root/MinimapPanel/MinimapView/MinimapViewport/MinimapCamera

var _manager: Node = null
var _player: CarBase = null
var _rival_rows: Array[Label] = []
var _message_timer: float = 0.0
var _penalty_flash: float = 0.0
var _go_timer: float = 0.0


func _ready() -> void:
	_countdown_label.visible = false
	_message_label.visible = false
	_penalty_label.visible = false
	_setup_minimap()
	_setup_motion_blur()
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)


## Мини-карта рисует тот же мир, что и основная камера.
func _setup_minimap() -> void:
	if _minimap_viewport == null:
		return
	_minimap_viewport.world_3d = get_viewport().world_3d
	_minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_minimap_viewport.transparent_bg = false
	_minimap_viewport.msaa_3d = Viewport.MSAA_DISABLED
	if _minimap_camera != null:
		_minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_minimap_camera.size = minimap_view_size
		_minimap_camera.near = 1.0
		_minimap_camera.far = 600.0
		_minimap_camera.current = true


func _setup_motion_blur() -> void:
	if _motion_blur == null:
		return
	var shader_path := "res://assets/shaders/motion_blur.gdshader"
	if ResourceLoader.exists(shader_path):
		var material := ShaderMaterial.new()
		material.shader = load(shader_path)
		material.set_shader_parameter("amount", 0.0)
		_motion_blur.material = material
	_motion_blur.visible = false


## Вызывается из RaceManager после спавна машин.
func setup(manager: Node, player: CarBase) -> void:
	_manager = manager
	_player = player
	_build_rival_rows()


func _build_rival_rows() -> void:
	for row: Label in _rival_rows:
		row.queue_free()
	_rival_rows.clear()
	if _manager == null or not _manager.has_method("get_standings"):
		return
	var count: int = _manager.call("get_standings").size()
	for index in count:
		var label := Label.new()
		label.name = "Rival%02d" % index
		label.text = ""
		_rivals_box.add_child(label)
		_rival_rows.append(label)


func _process(delta: float) -> void:
	_update_message(delta)
	_update_minimap()
	_update_motion_blur(delta)


# --- Основной апдейт ---------------------------------------------------------


## Тянет свежие данные из RaceManager (вызывается менеджером).
func update_hud() -> void:
	if _manager == null:
		return
	var racer: Dictionary = _manager.call("get_player_racer")
	if racer.is_empty():
		return
	var car: CarBase = racer["car"]
	var timer: LapTimer = racer["timer"]
	var standings: Array = _manager.call("get_standings")

	if car != null and _speedometer != null and _speedometer.has_method("set_values"):
		_speedometer.call(
			"set_values",
			car.get_speed_kmh(),
			car.get_rpm_ratio(),
			car.get_gear(),
			car.max_speed * 3.6
		)

	var total_racers := maxi(1, standings.size())
	_position_label.text = "Место  %d / %d" % [int(racer["position"]), total_racers]
	_lap_label.text = "Круг  %d / %d" % [mini(timer.current_lap, timer.total_laps), timer.total_laps]
	_time_label.text = "Круг  %s" % Records.format_time(timer.current_lap_time)
	_best_label.text = "Лучший  %s" % Records.format_time(timer.best_lap_time)

	var penalty := float(racer["penalty"])
	_penalty_label.visible = penalty > 0.0
	if penalty > 0.0:
		_penalty_label.text = "Штраф  +%.0f сек   Всего %s" % [penalty, Records.format_time(timer.get_total_with_penalty())]
		if _penalty_flash > 0.0:
			_penalty_label.modulate = Color(1.0, 0.45, 0.45, 1.0)
		else:
			_penalty_label.modulate = Color(1.0, 0.85, 0.6, 1.0)

	_update_rivals(standings)
	if timer.total_laps > 0:
		_progress_bar.max_value = float(timer.total_laps)
		_progress_bar.value = float(timer.current_lap - 1) + clampf(
			timer.current_lap_time / maxf(_lap_estimate(timer), 1.0), 0.0, 1.0
		)


func _lap_estimate(timer: LapTimer) -> float:
	return timer.best_lap_time if timer.best_lap_time > 0.0 else 90.0


func _update_rivals(standings: Array) -> void:
	for index in _rival_rows.size():
		if index >= standings.size():
			_rival_rows[index].text = ""
			continue
		var row: Dictionary = standings[index]
		var suffix := "  ФИНИШ" if bool(row["finished"]) else ""
		_rival_rows[index].text = "%d. %s%s" % [int(row["position"]), row["name"], suffix]
		_rival_rows[index].modulate = Color(1.0, 0.85, 0.35, 1.0) if bool(row["is_player"]) else Color(1, 1, 1, 1)


# --- Сообщения, отсчёт, вспышка штрафа ---------------------------------------


func show_countdown(step: int) -> void:
	if _countdown_label == null:
		return
	_countdown_label.visible = true
	_countdown_label.text = str(step) if step > 0 else "GO!"
	_countdown_label.modulate = Color(1, 1, 1, 1)
	_countdown_label.scale = Vector2(1.6, 1.6)
	if step <= 0:
		_go_timer = 1.2


func show_go() -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = "GO!"
	_countdown_label.modulate = Color(0.4, 1.0, 0.5, 1.0)
	_go_timer = 1.2


func show_message(text: String, duration: float = 2.0) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true
	_message_timer = maxf(_message_timer, duration)


func flash_penalty() -> void:
	_penalty_flash = 0.8


## Сообщение о круге: время и отметка лучшего.
func notify_lap(info: Dictionary) -> void:
	var lap_time: float = info["time"]
	if bool(info["finished"]):
		show_message("ФИНИШ!  Время гонки %s" % Records.format_time(lap_time), 3.0)
	elif bool(info["is_best"]):
		show_message("Лучший круг: %s" % Records.format_time(lap_time), 2.5)
	else:
		show_message("Круг %d: %s" % [int(info["lap"]), Records.format_time(lap_time)], 2.0)


func _update_message(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			_message_label.visible = false
	if _penalty_flash > 0.0:
		_penalty_flash = maxf(0.0, _penalty_flash - delta)
	if _go_timer > 0.0:
		_go_timer -= delta
		if _countdown_label != null:
			_countdown_label.scale = _countdown_label.scale.lerp(Vector2.ONE, clampf(delta * 6.0, 0.0, 1.0))
			_countdown_label.modulate.a = clampf(_go_timer, 0.0, 1.0)
		if _go_timer <= 0.0 and _countdown_label != null:
			_countdown_label.visible = false


# --- Мини-карта и размытие ---------------------------------------------------


func _update_minimap() -> void:
	if _player == null or not is_instance_valid(_player) or _minimap_camera == null:
		return
	var position := _player.global_position + Vector3.UP * minimap_height
	# Север сверху: камера смотрит строго вниз, машина видна как 3D-объект.
	_minimap_camera.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), position)


func _update_motion_blur(delta: float) -> void:
	if _motion_blur == null or _player == null or not is_instance_valid(_player):
		return
	var enabled := SettingsManager == null or SettingsManager.motion_blur_enabled
	var speed_kmh := _player.get_speed_kmh()
	var target := 0.0
	if enabled and speed_kmh > blur_start_speed_kmh:
		target = clampf((speed_kmh - blur_start_speed_kmh) / 120.0, 0.0, 1.0) * blur_max_amount
	var material := _motion_blur.material as ShaderMaterial
	if material == null:
		_motion_blur.visible = false
		return
	var current: float = material.get_shader_parameter("amount")
	current = move_toward(current, target, delta * 2.5)
	material.set_shader_parameter("amount", current)
	_motion_blur.visible = current > 0.01


func _on_settings_changed() -> void:
	_update_motion_blur(0.016)
