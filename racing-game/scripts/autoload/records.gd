extends Node
## Records (autoload) — таблица рекордов в `user://records.cfg`.
##
## Формат файла (ConfigFile):
## [city/roadster]
## best_lap=71.482
## best_total=214.901
## races=7
## best_position=1

signal record_updated(track_id: StringName, car_id: StringName)

const SAVE_PATH: String = "user://records.cfg"

var _config := ConfigFile.new()


func _ready() -> void:
	load_records()


## Читает файл рекордов. Отсутствие файла — не ошибка, а первый запуск.
func load_records() -> void:
	var err := _config.load(SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[Records] Не удалось прочитать %s (код %d)" % [SAVE_PATH, err])


## Сохраняет рекорды на диск.
func save_records() -> void:
	var err := _config.save(SAVE_PATH)
	if err != OK:
		push_warning("[Records] Не удалось сохранить %s (код %d)" % [SAVE_PATH, err])


func _section(track_id: StringName, car_id: StringName) -> String:
	return "%s/%s" % [track_id, car_id]


## Лучший круг в секундах; 0.0 — результата ещё нет.
func get_best_lap(track_id: StringName, car_id: StringName) -> float:
	return float(_config.get_value(_section(track_id, car_id), "best_lap", 0.0))


## Лучшее общее время гонки в секундах; 0.0 — результата ещё нет.
func get_best_total(track_id: StringName, car_id: StringName) -> float:
	return float(_config.get_value(_section(track_id, car_id), "best_total", 0.0))


## Лучшая занятая позиция (1 — лучшее); 0 — не финишировали.
func get_best_position(track_id: StringName, car_id: StringName) -> int:
	return int(_config.get_value(_section(track_id, car_id), "best_position", 0))


## Сколько раз трасса была проедена.
func get_races_count(track_id: StringName, car_id: StringName) -> int:
	return int(_config.get_value(_section(track_id, car_id), "races", 0))


## Лучший круг на трассе среди всех машин (для карточки в TrackSelect).
func get_track_best_lap(track_id: StringName) -> float:
	var best := 0.0
	for section: String in _config.get_sections():
		if not section.begins_with(String(track_id) + "/"):
			continue
		var lap := float(_config.get_value(section, "best_lap", 0.0))
		if lap > 0.0 and (best <= 0.0 or lap < best):
			best = lap
	return best


## Записывает результат заезда. Возвращает словарь с флагами новых рекордов.
func submit_result(
	track_id: StringName,
	car_id: StringName,
	total_time: float,
	best_lap: float,
	position: int
) -> Dictionary:
	var section := _section(track_id, car_id)
	var out := {"new_lap": false, "new_total": false, "new_position": false}

	var old_lap := float(_config.get_value(section, "best_lap", 0.0))
	if best_lap > 0.0 and (old_lap <= 0.0 or best_lap < old_lap):
		_config.set_value(section, "best_lap", best_lap)
		out["new_lap"] = true

	var old_total := float(_config.get_value(section, "best_total", 0.0))
	if total_time > 0.0 and (old_total <= 0.0 or total_time < old_total):
		_config.set_value(section, "best_total", total_time)
		out["new_total"] = true

	var old_position := int(_config.get_value(section, "best_position", 0))
	if position > 0 and (old_position <= 0 or position < old_position):
		_config.set_value(section, "best_position", position)
		out["new_position"] = true

	_config.set_value(section, "races", get_races_count(track_id, car_id) + 1)
	_config.set_value(section, "last_total", total_time)
	save_records()
	record_updated.emit(track_id, car_id)
	return out


## Стирает рекорды одной трассы (кнопка «Сброс» в TrackSelect).
func clear_track(track_id: StringName) -> void:
	for section: String in _config.get_sections():
		if section.begins_with(String(track_id) + "/"):
			_config.erase_section(section)
	save_records()
	record_updated.emit(track_id, &"")


## Стирает всё.
func clear_all() -> void:
	_config.clear()
	save_records()


## Формат времени: 71.482 -> "1:11.482", 0.0 -> "--:--.---".
static func format_time(seconds: float) -> String:
	if seconds <= 0.0 or is_nan(seconds) or is_inf(seconds):
		return "--:--.---"
	var minutes := int(floor(seconds / 60.0))
	var rest := seconds - minutes * 60.0
	return "%d:%06.3f" % [minutes, rest]
