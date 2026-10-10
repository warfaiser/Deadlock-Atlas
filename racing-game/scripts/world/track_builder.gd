class_name TrackBuilder
extends Node3D
## Собирает трассу из ресурса TrackData.
##
## Из одного и того же набора опорных точек получаются:
##   * дорога (ArrayMesh из SurfaceTool: асфальт + обочина + отбойники) с
##     трипланарным шейдером и разметкой;
##   * StaticBody3D-коллизия (ConcavePolygonShape3D) из тех же треугольников;
##   * Path3D с той же Curve3D — по нему едут боты (CarAI + PathFollow3D);
##   * чекпоинты Area3D (минимум 4, чекпоинт 0 = линия старта/финиша);
##   * окружение через MultiMeshInstance3D (здания / камни / ёлки) — один
##     draw call на всю трассу;
##   * земля, WorldEnvironment и DirectionalLight3D с тенями.
##
## Вызов: `track.build(track_data)` — из RaceManager после add_child().

## Шаг сэмплирования дороги по длине, метры.
const ROAD_SAMPLE_STEP: float = 2.0
## Ширина обочины за краем дороги, метры.
const SHOULDER_WIDTH: float = 3.0
## Насколько обочина ниже дороги.
const SHOULDER_DROP: float = 0.08

@onready var _road: MeshInstance3D = $Road
@onready var _collision_shape: CollisionShape3D = $RoadCollision/CollisionShape3D
@onready var _race_path: Path3D = $RacePath
@onready var _checkpoints_root: Node3D = $Checkpoints
@onready var _scenery: MultiMeshInstance3D = $Scenery
@onready var _ground: MeshInstance3D = $Ground
@onready var _start_line: MeshInstance3D = $StartLine
@onready var _environment_controller: Node = $EnvironmentController

## Данные трассы (можно задать в сцене или передать в build()).
@export var data: TrackData = null

var race_curve: Curve3D = null
var track_length: float = 0.0
var checkpoints: Array[Checkpoint] = []
var is_built: bool = false

var _collision_faces := PackedVector3Array()
var _min_y: float = 0.0
var _max_y: float = 0.0


func _ready() -> void:
	if data != null:
		build(data)


## Главная точка входа: строит всё по описанию трассы.
func build(track_data: TrackData) -> void:
	if track_data == null:
		push_error("[TrackBuilder] build(): не передан TrackData.")
		return
	data = track_data
	race_curve = data.create_curve()
	track_length = race_curve.get_baked_length()
	if track_length <= 0.0:
		push_error("[TrackBuilder] Не удалось построить кривую трассы '%s'." % data.id)
		return
	_race_path.curve = race_curve
	_race_path.position = Vector3.ZERO
	_measure_height_range()
	_build_road()
	_build_ground()
	_build_checkpoints()
	_build_start_line()
	_build_scenery()
	if _environment_controller != null and _environment_controller.has_method("setup"):
		_environment_controller.call("setup", data, _environment_for_controller())
	is_built = true
	print("[TrackBuilder] '%s': длина %.0f м, точек %d, чекпоинтов %d" % [
		data.display_name, track_length, race_curve.get_baked_points().size(), checkpoints.size()
	])


func _environment_for_controller() -> WorldEnvironment:
	return get_node_or_null("WorldEnvironment") as WorldEnvironment


func _measure_height_range() -> void:
	_min_y = INF
	_max_y = -INF
	for point: Vector3 in race_curve.get_baked_points():
		_min_y = minf(_min_y, point.y)
		_max_y = maxf(_max_y, point.y)
	if not is_finite(_min_y):
		_min_y = 0.0
		_max_y = 0.0


# --- Дорога и коллизия -------------------------------------------------------


