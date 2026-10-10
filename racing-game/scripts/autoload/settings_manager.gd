extends Node
## SettingsManager (autoload) — настройки графики и звука.
##
## Хранятся в `user://settings.cfg`. Звук применяется сразу (через AudioServer),
## графика — через сигнал settings_changed: его слушает EnvironmentController
## на трассе и MotionBlurLayer в HUD.

signal settings_changed

const SAVE_PATH: String = "user://settings.cfg"

# --- Звук (линейные значения 0..1) -------------------------------------------
var master_volume: float = 1.0
var music_volume: float = 0.75
var sfx_volume: float = 1.0

# --- Графика -----------------------------------------------------------------
var shadows_enabled: bool = true
var ssr_enabled: bool = true
var fog_enabled: bool = true
var motion_blur_enabled: bool = true
## Индекс Viewport.MSAA_*: 0 = выкл, 1 = 2x, 2 = 4x, 3 = 8x.
var msaa_3d: int = 2
var fullscreen: bool = false
## 0 = низкое, 1 = среднее, 2 = высокое качество.
var quality_preset: int = 2


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return  # Первый запуск: оставляем значения по умолчанию.
	master_volume = float(config.get_value("audio", "master", master_volume))
	music_volume = float(config.get_value("audio", "music", music_volume))
	sfx_volume = float(config.get_value("audio", "sfx", sfx_volume))
	shadows_enabled = bool(config.get_value("graphics", "shadows", shadows_enabled))
	ssr_enabled = bool(config.get_value("graphics", "ssr", ssr_enabled))
	fog_enabled = bool(config.get_value("graphics", "fog", fog_enabled))
	motion_blur_enabled = bool(config.get_value("graphics", "motion_blur", motion_blur_enabled))
	msaa_3d = int(config.get_value("graphics", "msaa", msaa_3d))
	fullscreen = bool(config.get_value("graphics", "fullscreen", fullscreen))
	quality_preset = int(config.get_value("graphics", "preset", quality_preset))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("graphics", "shadows", shadows_enabled)
	config.set_value("graphics", "ssr", ssr_enabled)
	config.set_value("graphics", "fog", fog_enabled)
	config.set_value("graphics", "motion_blur", motion_blur_enabled)
	config.set_value("graphics", "msaa", msaa_3d)
	config.set_value("graphics", "fullscreen", fullscreen)
	config.set_value("graphics", "preset", quality_preset)
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("[Settings] Не удалось сохранить %s (код %d)" % [SAVE_PATH, err])


## Применяет все настройки и рассылает сигнал.
func apply_all() -> void:
	_apply_audio()
	_apply_window()
	_apply_msaa()
	settings_changed.emit()


func _apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return  # Бас не найден — ничего не ломаем.
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _apply_window() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func _apply_msaa() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.msaa_3d = clampi(msaa_3d, 0, 3)


## Пресеты качества: переключают всё сразу.
func apply_preset(preset: int) -> void:
	quality_preset = clampi(preset, 0, 2)
	match quality_preset:
		0:  # Низкое
			msaa_3d = 0
			shadows_enabled = true
			ssr_enabled = false
			fog_enabled = false
			motion_blur_enabled = false
		1:  # Среднее
			msaa_3d = 1
			shadows_enabled = true
			ssr_enabled = false
			fog_enabled = true
			motion_blur_enabled = true
		2:  # Высокое
			msaa_3d = 2
			shadows_enabled = true
			ssr_enabled = true
			fog_enabled = true
			motion_blur_enabled = true
	apply_all()
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()
	settings_changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()
	settings_changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()
	settings_changed.emit()
