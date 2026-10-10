class_name MenuController
extends Control
## База для экранов меню (MainMenu / CarSelect / TrackSelect).
##
## Даёт общие вещи: звуки кнопок, фоновую музыку, фокус на первой кнопке,
## переходы между сценами и выход из игры.

## Музыка этого экрана.
@export var music_track: StringName = &"music_menu"
## Кнопка, которая получает фокус при открытии (навигация с клавиатуры).
@export var first_button: NodePath = NodePath()
## Включать ли музыку при открытии экрана.
@export var play_music_on_ready: bool = true


func _ready() -> void:
	if AudioManager != null:
		AudioManager.attach_ui_sounds(self)
		if play_music_on_ready:
			AudioManager.play_music(music_track, 1.0)
	_focus_first_button()


func _focus_first_button() -> void:
	if first_button.is_empty():
		return
	var node := get_node_or_null(first_button)
	var control := node as Control
	if control != null:
		control.grab_focus()


## Переход на другую сцену меню/игры.
func goto_scene(path: String) -> void:
	GameState.goto_scene(path)


func back_to_menu() -> void:
	GameState.goto_main_menu()


func quit_game() -> void:
	get_tree().quit()


## Загружает Texture2D по пути и не падает, если файла нет.
func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