func _build_road() -> void:
	var points := race_curve.get_baked_points()
	var count := points.size()
	if count < 4:
		push_error("[TrackBuilder] Слишком мало точек для дороги.")
		return

	var width := data.road_width
	var distance := 0.0
	var prev_left := Vector3.ZERO
	var prev_right := Vector3.ZERO
	var prev_shoulder_l := Vector3.ZERO
	var prev_shoulder_r := Vector3.ZERO
	var prev_distance := 0.0
	var has_prev := false

	var asphalt_st := SurfaceTool.new()
	var shoulder_st := SurfaceTool.new()
	var wall_st := SurfaceTool.new()
	asphalt_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	shoulder_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_collision_faces.clear()

	for i in count:
		var point := points[i]
		var next_point := points[(i + 1) % count]
		var prev_point := points[(i - 1 + count) % count]
		var tangent := next_point - prev_point
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.BACK
		tangent = tangent.normalized()
		var right := tangent.cross(Vector3.UP)
		if right.length_squared() < 0.000001:
			right = Vector3.RIGHT
		right = right.normalized()
		var normal := right.cross(tangent).normalized()

		var left := point - right * width
		var right_edge := point + right * width
		var shoulder_left := left - right * SHOULDER_WIDTH + Vector3.DOWN * SHOULDER_DROP
		var shoulder_right := right_edge + right * SHOULDER_WIDTH + Vector3.DOWN * SHOULDER_DROP
		distance += point.distance_to(next_point)

		if has_prev:
			var v_prev := prev_distance / 4.0
			var v_now := distance / 4.0
			# Асфальт: u — поперёк дороги (0 слева, 1 справа), v — вдоль.
			_add_quad(asphalt_st, prev_left, prev_right, right_edge, left,
				Vector2(0.0, v_prev), Vector2(1.0, v_prev), Vector2(1.0, v_now), Vector2(0.0, v_now), normal)
			_add_collision_quad(prev_left, prev_right, right_edge, left)
			# Обочины.
			_add_quad(shoulder_st, prev_shoulder_l, prev_left, left, shoulder_left,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal)
			_add_quad(shoulder_st, prev_right, prev_shoulder_r, shoulder_right, right_edge,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal)
			# Отбойники: вертикальные стенки по краям + треугольники в коллизию.
			_add_barrier(wall_st, shoulder_left, -right, tangent)
			_add_barrier(wall_st, shoulder_right, right, tangent)

		prev_left = left
		prev_right = right_edge
		prev_shoulder_l = shoulder_left
		prev_shoulder_r = shoulder_right
		prev_distance = distance
		has_prev = true

	var mesh := ArrayMesh.new()
	asphalt_st.generate_normals()
	asphalt_st.generate_tangents()
	asphalt_st.set_material(_asphalt_material())
	asphalt_st.commit(mesh)
	shoulder_st.generate_normals()
	shoulder_st.set_material(_shoulder_material())
	shoulder_st.commit(mesh)
	wall_st.generate_normals()
	wall_st.set_material(_wall_material())
	wall_st.commit(mesh)

	_road.mesh = mesh
	_road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_collision_faces)
	_collision_shape.shape = shape


## Один квад дороги + его нормаль.
func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2,
	uv_d: Vector2,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)

	st.set_normal(normal)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_d)
	st.add_vertex(d)


## Два треугольника в коллизию (порядок вершин задаёт сторону).
func _add_collision_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_collision_faces.append(a)
	_collision_faces.append(b)
	_collision_faces.append(c)
	_collision_faces.append(a)
	_collision_faces.append(c)
	_collision_faces.append(d)


## Отбойник: стенка высотой barrier_height + её коллизия.
## facing — горизонтальная нормаль стенки (наружу от дороги).
func _add_barrier(st: SurfaceTool, base: Vector3, facing: Vector3, tangent: Vector3) -> void:
	var height := maxf(data.barrier_height, 0.2)
	var top := base + Vector3.UP * height
	var side := tangent * 1.0
	var a := base - side
	var b := base + side
	var c := top + side
	var d := top - side
	_add_quad(st, a, b, c, d, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, facing)
	_add_collision_quad(a, b, c, d)
	# Обратная сторона, чтобы машина не проваливалась при ударе с другой стороны.
	_add_collision_quad(b, a, d, c)


# --- Материалы ---------------------------------------------------------------


