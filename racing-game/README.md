# Velocity Atlas — гонки на прохождение (Godot 4.7.2)

Аркадные гонки с двумя режимами: **Time Trial** (заезд на время) и **Race**
(гонка с 3–7 ботами). Полностью на GDScript 2.0, без внешних ассетов — вся
графика собирается процедурно, звуки синтезированы в OGG.

Проверено на **Godot 4.7.2** (Forward Plus). Код проекта проходит:

* `gdparse` — парсинг каждого `.gd` реальной грамматикой Godot;
* `gdlint` — линтер (конфиг в `gdlint.toml`);
* `tools/validate_godot_project.py` — кросс-проверка сцен/скриптов/путей/ввода
  (см. ниже).

---

## Установка и запуск

1. Установите **Godot 4.7.x** (стандартная, не .NET): <https://godotengine.org/download>.
2. Откройте в редакторе `racing-game/project.godot` («Import» → выбрать файл).
   При первом открытии Godot импортирует звуки/картинки в `.godot/`.
3. Нажмите **F5** (или ▶). Загрузится главное меню.

Головless-проверка без редактора (если установлен godot в PATH):

```
godot --headless --path racing-game --quit-after 1   # просто стартует и выйдет
```

Управление: `W/↑` газ · `S/↓` тормоз/реверс · `A/D` или `←/→` руль ·
`Space` ручник · `R` вернуться на чекпоинт · `Esc` пауза. Геймпад поддерживается.

## Режимы и правила

* **Time Trial** — только игрок, 3 круга (или `laps` трассы), замер времени.
* **Race** — игрок + боты (3–7), позиции в реальном времени (1st/2nd/…).
* Пропуск чекпоинта = **+5 сек** штрафа.
* Рекорды (лучший круг, общее время, позиция) автосохраняются в
  `user://records.cfg` и показываются в TrackSelect/Results.
* Боты: Easy 0.75x, Normal 0.9x, Hard 1.0x + агрессия (обгоны, ручник).

---

## Структура проекта

```
project.godot              конфиг: autoload, input map, rendering
scenes/
  MainMenu.tscn            меню + живой 3D-фон с вращающейся машиной
  CarSelect.tscn           3D-превью (вращение мышью) + полоски характеристик
  TrackSelect.tscn         карточки трасс: превью, сложность, длина, рекорд
  Race.tscn                HUD (спидометр, тахометр, мини-карта, позиции),
                           отсчёт 3-2-1-GO, motion blur, пауза
  PauseMenu.tscn           Resume / Restart / Settings / Menu / Exit
  Results.tscn             таблица финиша + Replay / Next Track / Menu
  SettingsPanel.tscn       общая панель настроек (в меню и в паузе)
scripts/
  car_base.gd              VehicleBody3D + 4 колеса: тяга/тормоз/руль/ручник,
                           крен кузова, дым, следы шин, звук мотора, повреждения
  car_player.gd            ввод игрока + камера-пружина (SpringArm3D)
  car_ai.gd                Path3D+PathFollow3D, обгоны RayCast3D, respawn
  race_manager.gd          спавн, отсчёт, чекпоинты, круги, позиции, финиш
  checkpoint.gd / lap_timer.gd
  menu_controller.gd       база экранов меню
  autoload/                GameState, Records, AudioManager, SettingsManager, InputBootstrap
  data/                    CarStats, TrackData (Resource)
  ui/                      hud, speedometer, меню, результаты, настройки
  world/                   track_builder (дорога/колизия/чекпоинты/scenery),
                           environment_controller (SSAO/SDFGI/SSR/туман/небо), skid_trail
assets/
  models/Car.tscn, CarPlayer.tscn, CarAI.tscn, Track.tscn
  sounds/*.ogg             синтезированные (tools/generate_racing_audio.py)
  shaders/                 asphalt.gdshader (трипланар+разметка), motion_blur.gdshader
  ui/icons/*.png           иконки машин и схемы трасс (tools/generate_racing_icons.py)
resources/
  car_stats.tres, track_data.tres
  cars/*.tres (5), tracks/*.tres (City/Desert/Snow)
```

## Как добавлять контент (без кода)

* **Новая машина**: скопируйте `resources/cars/roadster.tres`, поменяйте числа и
  цвета, положите иконку `assets/ui/icons/car_<id>.png`. Она появится в CarSelect.
* **Новая трасса**: скопируйте `resources/tracks/city.tres`, отредактируйте
  `control_points` (замкнутая петля в метрах), `theme` (0 город / 1 пустыня /
  2 снег), цвета, `surface_grip` и превью. Она появится в TrackSelect. Дорога,
  коллизия, Path3D для ботов и чекпоинты строятся из этих точек автоматически.

Перегенерировать ассеты после правок:

```
pip install numpy soundfile gdtoolkit
python3 tools/generate_racing_audio.py      # звуки
python3 tools/generate_racing_icons.py      # иконки/превью (нужен ImageMagick)
python3 tools/generate_racing_resources.py  # .tres (если правите шаблон генератора)
python3 tools/validate_godot_project.py     # кросс-проверка
```

## Проверка (что гоняет CI-стиль валидатор)

`tools/validate_godot_project.py`:

1. `gdparse` — каждый `.gd` синтаксически валиден.
2. Все `ext_resource` в сценах указывают на существующие файлы.
3. Автозагрузки из `project.godot` существуют.
4. `[connection]` в сценах ссылаются на реально существующие методы.
5. **Все `$A/B` и `get_node("A/B")` из скриптов разрешаются в дереве сцен**
   (с раскрытием вложенных `Car.tscn` / `PauseMenu.tscn` / `SettingsPanel.tscn`) —
   главный источник «Node not found».
6. Экшены ввода из скриптов объявлены в `[input]`.
7. Литералы `res://…` существуют.

## Замечания по физике (важно)

В Godot `VehicleBody3D.engine_force` и `brake` — это **ньютон-силы/импульсы на
колесо**, а «800» из ТЗ для массы 1200 кг слишком мало. Поэтому в `CarStats`
есть честные базовые значения из ТЗ (`max_engine_force = 800`, `brake_force = 40`)
и компенсационные множители `engine_force_multiplier` / `brake_multiplier`,
подобранные под каждую машину. Крутите их, если хотите иной «характер».
