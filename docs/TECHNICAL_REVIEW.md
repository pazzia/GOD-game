# Технический отчёт о восстановленном ядре

После сброса среды ядро, валидатор и тесты созданы заново. Владение исходниками передано Архитектору, поэтому этот новый проход — проверка восстановленной реализации её владельцем;37регрессий перенесены из прежнего независимого review. Для окончательной командной приёмки Менеджер/Разработчик могут повторить команды ниже.

Фактический движок:4.7.2.stable.official.ed1daf0bf. Headless-команды:

```bash
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path almost-god/game --script tests/test_campaign.gd
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path almost-god/game --script tests/test_s2_regressions.gd
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path almost-god/game --script tests/test_validation.gd
almost-god/tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path almost-god/game --script tests/test_kernel.gd
```

| Реальный новый запуск | Результат |
|---|---|
| Campaign после восстановления |30уровней+16альтернатив,732checks,0failures |
| S2 negative/boundary regression |37checks,0failures |
| Definition/checkpoint validation |26checks,0failures |
| Core geometry/observation/replay/checkpoint/frozen support/real suspension |31checks,0failures |

Reports находятся в tests/reports. Количество assertions разных suites не является числом уникальных требований: часть регрессий намеренно пересекается. Предыдущие355PASS не использованы как подтверждение новой реализации.

Закрыты прежние defects: collinear/endpoint ray leakage; method reset/exposure при invalid result; exposure через MOVING; immediate revoke confirmed vote вместо5ticks; stale hash; rehearsal лишнийtick; JSON numeric hash; cargo+carrier overload; invalid/negative/missing state fields; duplicate anchors/remote anchors; retrospective M02 proof; invalid law replacement; support aggregate load; real food payload/thermal protection.

Дополнительно восстановлен semantic content digest и проверка phase/readiness в restore. Из authoring исправлено: настоящий coldpack имеет materialSTEEL, исходные active laws дают планирование перед новым показом. Это общие правила, без исключений по level ID.

Отдельно добавлены четыре regression assertions матрицы M01+M02: обычный stone держится на замёрзшей поверхности, лёд не является open-water proof, отмена M01 не топит камень на льду, thaw снимает такую опору. После изменения повторены все четыре suite — результаты таблицы относятся к одному актуальному ядру.

Три новых проверки подвеса L08: после удаления float правильная нить с support_offset[-4,3] держит камень; неверный offset не держит; capacity2 не держит mass3. Существенное authoring-изменение L08 alternative уменьшило campaign suite с733до732assertions. Менеджер независимо повторил текущие732/31/37/26после второго восстановления среды.

## Независимое review сервисов и glue

Архитектор не менял сервисы Разработчика; передавал воспроизведения и принимал исправления повторными запусками. Закрыты6первоначальных дефектов: неподписанный revision мог поднять старую backup; неизвестный locale; отрицательный text_scale; muted Voice вызывал duck; произвольный leaf busMaster обходил category mute; строковый checkpoint вызывал ScriptError. Дополнительно закрыты2transport defects: повтор уже входящей главы создавал новый stream и сбрасывал clock; новый play после background снимал pause.

| Фактический свежий запуск | Проверки / ошибки | Свидетельство |
|---|---:|---|
| test_services.gd |26 /0| buses, slider², independent mute, loops, backup |
| test_service_boundaries.gd |28 /0| schema metadata, actual app glue/background/law commit/reopen, simulated1200с |
| test_save_recovery_edges.gd |11 /0| schema1migration, schema2header/body, float/int header, saturation |
| test_audio_conductor.gd |21 /0|1,2с chapter fade,450мс phase fade, quantization |
| test_audio_transport_edges.gd |13 /0| same-phase/same-clock requests, last choice, max2, pause/mute, direct paused shutdown |

