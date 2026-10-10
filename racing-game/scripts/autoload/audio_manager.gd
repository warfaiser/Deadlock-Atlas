extends Node
## AudioManager (autoload) — музыка и звук интерфейса.
##
## Что делает:
##   * кэширует AudioStream из `res://assets/sounds/` (ищет .ogg, затем .wav);
##   * включает loop для петлевых дорожек прямо в коде — так не зависит от
##     настроек импорта в `.import`;
##   * держит пул AudioStreamPlayer для коротких звуков UI/событий;
##   * плавно сводит фоновую музыку (Tween по volume_db).
##
## Трёхмерные звуки (двигатель, удары) живут в самих машинах:
## CarBase создаёт AudioStreamPlayer3D и берёт поток через AudioManager.get_sound().

## Звуки, которые должны зацикливаться.
const LOOPING_SOUNDS: Array[StringName] = [&"engine_loop", &"tire_squeal", &"music_menu", &"music_race"]

const SOUNDS_DIR: String = "res://assets/sounds/"
## Порядок перебора расширений: можно положить свои .ogg — они подхватятся первыми.
const EXTENSIONS: Array[String] = ["ogg", "wav"]

const SFX_POOL_SIZE: int = 10
const MUSIC_FADE_DB: float = -60.0

var _cache: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _music_player: AudioStreamPlayer = null
var _current_music: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = _resolve_bus("Music")
	_music_player.volume_db = MUSIC_FADE_DB
	add_child(_music_player)
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.bus = _resolve_bus("SFX")
		add_child(player)
		_sfx_pool.append(player)
	# Шины созданы — теперь громкости из настроек можно применить.
	if SettingsManager != null:
		SettingsManager.apply_all()


## Добавляет шину, если её нет в текущем AudioBusLayout.
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


## Возвращает имя шины, если она есть в AudioBusLayout, иначе "Master".
func _resolve_bus(bus_name: String) -> String:
	return bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"


## Загружает (и кэширует) поток по короткому имени, например "crash".
func get_sound(sound_name: StringName) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var stream: AudioStream = null
	for extension: String in EXTENSIONS:
		var path := "%s%s.%s" % [SOUNDS_DIR, sound_name, extension]
		if ResourceLoader.exists(path):
			stream = load(path)
			if stream != null:
				break
	if stream == null:
		push_warning("[AudioManager] Не найден звук '%s' в %s" % [sound_name, SOUNDS_DIR])
	else:
		_configure_loop(stream, sound_name in LOOPING_SOUNDS)
	_cache[sound_name] = stream
	return stream


## Ставит флаги цикла: работает и для OGG, и для WAV.
func _configure_loop(stream: AudioStream, should_loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = should_loop
		ogg.loop_offset = 0.0
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if should_loop:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.mix_rate * int(wav.get_length())
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


## Короткий 2D-звук (интерфейс, события гонки).
func play_sfx(sound_name: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream := get_sound(sound_name)
	if stream == null or _sfx_pool.is_empty():
		return
	var player := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch_scale, 0.1, 4.0)
	player.play()


func play_ui_click() -> void:
	play_sfx(&"ui_click", -6.0)


func play_ui_hover() -> void:
	play_sfx(&"ui_hover", -14.0)


## Трёхмерный звук рядом с узлом (удар, чекпоинт). Узел сам себя удаляет.
func play_sfx_3d(sound_name: StringName, anchor: Node3D, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if anchor == null or not is_instance_valid(anchor):
		play_sfx(sound_name, volume_db, pitch_scale)
		return
	var stream := get_sound(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = _resolve_bus("SFX")
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.unit_size = 12.0
	player.max_distance = 220.0
	player.autoplay = true
	player.finished.connect(player.queue_free)
	anchor.add_child(player)


# --- Музыка ------------------------------------------------------------------


func get_current_music() -> StringName:
	return _current_music


## Включает трек с кроссфейдом. Повторный вызов с тем же именем ничего не делает.
func play_music(sound_name: StringName, fade_seconds: float = 0.9) -> void:
	if sound_name == _current_music and _music_player.playing:
		return
	var stream := get_sound(sound_name)
	if stream == null:
		return
	_current_music = sound_name
	_music_player.stream = stream
	_music_player.volume_db = MUSIC_FADE_DB
	_music_player.play()
	_fade_music_to(linear_to_db(maxf(SettingsManager.music_volume, 0.0001) * 0.9), fade_seconds)


func stop_music(fade_seconds: float = 0.7) -> void:
	if not _music_player.playing:
		_current_music = &""
		return
	_fade_music_to(MUSIC_FADE_DB, fade_seconds)
	await get_tree().create_timer(fade_seconds).timeout
	if _music_player.volume_db <= MUSIC_FADE_DB + 0.5:
		_music_player.stop()
		_current_music = &""


func _fade_music_to(target_db: float, seconds: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_music_player, "volume_db", target_db, maxf(0.05, seconds))


## Подвешивает звуки hover/click на все кнопки в поддереве.
## Вызывается из MenuController для любого экрана.
func attach_ui_sounds(root: Node) -> void:
	if root == null:
		return
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		if not button.mouse_entered.is_connected(_on_button_hovered):
			button.mouse_entered.connect(_on_button_hovered)
		if not button.pressed.is_connected(_on_button_pressed):
			button.pressed.connect(_on_button_pressed)


func _on_button_hovered() -> void:
	play_ui_hover()


func _on_button_pressed() -> void:
	play_ui_click()
