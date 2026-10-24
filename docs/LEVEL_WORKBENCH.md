# Авторская мастерская уровней

Отдельная native сцена Godot для TOOL-01/WP33/AT-079. В обычном игровом меню ссылки нет; player progress и настройки не загружаются и не сохраняются. Сцена использует production `StageView` и отдельное детерминированное ядро.

Из корня пакета:

```bash
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --path almost-god/game tools/level_workbench.tscn
```

Выберите L01–L30 либо откройте JSON с диска. Режимы: слоты, точки результата, точки механизма, абсолютные концы преград. Маркер можно перетащить по целой сетке24×28 или задать XY. Undo/Ctrl+Z и Redo возвращают authoring data и preview; максимум50правок. Непригодная правка отклоняется с сообщением, прежняя сцена остаётся.

Слот хранит абсолютную позицию. Переграда хранит абсолютный segment, поэтому перемещение слота ширмы **не** сдвигает её segment: для нового положения отредактируйте оба конца отдельно. Evidence anchor хранит offset относительно своего entity; редактор вычисляет offset от видимого текущего положения этого предмета, а не от исходного лотка. Поддерживающие `support_offset` и `span_anchor_offsets` — часть логики Definition; мастерская не пересчитывает их молча. Для правок других properties откройте JSON в редакторе текста и загрузите после валидации.

Выбор свидетеля включает runtime rays и показывает visible result count, method, view progress, vote/status. Сектор/переграды/окна считаются ядром. Камера мастерской не влияет на поле зрения свидетеля.

«Шаг trace»/F6 выполняет следующую canonical operation: команду, advance_ticks либо assertion. «Такт+1» и «+10» дают ручную проверку внутри операции; Play/Пауза идёт10Гц только в активных фазах. Правки восстанавливают весь journal canonical+manual operations до выбранного времени. Если новое размещение ломает последующий trace, причина ядра отображается в журнале; данные не превращаются автоматически в другую постановку. «Весь trace» начинает заново и проверяет конечные predicates. Отсутствующий или неуспешный canonical trace явно показывается.

При успешной ActivateLaw сохраняются actual states непосредственно до/после commit. Кнопки «ДО закона»/«ПОСЛЕ» отображают отдельные restored kernels, «Live» возвращает текущую временную линию. Просмотр и перемещение markers в comparison не меняют live kernel напрямую; rebuild сохраняет выбранный comparison при наличии соответствующего commit.

«Проверить» выполняет структурную/ссылочную проверку Definition. «Экспорт JSON» требует явного пути и подтверждения, проверяет данные до записи и после temp/readback. Предыдущий пригодный файл сохраняется как `.bak`; если основной файл уже повреждён, старая пригодная backup остаётся. Ошибочные ссылки не перезаписывают прошлый файл. После экспорта откройте полученный JSON и заново запустите canonical trace. Структурная валидность не гарантирует проходимость/качество новой постановки; status редакторской правки — `layout_seed`.

Для воспроизводимой диагностики доступны developer CLI arguments:

```bash
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --path almost-god/game tools/level_workbench.tscn -- --level=3 --replay-step=8 --mode=result_anchors --witness=w3 --compare=before
```

`--run-canonical` выполняет весь trace. `--capture=/absolute/path.png` сохраняет кадр native viewport и закрывает инструмент; нужен настоящий графический driver/display, этот argument не создаёт поддельный headless screenshot. Снимки `build/workbench-L03-before.png` и `build/workbench-L03-after.png` сделаны под Xvfb/llvmpipe и проверены визуально.

Автоматическая проверка:

```bash
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path almost-god/game --script tests/test_workbench.gd
```

Результат72checks/0failures: все30канонических решений в preview, geometry/Undo/manual ticks/comparison, export/reload/backup/invalid refs, synthetic native input и отсутствие изменений player progress. Отчёт `tests/reports/workbench.json`; это не человеческий тест удобства редактора и не приёмка финального игрового арта.