Transport edge fixture устанавливает реальный AudioServer playback коротким80мс интервалом перед pause и позволяет native start requests обработаться ещё80мс, оставаясь paused. Затем shutdown выполняется напрямую без ручного resume. Свежий запуск завершился без retained ObjectDB/resources warnings. Эти короткие интервалы и mock1200с не являются20мин прослушивания или проверкой телефонии/Bluetooth. Статический просмотр presentation/game.gd не нашёл прямой записи gameplay fields из UI: переходы выполняются dispatch/load/restore; capture harness отдельно воспроизводит сохранённые команды.

## Авторский редактор и puppet API

`test_workbench.gd`:72checks/0failures. Покрыты30реальных canonical traces, marker/grid edits, Undo/Redo, absolute/relative geometry, сохранение manual ticks/comparison view, native synthetic drag/keyboard handler, actual StageView/witness diagnostics, error file/path, безопасный export/readback/backup/reload и отсутствие записи player progress. Это автоматические и synthetic input проверки; человеческое UX-тестирование не заявляется.

Два настоящих окна native workbench сняты под Xvfb1600×1000/llvmpipe и визуально проверены: `build/workbench-L03-before.png`, `build/workbench-L03-after.png`. Они показывают anchors, witness rays, tick85и state/laws до/после реального commit. Редактор не заменяет финальное качество underlying арта.

Peer review `presentation/character_puppet.gd` выявил перезапись жеста, запущенного completion subscriber, и принятие nominal_height0/negative. Менеджер исправил оба; независимый test_puppet_edges.gd9/0. Проверены nested joint/target-height/fit/facing, signal chaining и timeline setting. Fixture намеренно повторяет одну целую текстуру для разных metadata parts; это техническая проверка, не приёмка раздельно нарисованной анимации.

После группировки внутренних слоёв в один CanvasItem выполнен actual native `test_puppet_native.gd`:5/0. Pixel assertions под Xvfb/llvmpipe подтверждают, что отрицательный z ноги остаётся над фоном, положительный z головы не перекрывает следующий modal, а трансформы и зеркальное направление сохраняются. Используются явно окрашенные прямоугольники, не художественные assets; кадр `build/puppet-layer-order.png`. Native pixel test и оба кадра редактора повторены после восстановления v5. Дополнительная граница Workbench: импорт `{}` после ошибочного файла теперь сообщает свой путь и missing schema fields, сохраняя текущую сцену;72/0 фактически повторены на восстановленной среде. Полный snapshot source SHA и свежести suite reports находится в `tests/reports/architect-checkpoint.json`.

Текущие SHA-256 принятого ядра: simulation_kernel `38bf86532ae28c6838e7892d678df5397e6176e397c52412f9282ed6b8d67c1d`; content_validator `edab11b408defa8eaf51e84e2fe81ce560846860a176faf2f01ffef0153fa897`. Архитектор не менял эти два файла в batch редактора/сервисного review.

Эти проверки не подтверждают красивую графику, качество музыкального микса, UX на телефоне, установку APK, производительность устройства или внешний тест понимания. Остаточные задачи полного выпуска остаются в REQUIREMENTS_STATUS/PROJECT_STATE у Менеджера; этот отчёт не объявляет S3или релиз завершённым.

## Независимая приёмка интегрированного клиента

Зафиксированы runtime SHA: game.gd `1f501409fff228162988fa988fbc9a78e1e1820757e6ffe537ebc16ad3c77e57`, stage_view.gd `46cdad4b0e7620645f8748d302bf2f5fe1db90a20822e2c0738c689d56e902b2`. Архитектор не менял эти файлы. Художественные metadata ещё принимались отдельным шагом; technical freeze не означает all-art freeze.

