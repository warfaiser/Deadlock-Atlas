class_name Checkpoint
extends Area3D
## Контрольная точка трассы (Area3D).
##
## Задача узла — только сообщить, что машина пересекла плоскость. Всю логику
## кругов, штрафов и позиций ведёт RaceManager: он подписывается на car_passed.
##
## Порядок точек задаётся свойством index (0..N-1). Чекпоинт 0 — линия
## старта/финиша: он стоит первым в круге и замыкает его, то есть фактически
## является последним чекпоинтом круга.

## Машина пересекла чекпоинт.
signal car_passed(checkpoint: Checkpoint, car: CarBase)

## Порядковый номер в круге.
@export var index: int = 0
## true для линии старта/финиша (нужно для звука и визуала).
@export var is_finish: bool = false
## Ширина проезжей части в этом месте, метры (для расстановки на старте).
@export var road_width: float = 12.0


func _ready() -> void:
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarBase
	if car == null:
		return
	car_passed.emit(self, car)


## Мировой трансформ для возрождения/старта: смотрим вдоль трассы.
func get_gate_transform() -> Transform3D:
	return global_transform


## Точка возрождения для конкретной машины: со смещением вбок, чтобы боты
## не появлялись друг в друге.
func get_respawn_transform(lane_offset: float) -> Transform3D:
	var side := global_basis.x
	var origin := global_position + side * lane_offset + Vector3.UP * 0.6
	return Transform3D(global_basis, origin)
