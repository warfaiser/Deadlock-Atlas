extends Node
## GameState (autoload) — «чёрная доска» между сценами.
##
## Хранит выбранную машину, трассу, режим, сложность и результат последнего
## заезда. Сцены обращаются к нему напрямую: `GameState.selected_track`.

## Режим заезда.
enum GameMode { TIME_TRIAL, RACE }

## Сложность ботов.
enum Difficulty { EASY, NORMAL, HARD }

signal race_started
signal race_finished(result: Dictionary)

const CARS_DIR: String = "res://resources/cars"
const TRACKS_DIR: String = "res://resources/tracks"
const DEFAULT_CAR_PATH: String = "res://resources/car_stats.tres"
const DEFAULT_TRACK_PATH: String = "res://resources/track_data.tres"

const SCENE_MAIN_MENU: String = "res://scenes/MainMenu.tscn"
const SCENE_CAR_SELECT: String = "res://scenes/CarSelect.tscn"
const SCENE_TRACK_SELECT: String = "res://scenes/TrackSelect.tscn"
const SCENE_RACE: String = "res://scenes/Race.tscn"
const SCENE_RESULTS: String = "res://scenes/Results.tscn"

## Каталог машин и трасс (заполняется в _ready).
var cars: Array[CarStats] = []
var tracks: Array[TrackData] = []

## Текущий выбор игрока.
var selected_car: CarStats = null
var selected_track: TrackData = null
var game_mode: GameMode = GameMode.RACE
var difficulty: Difficulty = Difficulty.NORMAL
var bot_count: int = 5

## Словарь с итогами последнего заезда — его читает Results.tscn.
var last_result: Dictionary = {}


func _ready() -> void:
	_load_catalogs()
	if selected_car == null and not cars.is_empty():
		selected_car = cars[0]
	if selected_track == null and not tracks.is_empty():
		selected_track = tracks[0]
	bot_count = clampi(bot_count, 3, 7)


## Сканирует папки с .tres-ресурсами и собирает каталог контента.
func _load_catalogs() -> void:
	for resource: Resource in _scan_dir(CARS_DIR, [DEFAULT_CAR_PATH]):
		if resource is CarStats and _find_car(resource.id) == null:
			cars.append(resource)
	for resource: Resource in _scan_dir(TRACKS_DIR, [DEFAULT_TRACK_PATH]):
		if resource is TrackData and _find_track(resource.id) == null:
			tracks.append(resource)
	cars.sort_custom(func(a: CarStats, b: CarStats) -> bool: return a.display_name < b.display_name)
	tracks.sort_custom(func(a: TrackData, b: TrackData) -> bool: return a.display_name < b.display_name)
	if cars.is_empty():
		push_error("[GameState] Не найдено ни одной машины (папка %s)." % CARS_DIR)
	if tracks.is_empty():
		push_error("[GameState] Не найдено ни одной трассы (папка %s)." % TRACKS_DIR)


## Список файлов в папке; если папки нет — берём резервные пути.
func _scan_dir(dir_path: String, fallback: Array) -> Array[Resource]:
	var found: Array[Resource] = []
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for file_name: String in dir.get_files():
			if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				continue
			var resource: Resource = load(dir_path.path_join(file_name))
			if resource != null:
				found.append(resource)
	if found.is_empty():
		for path: String in fallback:
			var resource: Resource = load(path)
			if resource != null:
				found.append(resource)
	return found


func _find_car(car_id: StringName) -> CarStats:
	for car: CarStats in cars:
		if car.id == car_id:
			return car
	return null


func _find_track(track_id: StringName) -> TrackData:
	for track: TrackData in tracks:
		if track.id == track_id:
			return track
	return null


func get_car(car_id: StringName) -> CarStats:
	var car := _find_car(car_id)
	return car if car != null else (cars[0] if not cars.is_empty() else null)


func get_track(track_id: StringName) -> TrackData:
	var track := _find_track(track_id)
	return track if track != null else (tracks[0] if not tracks.is_empty() else null)


func get_car_index() -> int:
	if selected_car == null:
		return 0
	return maxi(0, cars.find(selected_car))


func get_track_index() -> int:
	if selected_track == null:
		return 0
	return maxi(0, tracks.find(selected_track))


func select_car_by_index(index: int) -> void:
	if cars.is_empty():
		return
	selected_car = cars[wrapi(index, 0, cars.size())]


func select_track_by_index(index: int) -> void:
	if tracks.is_empty():
		return
	selected_track = tracks[wrapi(index, 0, tracks.size())]


## Следующая трасса по кругу (кнопка «Next Track» на экране результатов).
func next_track() -> void:
	if tracks.is_empty():
		return
	select_track_by_index(get_track_index() + 1)


# --- Навигация ---------------------------------------------------------------


func goto_scene(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)


func goto_main_menu() -> void:
	goto_scene(SCENE_MAIN_MENU)


func start_race() -> void:
	last_result.clear()
	goto_scene(SCENE_RACE)


func show_results(result: Dictionary) -> void:
	last_result = result
	race_finished.emit(result)
	goto_scene(SCENE_RESULTS)


# --- Параметры сложности -----------------------------------------------------


func difficulty_name() -> String:
	match difficulty:
		Difficulty.EASY:
			return "Лёгкая"
		Difficulty.NORMAL:
			return "Обычная"
		Difficulty.HARD:
			return "Сложная"
	return "Обычная"


## Множитель максимальной скорости бота (ТЗ: 0.75 / 0.9 / 1.0).
func difficulty_speed_multiplier() -> float:
	match difficulty:
		Difficulty.EASY:
			return 0.75
		Difficulty.NORMAL:
			return 0.9
		Difficulty.HARD:
			return 1.0
	return 0.9


## Агрессия: насколько смело бот лезет в обгон и режет траекторию.
func difficulty_aggression() -> float:
	match difficulty:
		Difficulty.EASY:
			return 0.15
		Difficulty.NORMAL:
			return 0.45
		Difficulty.HARD:
			return 0.85
	return 0.45


func mode_name() -> String:
	return "Time Trial" if game_mode == GameMode.TIME_TRIAL else "Гонка"


func is_time_trial() -> bool:
	return game_mode == GameMode.TIME_TRIAL
