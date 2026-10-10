class_name LapTimer
extends Node
## Таймер кругов одного участника: текущий круг, лучший круг, общее время.
##
## По одному экземпляру на гонщика; их создаёт RaceManager. Узел наследует
## process_mode от родителя, поэтому на паузе время автоматически стоит.

## Круг завершён. is_best — новый личный рекорд круга в этом заезде.
signal lap_completed(lap_index: int, lap_time: float, is_best: bool)
## Начислен штраф (пропуск чекпоинта).
signal penalty_applied(seconds: float, total_penalty: float)
## Участник финишировал.
signal finished(total_time: float, best_lap: float)

## Сколько кругов нужно проехать.
var total_laps: int = 3
## Текущий круг (начинается с 1).
var current_lap: int = 1
## Время текущего круга, секунды.
var current_lap_time: float = 0.0
## Время последнего завершённого круга.
var last_lap_time: float = 0.0
## Лучший круг за заезд; 0.0 — ещё не было.
var best_lap_time: float = 0.0
## Суммарное время гонки без штрафов.
var total_time: float = 0.0
## Накопленный штраф, секунды.
var penalty_time: float = 0.0
## История кругов для таблицы результатов.
var lap_times: Array[float] = []
var is_running: bool = false
var is_finished: bool = false


func _process(delta: float) -> void:
	if not is_running or is_finished:
		return
	current_lap_time += delta
	total_time += delta


## Старт отсчёта (вызывается после «GO!»).
func start() -> void:
	if is_finished:
		return
	is_running = true
	current_lap_time = 0.0


func stop() -> void:
	is_running = false


## Полный сброс перед заездом.
func reset(laps: int) -> void:
	total_laps = maxi(1, laps)
	current_lap = 1
	current_lap_time = 0.0
	last_lap_time = 0.0
	best_lap_time = 0.0
	total_time = 0.0
	penalty_time = 0.0
	lap_times.clear()
	is_running = false
	is_finished = false


## Круг пройден. Возвращает словарь с деталями для HUD и результатов.
func complete_lap() -> Dictionary:
	last_lap_time = current_lap_time
	lap_times.append(last_lap_time)
	var is_best := best_lap_time <= 0.0 or last_lap_time < best_lap_time
	if is_best:
		best_lap_time = last_lap_time
	current_lap_time = 0.0
	var result := {
		"lap": current_lap,
		"time": last_lap_time,
		"is_best": is_best,
		"finished": false,
	}
	if current_lap >= total_laps:
		is_finished = true
		is_running = false
		result["finished"] = true
		finished.emit(get_total_with_penalty(), best_lap_time)
	else:
		current_lap += 1
	lap_completed.emit(result["lap"], last_lap_time, is_best)
	return result


## Штраф за пропуск чекпоинта.
func add_penalty(seconds: float) -> void:
	if seconds <= 0.0:
		return
	penalty_time += seconds
	penalty_applied.emit(seconds, penalty_time)


## Итоговое время с учётом штрафов.
func get_total_with_penalty() -> float:
	return total_time + penalty_time


## Оставшиеся круги (не меньше нуля).
func get_laps_left() -> int:
	return maxi(0, total_laps - current_lap)


## Прогресс гонки 0..1 — для полоски в HUD.
func get_progress_ratio() -> float:
	var done := float(current_lap - 1) + clampf(current_lap_time / maxf(_estimated_lap_time(), 1.0), 0.0, 1.0)
	return clampf(done / float(total_laps), 0.0, 1.0)


## Оценка длительности круга: лучший круг или 90 секунд по умолчанию.
func _estimated_lap_time() -> float:
	return best_lap_time if best_lap_time > 0.0 else 90.0
