class_name CarStats
extends Resource
## Характеристики машины.
##
## Один такой ресурс = одна машина в гараже. Файлы лежат в `res://resources/cars/`,
## «эталонный» экземпляр — `res://resources/car_stats.tres`.
## Все значения физики читаются из CarBase._apply_stats(), поэтому новую машину
## можно добавить без единой строчки кода: скопируйте .tres и поменяйте цифры.

## Тип привода: влияет на то, какие колёса получают engine_force.
enum Drivetrain { RWD, FWD, AWD }

# --- Идентификация -----------------------------------------------------------
## Короткий уникальный id: по нему пишутся рекорды в user://records.cfg.
@export var id: StringName = &"roadster"
## Название для меню.
@export var display_name: String = "Roadster"
## Путь к иконке/превью в UI (загружается с проверкой, так что битый путь не роняет игру).
@export_file("*.png", "*.webp", "*.svg") var icon_path: String = "res://assets/ui/icons/car_roadster.png"
@export_multiline var description: String = "Сбалансированная машина для любого покрытия."

# --- Полоски в CarSelect (0..1, только для отображения) -----------------------
@export_range(0.0, 1.0, 0.01) var bar_speed: float = 0.6
@export_range(0.0, 1.0, 0.01) var bar_acceleration: float = 0.6
@export_range(0.0, 1.0, 0.01) var bar_handling: float = 0.6
@export_range(0.0, 1.0, 0.01) var bar_brakes: float = 0.6
@export_range(0.0, 1.0, 0.01) var bar_grip: float = 0.6

# --- Физика (значения из ТЗ) -------------------------------------------------
## Масса кузова, кг.
@export var mass: float = 1200.0
## Максимальная сила двигателя. По ТЗ — 800; в Godot engine_force — это сила в
## ньютонах, поэтому реальное усилие = max_engine_force * engine_force_multiplier.
@export var max_engine_force: float = 800.0
## Множитель компенсации массы (см. выше). Сила применяется КАЖДОМУ тяговому
## колесу: для полного привода берите ~2.5, для заднего ~5.0.
@export_range(0.5, 20.0, 0.1) var engine_force_multiplier: float = 5.0
## Базовое тормозное усилие (по ТЗ — 40), домножается на brake_multiplier.
## Важно: в Godot VehicleWheel3D.brake — это предел импульса на колесо за тик
## (кг·м/с), а не сила. Для массы 1200 кг комфортное торможение ≈ 25–35 на колесо.
@export var brake_force: float = 40.0
@export_range(0.1, 4.0, 0.05) var brake_multiplier: float = 0.75
## Максимальный угол поворота руля, радианы.
@export_range(0.05, 1.2, 0.01) var max_steering: float = 0.5
## Ограничение скорости, м/с (55 м/с ≈ 198 км/ч).
@export_range(5.0, 120.0, 1.0) var max_speed: float = 55.0
## Привод.
@export var drivetrain: Drivetrain = Drivetrain.AWD

# --- Подвеска и сцепление ------------------------------------------------------
@export var suspension_stiffness: float = 40.0
@export_range(0.05, 1.0, 0.01) var suspension_travel: float = 0.3
@export_range(0.0, 5.0, 0.05) var damping_compression: float = 0.6
@export_range(0.0, 5.0, 0.05) var damping_relaxation: float = 0.9
## Сцепление передних / задних колёс (по ТЗ: 3.0 и 2.5).
@export_range(0.5, 10.0, 0.05) var wheel_friction_front: float = 3.0
@export_range(0.5, 10.0, 0.05) var wheel_friction_rear: float = 2.5
@export_range(0.0, 1.0, 0.01) var wheel_roll_influence: float = 0.1
## Радиус колеса и «нейтраль» подвески, метры.
@export_range(0.1, 1.0, 0.01) var wheel_radius: float = 0.35
@export_range(0.05, 1.0, 0.01) var wheel_rest_length: float = 0.12

# --- Аэродинамика и повреждения ----------------------------------------------
## Коэффициент лобового сопротивления (F = -drag * v²).
@export_range(0.0, 5.0, 0.01) var drag_coefficient: float = 0.35
## Прочность: сколько «единиц удара» выдерживает машина до нуля.
@export_range(10.0, 500.0, 5.0) var health_max: float = 100.0
## Насколько падает максималка при 100% повреждений (0.4 → -40%).
@export_range(0.0, 0.9, 0.01) var damage_speed_loss: float = 0.4

# --- Внешность ---------------------------------------------------------------
## Цвет краски (используется материалом с clearcoat).
@export var body_color: Color = Color(0.85, 0.12, 0.15, 1.0)
## Цвет дисков/акцентов.
@export var accent_color: Color = Color(0.10, 0.11, 0.14, 1.0)
## Цвет свечения фар/габаритов.
@export var light_color: Color = Color(1.0, 0.93, 0.75, 1.0)


## Человекочитаемая строка для отладки и логов.
func describe() -> String:
	return "%s (%s): %.0f кг, vmax %.0f км/ч" % [
		display_name, id, mass, max_speed * 3.6
	]