| Свежий независимый запуск | Проверки / ошибки | Область |
|---|---:|---|
| test_stage_boundaries.gd |28 /0| exact IDs и clock после reflow; реальные show/proof/stamp;3rigs, entity→asset binding; pause/resume; geometry/metadata; animal/tow/hero; comparison swap |
| test_touch_capability.gd |8 /0|42реальных ScreenTouch/ScreenDrag events; capability OFF/ON; vertical и nested horizontal scroll; no selection on pan; positive touch tap |
| test_complex_ui_journeys.gd |59 /0|290mouse press/release events; L11/L21/L30 от authored tick0 до победы через UI |
| test_audio_shutdown_edges.gd |8 /0| Audio Node остаётся живым после shutdown; active/paused crossfade, repeat close, late callbacks |

Во время Stage reflow реально сохраняются один Stage, все actor/AnimationPlayer instances, текущая stamp position и единственная target connection; первоначальное опасение об остановке AnimationPlayer при reparent не подтвердилось. Background-проверка использует настоящие SceneTree frames и подтверждает неподвижные clocks Stage, всех actor animations, caption, transformation и audio. Resume возвращает точный предшоу hash, reduced motion останавливает позы, а walking/towed связи не переносят героя вместе с самостоятельным животным или буксируемым ящиком. Переключение на уровень без козы не оставляет видимую Caramelka.

Touch эксперимент: DisplayServer не сообщает touchscreen, default emulate_mouse_from_touch=true. С emulate_touch_from_mouse=false та же последовательность native touch drag не прокручивала ScrollContainer; с true прокручивала обе оси. После pan предмет не выбран, после обычного native touch tap выбран. Fixture восстанавливает исходные flags; grep production/project не обнаружил emulation overrides. Это проверка native UI dispatch в тестовой среде, не физического touch driver телефона.

Сквозные UI journeys выполнялись в настоящем окне Xvfb/llvmpipe, RU100%, с8× clock и тестовым unlocked profile. Каждый уровень загружен из исходного JSON, без progressed snapshot: L11 —7команд UI; L21 —11; L30 —30, включая thermal prep/StopResolution и реальный выбор заменыM01третьим законом. Все команды поступили через реальные Button pointer input; прямого kernel.dispatch/restore в suite нет. Author trace используется только как план действий. Навигация offscreen через native ensure_control_visible не считается проверкой touch pan — он проверен отдельно. Журнал принятых команд, конечных predicates и hashes: `tests/reports/complex-ui-journeys.json`; native victory PNGs: `build/complex-ui-L11-success.png`, `build/complex-ui-L21-success.png`, `build/complex-ui-L30-success.png`. L30кадр осмотрен. P0 отсутствующего UI пути не найдено. Четыре одинаковые подписи ширмL30выявлены при audit; Менеджер добавил отдельные authored RU/EN имена до фактического прохождения.

Native v9 capture выявил дополнительный настоящий audio shutdown defect: после очистки player arrays Node обрабатывался ещё150мс graceful-close, и завершавшийся crossfade обращался за пределами массива. Разработчик исправил terminal guard и processing order. Архитектор независимо принял SHA `e84b9fd57b1b73f2b57ef570fe4471821af02893fcb2f95691071572850017eb`: shutdown_edges8/0; transport13/0; service_boundaries28/0; conductor21/0; services26/0. Все реальные запуски завершились без ScriptError или retained-resource warnings. Восемь новых проверок держат Node живым250мс после shutdown, проверяют активный и paused случай, повторное закрытие, поздние phase/theme/music/ambience/voice/event/duck/resume и manual process. Предыдущие fixtures с немедленным free этого интервала не покрывали.

Статический peer review интерполяции: previous/current — только confirmed progress; gaps/phase changes/kernel swaps/route completion сбрасывают blend; ожидание воды не предсказывает движение. Input Stage теперь коммитит tap на release и отменяет по scroll-begin/movement/canceled event. Gameplay source hashes и новая совокупность reports перечислены в `tests/reports/architect-checkpoint.json`. Final APK asset/metadata verification выполняется после all-art freeze и не подменяется запуском editor/source fixtures.

## Финальная граница выбора и проверка APK

