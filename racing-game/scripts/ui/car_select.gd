extends MenuController
## Выбор машины: 3D-превью с вращением мышью, характеристики полосками,
## список из гаража. Выбор сохраняется в GameState и используется в заезде.

## Скорость авто-вращения превью, рад/с.
@export_range(0.0, 3.0, 0.05) var auto_rotation_speed: float = 0.55
## Чувствительность вращения мышью.
@export_range(0.001, 0.05, 0.001) var drag_sensitivity: float = 0.01

@onready var _car_name: Label = $StatsPanel/StatsBox/CarNameLabel
@onready var _car_desc: Label = $StatsPanel/StatsBox/CarDescLabel
@onready var _mass_label: Label = $StatsPanel/StatsBox/MassLabel
@onready var _speed_bar: ProgressBar = $StatsPanel/StatsBox/SpeedRow/Bar
@onready var _accel_bar: ProgressBar = $StatsPanel/StatsBox/AccelRow/Bar
@onready var _handling_bar: ProgressBar = $StatsPanel/StatsBox/HandlingRow/Bar
@onready var _brakes_bar: ProgressBar = $StatsPanel/StatsBox/BrakesRow/Bar
@onready var _grip_bar: ProgressBar = $StatsPanel/StatsBox/GripRow/Bar
@onready var _list_box: VBoxContainer = $ListPanel/ListBox
@onready var _preview_area: SubViewportContainer = $PreviewArea/PreviewView
@onready var _preview_viewport: SubViewport = $PreviewArea/PreviewView/PreviewViewport
@onready var _preview_car: Node3D = $PreviewArea/PreviewView/PreviewViewport/ShowCar
@onready var _prev_button: Button = $BottomBar/PrevButton
@onready var _next_button: Button = $BottomBar/NextButton
@onready var _back_button: Button = $BottomBar/BackButton
@onready var _select_button: Button = $BottomBar/SelectButton

var _index: int = 0
var _car_buttons: Array[Button] = []
var _dragging: bool = false


func _ready() -> void:
	first_button = $BottomBar/SelectButton.get_path()
	super._ready()
	_index = GameState.get_car_index()
	_setup_preview_viewport()
	_build_car_list()
	_prev_button.pressed.connect(_on_prev)
	_next_button.pressed.connect(_on_next)
	_back_button.pressed.connect(back_to_menu)
	_select_button.pressed.connect(_on_select)
	if _preview_area != null:
		# События мыши ловим на SubViewportContainer — он поверх превью.
		_preview_area.gui_input.connect(_on_preview_gui_input)
	_apply_selection()


func _setup_preview_viewport() -> void:
	if _preview_viewport == null:
		return
	# Своё World3D у SubViewport создаётся само — превью живёт в отдельном мире,
	# поэтому основной сцене оно ничего не навязывает.
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.transparent_bg = false


func _process(delta: float) -> void:
	if _preview_car != null and not _dragging:
		_preview_car.rotate_y(auto_rotation_speed * delta)


func _build_car_list() -> void:
	for button: Button in _car_buttons:
		button.queue_free()
	_car_buttons.clear()
	for index in GameState.cars.size():
		var car: CarStats = GameState.cars[index]
		var button := Button.new()
		button.name = "CarButton_%s" % car.id
		button.text = "%s\n%.0f кг • %.0f км/ч" % [car.display_name, car.mass, car.max_speed * 3.6]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(220, 54)
		button.pressed.connect(_on_car_button_pressed.bind(index))
		_list_box.add_child(button)
		_car_buttons.append(button)


func _on_car_button_pressed(index: int) -> void:
	_index = index
	_apply_selection()


func _on_prev() -> void:
	_index = wrapi(_index - 1, 0, maxi(1, GameState.cars.size()))
	_apply_selection()


func _on_next() -> void:
	_index = wrapi(_index + 1, 0, maxi(1, GameState.cars.size()))
	_apply_selection()


func _on_select() -> void:
	GameState.select_car_by_index(_index)
	back_to_menu()


func _apply_selection() -> void:
	if GameState.cars.is_empty():
		return
	_index = clampi(_index, 0, GameState.cars.size() - 1)
	var car: CarStats = GameState.cars[_index]
	_car_name.text = car.display_name
	_car_desc.text = car.description
	_mass_label.text = "Масса %.0f кг • vmax %.0f км/ч • привод %s" % [
		car.mass, car.max_speed * 3.6, _drivetrain_name(car.drivetrain)
	]
	_speed_bar.value = car.bar_speed * 100.0
	_accel_bar.value = car.bar_acceleration * 100.0
	_handling_bar.value = car.bar_handling * 100.0
	_brakes_bar.value = car.bar_brakes * 100.0
	_grip_bar.value = car.bar_grip * 100.0
	for index in _car_buttons.size():
		_car_buttons[index].disabled = index == _index
	_paint_preview(car)


func _drivetrain_name(drivetrain: int) -> String:
	match drivetrain:
		CarStats.Drivetrain.RWD:
			return "задний"
		CarStats.Drivetrain.FWD:
			return "передний"
	return "полный"


## Красит превью в цвет выбранной машины (Car.tscn в меню без скрипта CarBase).
func _paint_preview(car: CarStats) -> void:
	if _preview_car == null:
		return
	var chassis := _preview_car.get_node_or_null("BodyVisual/Chassis") as MeshInstance3D
	if chassis == null:
		return
	var material := chassis.get_active_material(0) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		chassis.material_override = material
	else:
		material = material.duplicate(true) as StandardMaterial3D
		chassis.material_override = material
	material.albedo_color = car.body_color
	material.metallic = 0.85
	material.roughness = 0.28
	material.clearcoat_enabled = true
	material.clearcoat = 1.0
	var spoiler := _preview_car.get_node_or_null("BodyVisual/Spoiler") as MeshInstance3D
	if spoiler != null:
		var accent := StandardMaterial3D.new()
		accent.albedo_color = car.accent_color
		accent.roughness = 0.5
		spoiler.material_override = accent


## Вращение превью мышью: зажал и потащил.
func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		if _preview_car != null:
			_preview_car.rotate_y(-motion.relative.x * drag_sensitivity)