func _asphalt_material() -> Material:
	var shader_path := "res://assets/shaders/asphalt.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader := load(shader_path) as Shader
		if shader != null:
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("asphalt_color", data.asphalt_color)
			material.set_shader_parameter("marking_color", data.marking_color)
			material.set_shader_parameter("roughness_value", 0.65 if data.theme == TrackData.Theme.CITY else 0.85)
			material.set_shader_parameter("marking_repeat", 0.35)
			return material
	# Запасной вариант: обычный PBR без шейдера.
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = data.asphalt_color
	fallback.roughness = 0.9
	fallback.metallic = 0.0
	return fallback


func _shoulder_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _theme_shoulder_color()
	material.roughness = 1.0
	material.metallic = 0.0
	return material


func _wall_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.56, 0.6, 1.0)
	material.roughness = 0.75
	material.metallic = 0.1
	return material


func _theme_shoulder_color() -> Color:
	match data.theme:
		TrackData.Theme.DESERT:
			return Color(0.62, 0.52, 0.36, 1.0)
		TrackData.Theme.SNOW:
			return Color(0.86, 0.89, 0.94, 1.0)
	return Color(0.28, 0.30, 0.24, 1.0)


# --- Земля -------------------------------------------------------------------


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	var size := 2400.0
	plane.size = Vector2(size, size)
	_ground.mesh = plane
	_ground.position = Vector3(0.0, _min_y - 0.6, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = data.ground_color
	material.roughness = 1.0
	material.metallic = 0.0
	_ground.material_override = material


# --- Чекпоинты ---------------------------------------------------------------


func _build_checkpoints() -> void:
	for child: Node in _checkpoints_root.get_children():
		child.queue_free()
	checkpoints.clear()
	var count := maxi(4, data.checkpoint_count)
	for index in count:
		var offset := track_length * float(index) / float(count)
		var checkpoint := _make_checkpoint(index, offset, index == 0)
		_checkpoints_root.add_child(checkpoint)
		checkpoints.append(checkpoint)


func _make_checkpoint(index: int, offset: float, is_finish: bool) -> Checkpoint:
	var position := race_curve.sample_baked(offset)
	var tangent := _tangent_at(offset)
	var basis := Basis.looking_at(tangent, Vector3.UP)
	var checkpoint := Checkpoint.new()
	checkpoint.name = "Checkpoint%02d" % index
	checkpoint.index = index
	checkpoint.is_finish = is_finish
	checkpoint.road_width = data.road_width
	checkpoint.collision_layer = 4
	checkpoint.collision_mask = 2
	checkpoint.transform = Transform3D(basis, position + Vector3.UP * 1.6)
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(data.road_width * 2.0 + 4.0, 6.0, 1.2)
	shape_node.shape = box
	checkpoint.add_child(shape_node)
	return checkpoint


## Касательная к трассе на заданном расстоянии от старта.
func _tangent_at(offset: float) -> Vector3:
	var ahead := race_curve.sample_baked(fposmod(offset + 0.75, track_length))
	var behind := race_curve.sample_baked(fposmod(offset - 0.75, track_length))
	var tangent := ahead - behind
	tangent.y = 0.0
	if tangent.length_squared() < 0.000001:
		return Vector3.BACK
	return tangent.normalized()


# --- Линия старта/финиша -----------------------------------------------------


func _build_start_line() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(data.road_width * 2.0, 2.4)
	_start_line.mesh = quad
	var position := race_curve.sample_baked(0.0)
	var tangent := _tangent_at(0.0)
	# QuadMesh лежит в плоскости XY, разворачиваем его на дорогу.
	var basis := Basis.looking_at(tangent, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	_start_line.transform = Transform3D(basis, position + Vector3.UP * 0.05)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _checker_texture()
	material.roughness = 0.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_start_line.material_override = material


## Шахматная текстура 8×8 для линии финиша.
func _checker_texture() -> ImageTexture:
	var size := 8
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var white: bool = (x + y) % 2 == 0
			image.set_pixel(x, y, Color.WHITE if white else Color(0.05, 0.05, 0.05, 1.0))
	var texture := ImageTexture.create_from_image(image)
	return texture


# --- Окружение ---------------------------------------------------------------


func _build_scenery() -> void:
	var amount := data.scenery_count
	if amount <= 0 or _scenery == null:
		if _scenery != null:
			_scenery.visible = false
		return
	var mesh := _theme_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_color = _theme_scenery_color()
	material.roughness = 0.9
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = material

	var transforms: Array[Transform3D] = []
	var attempts := 0
	var max_attempts := amount * 12
	while transforms.size() < amount and attempts < max_attempts:
		attempts += 1
		var offset := randf() * track_length
		var base := race_curve.sample_baked(offset)
		var tangent := _tangent_at(offset)
		var right := tangent.cross(Vector3.UP).normalized()
		var side := 1.0 if randf() > 0.5 else -1.0
		var distance := randf_range(data.scenery_min_distance, data.scenery_max_distance)
		var position := base + right * side * distance
		position += Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		# Не ставим объект на дорогу и не прячем его под землю.
		var closest := race_curve.get_closest_point(position)
		if position.distance_to(closest) < data.scenery_min_distance * 0.85:
			continue
		var scale := _theme_scale()
		position.y = closest.y + scale.y * 0.5
		var instance_basis := Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(scale)
		transforms.append(Transform3D(instance_basis, position))

	if transforms.is_empty():
		_scenery.visible = false
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	_scenery.multimesh = multimesh


## Меш зависит от темы: здания / камни / ёлки.
func _theme_mesh() -> Mesh:
	match data.theme:
		TrackData.Theme.CITY:
			var box := BoxMesh.new()
			box.size = Vector3(1.0, 1.0, 1.0)
			return box
		TrackData.Theme.DESERT:
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 8
			sphere.rings = 4
			return sphere
		TrackData.Theme.SNOW:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = 8
			cone.rings = 1
			return cone
	var fallback := BoxMesh.new()
	fallback.size = Vector3.ONE
	return fallback


func _theme_scale() -> Vector3:
	match data.theme:
		TrackData.Theme.CITY:
			return Vector3(randf_range(8.0, 16.0), randf_range(10.0, 46.0), randf_range(8.0, 16.0))
		TrackData.Theme.DESERT:
			var size := randf_range(1.5, 5.0)
			return Vector3(size, size * randf_range(0.5, 1.0), size)
		TrackData.Theme.SNOW:
			var height := randf_range(5.0, 12.0)
			return Vector3(height * 0.5, height, height * 0.5)
	return Vector3.ONE * 2.0


func _theme_scenery_color() -> Color:
	match data.theme:
		TrackData.Theme.CITY:
			return Color(0.42, 0.45, 0.52, 1.0)
		TrackData.Theme.DESERT:
			return Color(0.6, 0.45, 0.3, 1.0)
		TrackData.Theme.SNOW:
			return Color(0.16, 0.32, 0.2, 1.0)
	return Color(0.4, 0.45, 0.35, 1.0)


# --- Доступ для RaceManager --------------------------------------------------


func get_race_path() -> Path3D:
	return _race_path


func get_checkpoints() -> Array[Checkpoint]:
	return checkpoints


## Стартовое место на решётке: index-я позиция из total.
func get_start_transform(index: int, total: int) -> Transform3D:
	var checkpoint := checkpoints[0] if not checkpoints.is_empty() else null
	if checkpoint == null:
		return Transform3D.IDENTITY
	# Два ряда по центру дороги; каждый следующий ряд на 7 метров дальше от линии.
	var lane := index % 2
	var row := index / 2
	var forward := -checkpoint.global_basis.z
	var side_dir := checkpoint.global_basis.x
	var lateral := data.road_width * 0.42 * (1.0 if lane == 0 else -1.0)
	var origin := checkpoint.global_position
	origin -= forward * (4.0 + float(row) * 7.0)
	origin += side_dir * lateral
	origin += Vector3.UP * 0.8
	return Transform3D(checkpoint.global_basis, origin)


## Точка на трассе по расстоянию от старта (для телепорта и отладки).
func get_point_at(offset: float) -> Vector3:
	if race_curve == null:
		return Vector3.ZERO
	return race_curve.sample_baked(fposmod(offset, track_length))