Последняя изолированная правка Stage увеличила entity hit areas до минимум144×144логических единиц сцены, выбирает ближайший нарисованный предмет при пересечении областей и сохраняет приоритет допустимого выбранного slot. Принят финальный stage_view.gd SHA-256 `1b49e3eeff1309472f566d2cc3391ff0b76833d042bd64d11eecac1b82af180a`; game.gd, audio и ядро сохранили приведённые выше SHA.

После этой правки Архитектор фактически повторил `test_stage_input_edges.gd`7/0(9native events), `test_touch_capability.gd`8/0(42touch events), `test_ui.gd`31/0(44mouse+40touch events). Новая граница проверяет release вместо press, выбор в расширенной части hit area, canceled release, drag cancellation, приоритет slot и неизменность simulation hash. Полные complex journeys59/0 не повторялись ради этой изолированной правки: они выбирают предметы и slots через реальные клиентские Controls, не используют Stage hit rectangles. Предыдущее свидетельство28/0Stage lifecycle и59/0journeys остаётся привязано к предыдущему Stage SHA; Менеджер отдельно повторил финальный aggregate на общем freeze.

После сообщения Менеджера об all-source/art/data freeze независимо исполнен `python tests/review_final_apk.py --apk build/AlmostGod-debug.apk --source .`: **710проверок,0ошибок**. Скрипт самостоятельно читает Android binary XML и ZIP, повторно вычисляет SHA-256 и runtime manifest, запускает `apksigner verify` отдельно от сборщика. Отчёт: `tests/reports/apk-independent.json`.

| Проверенный артефакт | Результат |
|---|---|
| APK bytes |118677094байта; SHA-256 `4cdd114c9afc50566226d49a7352918019dbee02c12ae9685cf4b929a9232451` |
| Frozen runtime source |1055файлов; digest `cb83d6eae698674b8f25768da86d10853c0a73128c5381af8534b9c88eaac66c`, совпадает с build manifest |
| Android manifest |`com.almostgod.game`, versionCode3/name0.2.0, minSDK24/targetSDK36, portrait, только VIBRATE, backup=false, debug=true |
| Resource availability |51raw byte-equal,498imported resources с разрешёнными targets,7compiled GDSC/remaps;238PNG,222audio |
| Runtime metadata |30levels,9rigs/81referenced parts,3ENV/15referenced layers,81portraits; все metadata byte-equal исходникам |
| Signature |Проверена независимо; certificate SHA-256 `c404360ce379fd5bdf86f68b8c4bb398e7a3c452a1dc3a92a46bc1e820d77893` совпадает с сохранённым debug certificate |
| Native libraries |Только arm64-v8a, оба ELF имеют LOAD alignment16384; сжатые библиотеки+extractNativeLibs=true совместимы с установкой при16KB pages по структуре |

Digest включает исходники, ресурсы, исходные import settings, project.godot и export_presets.cfg; исключает outputs/developer/authoring folders. Godot преобразует packed import/remap files и компилирует scripts. Для них проверены наличие, ссылки и GDSC header; исходный текст не объявляется побайтово извлечённым из bytecode. Связь с исходниками основана на совпадении independently recomputed frozen digest и проверенном staged build guard до/после экспорта. В APK не обнаружены developer/test/authoring directories.

Финальный cast проверен только по identity, без изменения geometry или правил: во всех30packed levels нет повторяющегося world character_id среди героя, Плама, животных и witnesses;15character IDs отображаются в15разных actor IDs,9rig.actor_id совпадают с каталогами, все author overrides применены, все6crowd IDs встречаются. Повтор портрета того же актёра в HUD не считается вторым актёром мира. Этот audit не переоценивает рисунок или полный цикл анимации.

APK принят как проверенная локально подписанная **debug-сборка**. Физическая установка, устройство/FPS/потребление, телефонные audio interruptions, store signing и полноценная релизная/художественная приёмка этим проходом не подтверждены. Production source во время независимой финальной проверки не менялся.
