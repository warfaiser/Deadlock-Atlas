# Шрифты

По умолчанию проект использует встроенный шрифт Godot (Open Sans) — он содержит
кириллицу, поэтому русские подписи отображаются без настройки.

Если хочется свой шрифт:

1. Положите `*.ttf` / `*.otf` в эту папку (например `racing.ttf`).
2. В редакторе создайте `FontVariation` или сразу используйте `DynamicFont`:
   `Project Settings → GUI → Theme → Custom Font`, либо назначьте шрифт на
   конкретный `Label`/`Button` через `theme_override_fonts/font`.
3. Для всех контролов сразу: создайте `Theme` с `default_font` и назначьте его
   в `Project Settings → GUI → Theme → Custom Theme`.
