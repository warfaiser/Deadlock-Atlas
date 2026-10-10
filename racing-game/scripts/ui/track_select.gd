extends MenuController
## Выбор трассы: карточки с превью, сложностью, длиной и рекордом.
##
## Карточки собираются в коде из GameState.tracks, поэтому добавление нового
## .tres в res://resources/tracks/ сразу даёт новую карточку.

@onready var _cards_box: HBoxContainer = $CardsPanel/CardsScroll/CardsBox
@onready var _preview_rect: TextureRect = $DetailPanel/DetailBox/PreviewRect
@onready var _track_name: Label = $DetailPanel/DetailBox/InfoBox/TrackNameLabel
@onready var _difficulty_label: Label = $DetailPanel/DetailBox/InfoBox/DifficultyLabel
@onready var _length_label: Label = $DetailPanel/DetailBox/InfoBox/LengthLabel
@onready var _laps_label: Label = $DetailPanel/DetailBox/InfoBox/LapsLabel
@onready var _record_label: Label = $DetailPanel/DetailBox/InfoBox/RecordLabel
@onready var _desc_label: Label = $DetailPanel/DetailBox/InfoBox/DescLabel
@onready var _back_button: Button = $BottomBar/BackButton
@onready var _reset_button: Button = $BottomBar/ResetButton
@onready var _start_button: Button = $BottomBar/StartButton

var _index: int = 0
var _cards: Array[Button] = []


func _ready() -> void:
	first_button = $BottomBar/StartButton.get_path()
	super._ready()
	_index = GameState.get_track_index()
	_back_button.pressed.connect(back_to_menu)
	_reset_button.pressed.connect(_on_reset_records)
	_start_button.pressed.connect(_on_start)
	_build_cards()
	_apply_selection()
	if Records != null and not Records.record_updated.is_connected(_on_record_updated):
		Records.record_updated.connect(_on_record_updated)


func _build_cards() -> void:
	for card: Button in _cards:
		card.queue_free()
	_cards.clear()
	for index in GameState.tracks.size():
		var track: TrackData = GameState.tracks[index]
		var card := Button.new()
		card.name = "Card_%s" % track.id
		card.custom_minimum_size = Vector2(230, 190)
		card.clip_text = false
		card.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.expand_icon = true
		card.icon = load_texture(track.preview_path)
		card.text = "%s\n%s • %s\n%.0f м • %d круга\nРекорд: %s" % [
			track.display_name,
			track.get_theme_name(),
			_stars(track.difficulty),
			track.get_length(),
			track.laps,
			Records.format_time(Records.get_track_best_lap(track.id)),
		]
		card.pressed.connect(_on_card_pressed.bind(index))
		_cards_box.add_child(card)
		_cards.append(card)


func _stars(difficulty: int) -> String:
	var value := clampi(difficulty, 1, 5)
	return "★".repeat(value) + "☆".repeat(5 - value)


func _on_card_pressed(index: int) -> void:
	_index = index
	_apply_selection()


func _apply_selection() -> void:
	if GameState.tracks.is_empty():
		_track_name.text = "Трассы не найдены"
		return
	_index = clampi(_index, 0, GameState.tracks.size() - 1)
	var track: TrackData = GameState.tracks[_index]
	GameState.select_track_by_index(_index)

	_track_name.text = track.display_name
	_difficulty_label.text = "Сложность: %s  %s" % [_stars(track.difficulty), track.get_theme_name()]
	_length_label.text = "Длина круга: %.0f м • соперников: %d–%d" % [
		track.get_length(), track.bots_min, track.bots_max
	]
	_laps_label.text = "Кругов: %d • чекпоинтов: %d • сцепление: %.0f%%" % [
		track.laps, maxi(4, track.checkpoint_count), track.surface_grip * 100.0
	]
	var best := Records.get_track_best_lap(track.id)
	var car_best := Records.get_best_lap(track.id, GameState.selected_car.id if GameState.selected_car != null else &"")
	_record_label.text = "Рекорд трассы: %s\nВаш рекорд на %s: %s" % [
		Records.format_time(best),
		GameState.selected_car.display_name if GameState.selected_car != null else "—",
		Records.format_time(car_best),
	]
	_desc_label.text = track.description
	_preview_rect.texture = load_texture(track.preview_path)
	for index in _cards.size():
		_cards[index].disabled = index == _index


func _on_start() -> void:
	GameState.select_track_by_index(_index)
	GameState.start_race()


func _on_reset_records() -> void:
	if GameState.selected_track == null:
		return
	Records.clear_track(GameState.selected_track.id)
	_apply_selection()
	_build_cards()


func _on_record_updated(_track_id: StringName, _car_id: StringName) -> void:
	_apply_selection()
