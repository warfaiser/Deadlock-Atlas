extends Control
## Панель настроек: громкости, качество графики, сброс рекордов.
##
## Один и тот же экземпляр сцены SettingsPanel.tscn вставляется и в MainMenu,
## и в PauseMenu — логика общая, значения живут в SettingsManager.

signal closed

@onready var _master_slider: HSlider = $Panel/VBox/MasterRow/MasterSlider
@onready var _master_value: Label = $Panel/VBox/MasterRow/MasterValue
@onready var _music_slider: HSlider = $Panel/VBox/MusicRow/MusicSlider
@onready var _music_value: Label = $Panel/VBox/MusicRow/MusicValue
@onready var _sfx_slider: HSlider = $Panel/VBox/SfxRow/SfxSlider
@onready var _sfx_value: Label = $Panel/VBox/SfxRow/SfxValue
@onready var _quality_option: OptionButton = $Panel/VBox/QualityRow/QualityOption
@onready var _msaa_option: OptionButton = $Panel/VBox/MsaaRow/MsaaOption
@onready var _shadows_check: CheckButton = $Panel/VBox/ShadowsCheck
@onready var _ssr_check: CheckButton = $Panel/VBox/SsrCheck
@onready var _fog_check: CheckButton = $Panel/VBox/FogCheck
@onready var _blur_check: CheckButton = $Panel/VBox/BlurCheck
@onready var _fullscreen_check: CheckButton = $Panel/VBox/FullscreenCheck
@onready var _reset_button: Button = $Panel/VBox/ResetButton
@onready var _close_button: Button = $Panel/VBox/CloseButton


func _ready() -> void:
	visible = false
	if AudioManager != null:
		AudioManager.attach_ui_sounds(self)
	_quality_option.clear()
	_quality_option.add_item("Низкое", 0)
	_quality_option.add_item("Среднее", 1)
	_quality_option.add_item("Высокое", 2)
	_msaa_option.clear()
	_msaa_option.add_item("Выкл", 0)
	_msaa_option.add_item("2x", 1)
	_msaa_option.add_item("4x", 2)
	_msaa_option.add_item("8x", 3)

	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_quality_option.item_selected.connect(_on_quality_selected)
	_msaa_option.item_selected.connect(_on_msaa_selected)
	_shadows_check.toggled.connect(_on_shadows_toggled)
	_ssr_check.toggled.connect(_on_ssr_toggled)
	_fog_check.toggled.connect(_on_fog_toggled)
	_blur_check.toggled.connect(_on_blur_toggled)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_reset_button.pressed.connect(_on_reset_records)
	_close_button.pressed.connect(close)


func open() -> void:
	_sync_from_settings()
	visible = true
	_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Подтягивает текущие значения из SettingsManager.
func _sync_from_settings() -> void:
	if SettingsManager == null:
		return
	_master_slider.value = SettingsManager.master_volume * 100.0
	_music_slider.value = SettingsManager.music_volume * 100.0
	_sfx_slider.value = SettingsManager.sfx_volume * 100.0
	_update_value_label(_master_value, SettingsManager.master_volume)
	_update_value_label(_music_value, SettingsManager.music_volume)
	_update_value_label(_sfx_value, SettingsManager.sfx_volume)
	_select_id(_quality_option, SettingsManager.quality_preset)
	_select_id(_msaa_option, SettingsManager.msaa_3d)
	_shadows_check.button_pressed = SettingsManager.shadows_enabled
	_ssr_check.button_pressed = SettingsManager.ssr_enabled
	_fog_check.button_pressed = SettingsManager.fog_enabled
	_blur_check.button_pressed = SettingsManager.motion_blur_enabled
	_fullscreen_check.button_pressed = SettingsManager.fullscreen


func _select_id(option: OptionButton, value: int) -> void:
	var index := option.get_item_index_from_id(value)
	if index >= 0:
		option.select(index)


func _update_value_label(label: Label, linear: float) -> void:
	label.text = "%d%%" % int(round(linear * 100.0))


# --- Обработчики -------------------------------------------------------------


func _on_master_changed(value: float) -> void:
	_update_value_label(_master_value, value / 100.0)
	SettingsManager.set_master_volume(value / 100.0)


func _on_music_changed(value: float) -> void:
	_update_value_label(_music_value, value / 100.0)
	SettingsManager.set_music_volume(value / 100.0)


func _on_sfx_changed(value: float) -> void:
	_update_value_label(_sfx_value, value / 100.0)
	SettingsManager.set_sfx_volume(value / 100.0)
	AudioManager.play_sfx(&"ui_click", -6.0, 1.0)


func _on_quality_selected(index: int) -> void:
	SettingsManager.apply_preset(_quality_option.get_item_id(index))
	_sync_from_settings()


func _on_msaa_selected(index: int) -> void:
	SettingsManager.msaa_3d = _msaa_option.get_item_id(index)
	SettingsManager.apply_all()
	SettingsManager.save_settings()


func _on_shadows_toggled(pressed: bool) -> void:
	SettingsManager.shadows_enabled = pressed
	SettingsManager.apply_all()
	SettingsManager.save_settings()


func _on_ssr_toggled(pressed: bool) -> void:
	SettingsManager.ssr_enabled = pressed
	SettingsManager.apply_all()
	SettingsManager.save_settings()


func _on_fog_toggled(pressed: bool) -> void:
	SettingsManager.fog_enabled = pressed
	SettingsManager.apply_all()
	SettingsManager.save_settings()


func _on_blur_toggled(pressed: bool) -> void:
	SettingsManager.motion_blur_enabled = pressed
	SettingsManager.apply_all()
	SettingsManager.save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.fullscreen = pressed
	SettingsManager.apply_all()
	SettingsManager.save_settings()


func _on_reset_records() -> void:
	Records.clear_all()
	_reset_button.text = "Рекорды стёрты"
