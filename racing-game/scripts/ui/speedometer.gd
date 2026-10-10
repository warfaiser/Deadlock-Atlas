extends Control
## Круглый спидометр + тахометр, нарисованные кодом (без картинок).
##
## Что рисуется:
##   * шкала 0..max с делениями и подписями каждые 20 км/ч;
##   * дуга текущей скорости;
##   * внутренняя дуга тахометра (зелёный -> красный у отсечки);
##   * стрелка, цифры км/ч и номер передачи.
##
## Данные приходят из HUD.set_values(), стрелка доводится плавно в _process().

## Начало шкалы и её развёртка, градусы.
@export var start_angle_deg: float = 135.0
@export var sweep_deg: float = 270.0
## Доля оборотов, с которой тахометр краснеет.
@export_range(0.3, 1.0, 0.01) var redline_ratio: float = 0.78
## Шаг подписей шкалы, км/ч.
@export_range(10.0, 60.0, 5.0) var label_step_kmh: float = 20.0

var _speed_kmh: float = 0.0
var _rpm_ratio: float = 0.0
var _gear: int = 1
var _max_speed_kmh: float = 220.0
var _display_speed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Обновление показаний (вызывает HUD).
func set_values(speed_kmh: float, rpm_ratio: float, gear: int, max_speed_kmh: float) -> void:
	_speed_kmh = maxf(0.0, speed_kmh)
	_rpm_ratio = clampf(rpm_ratio, 0.0, 1.0)
	_gear = gear
	_max_speed_kmh = maxf(60.0, max_speed_kmh)


func _process(delta: float) -> void:
	var next := move_toward(_display_speed, _speed_kmh, delta * 160.0)
	if not is_equal_approx(next, _display_speed):
		_display_speed = next
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	if radius < 10.0:
		return
	var start := deg_to_rad(start_angle_deg)
	var end := deg_to_rad(start_angle_deg + sweep_deg)
	var font := get_theme_default_font()

	# Циферблат.
	draw_circle(center, radius * 1.02, Color(0.05, 0.06, 0.09, 0.85))
	draw_arc(center, radius, start, end, 72, Color(0.24, 0.27, 0.33, 1.0), 5.0)

	# Деления и подписи.
	var steps := int(round(_max_speed_kmh / label_step_kmh))
	for index in steps + 1:
		var ratio := float(index) / float(steps)
		var angle := start + sweep_deg * ratio / 180.0 * PI
		var inner := center + Vector2(cos(angle), sin(angle)) * radius * 0.82
		var outer := center + Vector2(cos(angle), sin(angle)) * radius * 0.96
		var tick_color := Color(0.9, 0.92, 0.95, 1.0)
		if ratio > redline_ratio:
			tick_color = Color(1.0, 0.35, 0.3, 1.0)
		draw_line(inner, outer, tick_color, 3.0 if index % 5 == 0 else 1.5)
		if index % 2 == 0 and font != null:
			var text_pos := center + Vector2(cos(angle), sin(angle)) * radius * 0.66
			draw_string(
				font,
				text_pos + Vector2(-14, 5),
				str(int(ratio * _max_speed_kmh)),
				HORIZONTAL_ALIGNMENT_CENTER,
				28,
				14,
				Color(0.75, 0.8, 0.88, 1.0)
			)

	# Дуга текущей скорости.
	var speed_ratio := clampf(_display_speed / _max_speed_kmh, 0.0, 1.0)
	if speed_ratio > 0.001:
		var speed_color := Color(0.35, 0.78, 1.0, 1.0).lerp(Color(1.0, 0.75, 0.25, 1.0), speed_ratio)
		draw_arc(center, radius * 0.96, start, start + sweep_deg * speed_ratio / 180.0 * PI, 48, speed_color, 4.0)

	# Тахометр: внутренняя дуга.
	var tacho_radius := radius * 0.58
	draw_arc(center, tacho_radius, start, end, 48, Color(0.15, 0.17, 0.21, 1.0), 7.0)
	if _rpm_ratio > 0.001:
		var rpm_color := Color(0.35, 0.9, 0.45, 1.0)
		if _rpm_ratio > redline_ratio:
			rpm_color = Color(1.0, 0.3, 0.25, 1.0)
		draw_arc(
			center,
			tacho_radius,
			start,
			start + sweep_deg * _rpm_ratio / 180.0 * PI,
			32,
			rpm_color,
			7.0
		)

	# Стрелка.
	var needle_angle := start + sweep_deg * speed_ratio / 180.0 * PI
	var needle_tip := center + Vector2(cos(needle_angle), sin(needle_angle)) * radius * 0.9
	draw_line(center, needle_tip, Color(1.0, 0.25, 0.2, 1.0), 3.0)
	draw_circle(center, radius * 0.07, Color(0.85, 0.87, 0.92, 1.0))

	if font == null:
		return
	# Цифры скорости.
	draw_string(
		font,
		center + Vector2(-46, radius * 0.42),
		str(int(round(_display_speed))),
		HORIZONTAL_ALIGNMENT_CENTER,
		92,
		34,
		Color.WHITE
	)
	draw_string(
		font,
		center + Vector2(-30, radius * 0.62),
		"км/ч",
		HORIZONTAL_ALIGNMENT_CENTER,
		60,
		13,
		Color(0.65, 0.7, 0.8, 1.0)
	)
	# Передача.
	draw_string(
		font,
		center + Vector2(-18, -radius * 0.28),
		str(_gear),
		HORIZONTAL_ALIGNMENT_CENTER,
		36,
		26,
		Color(0.95, 0.8, 0.35, 1.0)
	)
