class_name TrackData
extends Resource
## Данные трассы: геометрия, тема окружения, параметры режима.
##
## Три готовых трассы лежат в `res://resources/tracks/` (City / Desert / Snow),
## «эталонный» экземпляр — `res://resources/track_data.tres`.
## Геометрия дороги, Path3D для ботов и чекпоинты строятся из одного и того же
## метода create_curve(), поэтому машина игрока и ИИ всегда едут по одной линии.

## Тема трассы: определяет палитру, тип scenery и туман.
enum Theme { CITY, DESERT, SNOW }

# --- Идентификация -----------------------------------------------------------
@export var id: StringName = &"city"
@export var display_name: String = "City Sprint"
@export_file("*.png", "*.webp", "*.svg") var preview_path: String = "res://assets/ui/icons/track_city.png"
@export_multiline var description: String = "Короткая городская трасса с узкими поворотами."

# --- Геометрия ---------------------------------------------------------------
## Опорные точки гоночной линии (метры, Y = высота). Петля замыкается автоматически.
@export var control_points: PackedVector3Array = PackedVector3Array()
## Полуширина дороги, метры (полная ширина = 2 * road_width).
@export_range(4.0, 30.0, 0.5) var road_width: float = 12.0
## Шаг сэмплирования кривой, метры: чем меньше, тем глаже дорога.
@export_range(0.5, 6.0, 0.25) var bake_interval: float = 2.0
## Вес касательных при сглаживании (Catmull-Rom ≈ 0.17, больше — шире дуги).
@export_range(0.05, 0.5, 0.01) var tangent_scale: float = 0.25
## Высота бордюра/отбойника по краям, метры.
@export_range(0.0, 4.0, 0.1) var barrier_height: float = 1.0

# --- Режим -------------------------------------------------------------------
@export_range(1, 10) var laps: int = 3
## Сложность для карточки в меню (1..5 звёзд).
@export_range(1, 5) var difficulty: int = 2
## Сколько чекпоинтов нарезать по длине (включая линию старта/финиша).
@export_range(3, 16) var checkpoint_count: int = 6
## Диапазон числа ботов в режиме Race.
@export_range(1, 12) var bots_min: int = 3
@export_range(1, 12) var bots_max: int = 7
## Множитель сцепления покрытия: снег скользкий, асфальт цепкий.
@export_range(0.2, 2.0, 0.01) var surface_grip: float = 1.0

# --- Окружение ---------------------------------------------------------------
@export var theme: Theme = Theme.CITY
## Количество объектов MultiMesh (деревья/здания/камни).
@export_range(0, 2000) var scenery_count: int = 400
## Как далеко от дороги разрешено ставить scenery, метры.
@export_range(5.0, 200.0, 1.0) var scenery_min_distance: float = 10.0
@export_range(5.0, 300.0, 1.0) var scenery_max_distance: float = 120.0
## Время суток 0..24 — управляет солнцем и небом.
@export_range(0.0, 24.0, 0.25) var time_of_day: float = 16.5
## Базовые цвета палитры.
@export var asphalt_color: Color = Color(0.13, 0.13, 0.15, 1.0)
@export var marking_color: Color = Color(0.92, 0.92, 0.88, 1.0)
@export var ground_color: Color = Color(0.20, 0.30, 0.18, 1.0)
@export var fog_color: Color = Color(0.62, 0.68, 0.78, 1.0)
@export_range(0.0, 0.4, 0.005) var fog_density: float = 0.02
@export var sky_top_color: Color = Color(0.22, 0.36, 0.62, 1.0)
@export var sky_horizon_color: Color = Color(0.72, 0.74, 0.78, 1.0)
@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.1


## Название темы для UI/логов.
func get_theme_name() -> String:
	match theme:
		Theme.CITY:
			return "Город"
		Theme.DESERT:
			return "Пустыня"
		Theme.SNOW:
			return "Снег"
	return "Неизвестно"


## Строит сглаженную замкнутую Curve3D по опорным точкам.
##
## Последняя точка дублируется первой, чтобы петля физически замкнулась:
## Curve3D в Godot не умеет замыкаться сама.
func create_curve() -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = bake_interval
	var count := control_points.size()
	if count < 3:
		push_warning("TrackData '%s': нужно минимум 3 опорные точки." % id)
		return curve
	for i in count + 1:
		var idx := i % count
		var prev := control_points[(idx - 1 + count) % count]
		var curr := control_points[idx]
		var next := control_points[(idx + 1) % count]
		var tangent := (next - prev) * tangent_scale
		curve.add_point(curr, -tangent, tangent)
	return curve


## Длина трассы в метрах (по запечённой кривой).
func get_length() -> float:
	return create_curve().get_baked_length()


## Количество кругов для выбранного режима: Time Trial всегда едет laps кругов.
func get_lap_count(mode_is_time_trial: bool) -> int:
	return laps if mode_is_time_trial else laps
