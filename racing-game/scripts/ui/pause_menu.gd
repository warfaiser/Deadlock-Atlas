extends CanvasLayer
## Меню паузы (Esc): Resume, Restart, Settings, Main Menu, Exit.
##
## Узел работает в PROCESS_MODE_ALWAYS, поэтому ловит Esc даже на паузе,
## и сам ставит дерево на паузу. Открытие/закрытие — toggle().

@onready var _panel: PanelContainer = $Panel
@onready var _resume_button: Button = $Panel/VBox/ResumeButton
@onready var _restart_button: Button = $Panel/VBox/RestartButton
@onready var _settings_button: Button = $Panel/VBox/SettingsButton
@onready var _menu_button: Button = $Panel/VBox/MenuButton
@onready var _quit_button: Button = $Panel/VBox/QuitButton
@onready var _hint_label: Label = $Panel/VBox/HintLabel
@onready var _settings_panel: Control = $SettingsPanel

var is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	visible = false
	if AudioManager != null:
		AudioManager.attach_ui_sounds(self)
	_resume_button.pressed.connect(close)
	_restart_button.pressed.connect(_on_restart)
	_settings_button.pressed.connect(_on_settings)
	_menu_button.pressed.connect(_on_main_menu)
	_quit_button.pressed.connect(_on_quit)
	if _settings_panel != null:
		if _settings_panel.has_method("close"):
			_settings_panel.call("close")
		if _settings_panel.has_signal("closed"):
			_settings_panel.connect("closed", _on_settings_closed)
	_hint_label.text = "W/↑ — газ,  S/↓ — тормоз и реверс,  A/D — руль\nSpace — ручник,  R — вернуться на чекпоинт,  Esc — пауза"


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Открыть/закрыть меню.
func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()
	if _settings_panel != null and _settings_panel.has_method("close"):
		_settings_panel.call("close")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false


func _on_restart() -> void:
	close()
	GameState.start_race()


func _on_main_menu() -> void:
	close()
	AudioManager.stop_music(0.5)
	GameState.goto_main_menu()


func _on_quit() -> void:
	get_tree().quit()


func _on_settings() -> void:
	if _settings_panel != null and _settings_panel.has_method("open"):
		_settings_panel.call("open")


func _on_settings_closed() -> void:
	_resume_button.grab_focus()
