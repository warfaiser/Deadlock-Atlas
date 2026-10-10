class_name EnvironmentController
extends Node
## Окружение трассы: WorldEnvironment + DirectionalLight3D.
##
## Включает SSAO, SDFGI, SSR, объёмный туман, glow и процедурное небо, красит всё
## в палитру темы и крутит солнце по времени суток из TrackData.time_of_day.
## Флаги из SettingsManager (тени / SSR / туман) применяются на лету.

## Сколько игровых часов проходит за секунду (0 — солнце стоит).
@export_range(0.0, 2.0, 0.05) var day_speed: float = 0.0
## Насколько солнце смещается по азимуту за день, градусы.
@export_range(0.0, 120.0, 1.0) var azimuth_range: float = 60.0

var data: TrackData = null
var time_of_day: float = 16.5

var _environment: Environment = null
var _sky_material: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null


func _ready() -> void:
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_apply_settings):
		SettingsManager.settings_changed.connect(_apply_settings)


## Вызывается из TrackBuilder.build().
func setup(track_data: TrackData, world_environment: WorldEnvironment) -> void:
	if track_data == null or world_environment == null:
		return
	data = track_data
	time_of_day = data.time_of_day
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	_build_environment(world_environment)
	_apply_settings()
	_update_sun(0.0)


func _build_environment(world_environment: WorldEnvironment) -> void:
	var environment := Environment.new()

	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_top_color = data.sky_top_color
	_sky_material.sky_horizon_color = data.sky_horizon_color
	_sky_material.ground_bottom_color = data.ground_color.darkened(0.6)
	_sky_material.ground_horizon_color = data.sky_horizon_color
	_sky_material.sun_angle_max = 32.0
	_sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0

	# Отражения в лаке кузова и стёклах.
	environment.ssr_enabled = true
	environment.ssr_max_steps = 64
	environment.ssr_fade_in = 0.2
	environment.ssr_fade_out = 2.0
	environment.ssr_depth_tolerance = 0.25

	# Контактные тени в стыках дороги и отбойников.
	environment.ssao_enabled = true
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.4
	environment.ssao_power = 1.6

	# Глобальное освещение (SDFGI) — самый тяжёлый пункт, отключается в настройках.
	environment.sdfgi_enabled = true
	environment.sdfgi_energy = 0.85

	# Свечение фар и выхлопа.
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.0
	environment.glow_hdr_scale = 1.4

	# Туман: обычный + объёмный.
	environment.fog_enabled = true
	environment.fog_light_color = data.fog_color
	environment.fog_density = data.fog_density
	environment.fog_aerial_perspective = 0.5
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = clampf(data.fog_density * 0.6, 0.0, 0.2)
	environment.volumetric_fog_albedo = data.fog_color
	environment.volumetric_fog_emission = data.fog_color.darkened(0.7)
	environment.volumetric_fog_length = 96.0

	# Лёгкая тонировка под тему.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06 if data.theme == TrackData.Theme.CITY else 1.0
	environment.adjustment_contrast = 1.04

	world_environment.environment = environment
	_environment = environment


## Тени / SSR / туман из настроек игрока.
func _apply_settings() -> void:
	if _environment == null:
		return
	if SettingsManager == null:
		return
	_environment.ssr_enabled = SettingsManager.ssr_enabled
	_environment.volumetric_fog_enabled = SettingsManager.fog_enabled
	_environment.fog_enabled = SettingsManager.fog_enabled
	if _sun != null:
		_sun.shadow_enabled = SettingsManager.shadows_enabled


func _process(delta: float) -> void:
	if _environment == null or day_speed <= 0.0:
		return
	time_of_day = fposmod(time_of_day + delta * day_speed, 24.0)
	_update_sun(delta)


## Положение и цвет солнца по времени суток.
func _update_sun(_delta: float) -> void:
	if _sun == null:
		return
	# 6:00 — восход, 12:00 — зенит, 18:00 — закат.
	var day_progress := clampf((time_of_day - 6.0) / 12.0, 0.0, 1.0)
	var elevation := sin(day_progress * PI)
	var pitch := lerpf(-6.0, -74.0, elevation)
	var azimuth := (day_progress - 0.5) * azimuth_range
	_sun.rotation_degrees = Vector3(pitch, azimuth, 0.0)

	var warm := Color(1.0, 0.62, 0.35, 1.0)
	var noon := Color(1.0, 0.97, 0.92, 1.0)
	_sun.light_color = warm.lerp(noon, clampf(elevation * 1.6, 0.0, 1.0))
	_sun.light_energy = data.sun_energy * clampf(elevation * 1.35, 0.12, 1.0)

	if _sky_material != null:
		_sky_material.sky_energy_multiplier = clampf(0.25 + elevation, 0.25, 1.2)
	if _environment != null:
		_environment.ambient_light_energy = clampf(0.45 + elevation * 0.7, 0.45, 1.15)
