class_name SkidTrail
extends MeshInstance3D
## Следы шин: «decal» из ImmediateMesh, который машина рисует под задними колёсами.
##
## Узел живёт на уровне трассы (top_level = true), поэтому координаты вершин —
## мировые. Старые сегменты выкидываются, так что память не растёт бесконечно.

## Сколько сегментов (четвёрка вершин) держим в памяти.
const MAX_SEGMENTS: int = 240
## Минимальное расстояние между «отпечатками», метры.
const MIN_STEP: float = 0.4
## Насколько поднять след над дорогой, чтобы не было z-fighting.
const LIFT: float = 0.02

var _immediate := ImmediateMesh.new()
var _trail_material: StandardMaterial3D = null
var _vertices: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _segments: int = 0
var _prev_left: Vector3 = Vector3.INF
var _prev_right: Vector3 = Vector3.INF


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_material = _build_material()
	material_override = _trail_material
	mesh = _immediate
	_rebuild()


func _build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1, 1, 1, 1)
	material.render_priority = -1
	return material


## Добавляет точку контакта задних колёс. intensity 0..1 — сила пробуксовки.
func add_track(left: Vector3, right: Vector3, half_width: float, intensity: float) -> void:
	if left == Vector3.INF or right == Vector3.INF:
		_prev_left = Vector3.INF
		return
	if _prev_left == Vector3.INF:
		_prev_left = left
		_prev_right = right
		return
	if left.distance_to(_prev_left) < MIN_STEP:
		return
	var side := (right - left).normalized()
	if side.length_squared() < 0.5:
		return
	side *= maxf(half_width, 0.05)
	var up := Vector3.UP * LIFT
	var a1 := _prev_left - side + up
	var a2 := _prev_right + side + up
	var b1 := left - side + up
	var b2 := right + side + up
	var alpha := clampf(0.18 + intensity * 0.5, 0.0, 0.75)
	var color := Color(0.06, 0.06, 0.07, alpha)
	# Два треугольника на сегмент.
	_push_triangle(a1, a2, b1, color)
	_push_triangle(b1, a2, b2, color)
	_segments += 1
	_prev_left = left
	_prev_right = right
	if _segments > MAX_SEGMENTS:
		_drop_oldest()
	_rebuild()


func _push_triangle(v1: Vector3, v2: Vector3, v3: Vector3, color: Color) -> void:
	_vertices.append(v1)
	_vertices.append(v2)
	_vertices.append(v3)
	for i in 3:
		_colors.append(color)


## Удаляет самый старый сегмент (6 вершин).
func _drop_oldest() -> void:
	if _vertices.size() < 6:
		return
	_vertices = _vertices.slice(6)
	_colors = _colors.slice(6)
	_segments = maxi(0, _segments - 1)


func _rebuild() -> void:
	_immediate.clear_surfaces()
	if _vertices.is_empty():
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in _vertices.size():
		_immediate.set_color(_colors[index])
		_immediate.add_vertex(_vertices[index])
	_immediate.surface_end()


## Разрыв ленты: после телепорта след не тянется через всю трассу.
func break_strip() -> void:
	_prev_left = Vector3.INF
	_prev_right = Vector3.INF


## Полная очистка (например, рестарт заезда).
func clear_trail() -> void:
	_vertices.clear()
	_colors.clear()
	_segments = 0
	break_strip()
	_rebuild()
