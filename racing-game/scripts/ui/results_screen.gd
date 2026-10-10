extends MenuController
## Экран результатов: таблица финиша, времена, позиция и кнопки
## Replay / Next Track / Main Menu.
##
## Данные берёт из GameState.last_result (их кладёт RaceManager).

@onready var _title: Label = $HeaderPanel/HeaderBox/TitleLabel
@onready var _summary_position: Label = $SummaryPanel/SummaryBox/PositionLabel
@onready var _summary_total: Label = $SummaryPanel/SummaryBox/TotalLabel
@onready var _summary_best: Label = $SummaryPanel/SummaryBox/BestLabel
@onready var _summary_penalty: Label = $SummaryPanel/SummaryBox/PenaltyLabel
@onready var _summary_record: Label = $SummaryPanel/SummaryBox/RecordLabel
@onready var _table_box: VBoxContainer = $TablePanel/TableScroll/TableBox
@onready var _replay_button: Button = $BottomBar/ReplayButton
@onready var _next_button: Button = $BottomBar/NextButton
@onready var _menu_button: Button = $BottomBar/MenuButton


func _ready() -> void:
	first_button = $BottomBar/ReplayButton.get_path()
	super._ready()
	_replay_button.pressed.connect(_on_replay)
	_next_button.pressed.connect(_on_next_track)
	_menu_button.pressed.connect(back_to_menu)
	_next_button.disabled = GameState.tracks.size() < 2
	_fill_from_result(GameState.last_result)


func _fill_from_result(result: Dictionary) -> void:
	if result.is_empty():
		_title.text = "Нет данных о заезде"
		_summary_position.text = "Запустите гонку из главного меню"
		return
	_title.text = "%s — %s" % [result.get("track_name", "Трасса"), result.get("mode", "")]
	_summary_position.text = "Место: %d из %d  (%s)" % [
		int(result.get("position", 0)), int(result.get("total_racers", 1)), result.get("difficulty", "")
	]
	_summary_total.text = "Общее время: %s" % Records.format_time(float(result.get("total_time", 0.0)))
	_summary_best.text = "Лучший круг: %s" % Records.format_time(float(result.get("best_lap", 0.0)))
	var penalty := float(result.get("penalty", 0.0))
	_summary_penalty.visible = penalty > 0.0
	_summary_penalty.text = "Штрафы: +%.0f сек (пропущенные чекпоинты)" % penalty

	var records: Array[String] = []
	if bool(result.get("new_lap_record", false)):
		records.append("новый рекорд круга")
	if bool(result.get("new_total_record", false)):
		records.append("новое лучшее время")
	if bool(result.get("new_position_record", false)):
		records.append("лучшая позиция")
	_summary_record.visible = not records.is_empty()
	_summary_record.text = "Достижение: " + ", ".join(records)

	_build_table(result.get("rows", []))


func _build_table(rows: Array) -> void:
	for child: Node in _table_box.get_children():
		child.queue_free()
	var header := Label.new()
	header.name = "HeaderRow"
	header.text = "Место   Гонщик            Время        Лучший круг"
	header.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 1.0))
	_table_box.add_child(header)

	for row_variant: Variant in rows:
		var row: Dictionary = row_variant
		var label := Label.new()
		label.text = "%2d.      %-16s %10s   %10s%s" % [
			int(row.get("position", 0)),
			row.get("name", "—"),
			Records.format_time(float(row.get("total_time", 0.0))),
			Records.format_time(float(row.get("best_lap", 0.0))),
			"   ФИНИШ" if bool(row.get("finished", false)) else "",
		]
		if bool(row.get("is_player", false)):
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
		_table_box.add_child(label)


func _on_replay() -> void:
	GameState.start_race()


func _on_next_track() -> void:
	GameState.next_track()
	GameState.start_race()
