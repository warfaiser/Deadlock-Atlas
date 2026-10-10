extends Node
## InputBootstrap (autoload).
##
## Страховка для InputMap: если действия из `project.godot` кто-то удалил
## (или проект открыли в чужом конфиге), игра не развалится на первом же
## `Input.get_action_strength("accelerate")`, а экшены будут созданы заново.

## Имя экшена -> список физических клавиш.
const KEYBOARD_ACTIONS: Dictionary = {
	&"accelerate": [KEY_W, KEY_UP],
	&"brake": [KEY_S, KEY_DOWN],
	&"steer_left": [KEY_A, KEY_LEFT],
	&"steer_right": [KEY_D, KEY_RIGHT],
	&"handbrake": [KEY_SPACE],
	&"reset_car": [KEY_R],
	&"pause": [KEY_ESCAPE],
}

## Мёртвая зона для каждого действия.
const DEADZONES: Dictionary = {
	&"accelerate": 0.15,
	&"brake": 0.15,
	&"steer_left": 0.2,
	&"steer_right": 0.2,
	&"handbrake": 0.2,
	&"reset_car": 0.2,
	&"pause": 0.2,
}


func _ready() -> void:
	for action: StringName in KEYBOARD_ACTIONS:
		_ensure_action(action, KEYBOARD_ACTIONS[action], DEADZONES.get(action, 0.2))


## Создаёт экшен, если его нет в InputMap.
func _ensure_action(action: StringName, keys: Array, deadzone: float) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	print("[InputBootstrap] Создано отсутствующее действие ввода: %s" % action)
