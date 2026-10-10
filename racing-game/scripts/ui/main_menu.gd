extends MenuController
## Главное меню: Play, Car Select, Track Select, Settings, Exit.
##
## Фон — живая 3D-сцена с вращающейся машиной (SubViewport), справа — панель
## режима (Time Trial / гонка), сложности ботов и их количества.

## Скорость вращения машины на фоне, рад/с.
@export_range(0.0, 3.0, 0.05) var preview_rotation_speed: float = 0.45

@onready var _play_button: Button = $Panel/VBox/PlayButton
@onready var _car_button: Button = $Panel/VBox/CarSelectButton
@onready var _track_button: Button = $Panel/VBox/TrackSelectButton
@onready var _settings_button: Button = $Panel/VBox/SettingsButton
@onready var _exit_button: Button = $Panel/VBox/ExitButton
@onready var _mode_option: OptionButton = $ModePanel/ModeBox/ModeOption
@onready var _difficulty_option: OptionButton = $ModePanel/ModeBox/DifficultyOption
@onready var _bots_option: OptionButton = $ModePanel/ModeBox/BotsOption
@onready var _track_info: Label = $ModePanel/ModeBox/TrackInfoLabel
@onready var _car_info: Label = $ModePanel/ModeBox/CarInfoLabel
@onready var _settings_panel: Control = $SettingsPanel
@onready var _preview_car: Node3D = $Background/PreviewViewport/ShowCar


func _ready() -> void:
	first_button = $Panel/VBox/PlayButton.get_path()
	super._ready()
	_fill_mode_options()
	_fill_difficulty_options()
	_fill_bots_options()
	_sync_from_game_state()
	_update_info_labels()
	_play_button.pressed.connect(_on_play)
	_car_button.pressed.connect(_on_car_select)
	_track_button.pressed.connect(_on_track_select)
	_settings_button.pressed.connect(_on_settings)
	_exit_button.pressed.connect(_on_exit)
	_mode_option.item_selected.connect(_on_mode_selected)
	_difficulty_option.item_selected.connect(_on_difficulty_selected)
	_bots_option.item_selected.connect(_on_bots_selected)
	if _settings_panel != null and _settings_panel.has_method("close"):
		_settings_panel.call("close")
		if _settings_panel.has_signal("closed"):
			_settings_panel.connect("closed", _on_settings_closed)


func _process(delta: float) -> void:
	if _preview_car != null:
		_preview_car.rotate_y(preview_rotation_speed * delta)


func _fill_mode_options() -> void:
	_mode_option.clear()
	_mode_option.add_item("Гонка с ботами", GameState.GameMode.RACE)
	_mode_option.add_item("Time Trial", GameState.GameMode.TIME_TRIAL)


func _fill_difficulty_options() -> void:
	_difficulty_option.clear()
	_difficulty_option.add_item("Лёгкая (0.75x)", GameState.Difficulty.EASY)
	_difficulty_option.add_item("Обычная (0.9x)", GameState.Difficulty.NORMAL)
	_difficulty_option.add_item("Сложная (1.0x + агрессия)", GameState.Difficulty.HARD)


func _fill_bots_options() -> void:
	_bots_option.clear()
	for count in range(3, 8):
		_bots_option.add_item("%d соперника" % count, count)


func _sync_from_game_state() -> void:
	_select_by_id(_mode_option, GameState.game_mode)
	_select_by_id(_difficulty_option, GameState.difficulty)
	_select_by_id(_bots_option, GameState.bot_count)
	_bots_option.disabled = GameState.is_time_trial()


func _select_by_id(option: OptionButton, value: int) -> void:
	var index := option.get_item_index_from_id(value)
	if index >= 0:
		option.select(index)


func _update_info_labels() -> void:
	if GameState.selected_track != null:
		var track: TrackData = GameState.selected_track
		_track_info.text = "Трасса: %s (%s)\nДлина %.0f м, кругов %d" % [
			track.display_name, track.get_theme_name(), track.get_length(), track.laps
		]
	else:
		_track_info.text = "Трасса не выбрана"
	if GameState.selected_car != null:
		var car: CarStats = GameState.selected_car
		_car_info.text = "Машина: %s\n%.0f кг, vmax %.0f км/ч" % [
			car.display_name, car.mass, car.max_speed * 3.6
		]
	else:
		_car_info.text = "Машина не выбрана"


func _on_play() -> void:
	GameState.start_race()


func _on_car_select() -> void:
	GameState.goto_scene(GameState.SCENE_CAR_SELECT)


func _on_track_select() -> void:
	GameState.goto_scene(GameState.SCENE_TRACK_SELECT)


func _on_settings() -> void:
	if _settings_panel != null and _settings_panel.has_method("open"):
		_settings_panel.call("open")


func _on_settings_closed() -> void:
	_play_button.grab_focus()


func _on_exit() -> void:
	quit_game()


func _on_mode_selected(index: int) -> void:
	var id := _mode_option.get_item_id(index)
	if id == GameState.GameMode.TIME_TRIAL:
		GameState.game_mode = GameState.GameMode.TIME_TRIAL
	else:
		GameState.game_mode = GameState.GameMode.RACE
	_bots_option.disabled = GameState.is_time_trial()


func _on_difficulty_selected(index: int) -> void:
	var id := _difficulty_option.get_item_id(index)
	match id:
		GameState.Difficulty.EASY:
			GameState.difficulty = GameState.Difficulty.EASY
		GameState.Difficulty.HARD:
			GameState.difficulty = GameState.Difficulty.HARD
		_:
			GameState.difficulty = GameState.Difficulty.NORMAL


func _on_bots_selected(index: int) -> void:
	GameState.bot_count = _bots_option.get_item_id(index)
