# Архитектурные решения после восстановления

Среда была потеряна: прежние результаты тестов исторические. Ниже сохранён канон15решений, по которому восстановлены реальные исходники. Rules version `0.2.0-recovered`. Текущее свидетельство — новые `tests/reports/*.json`.

| ADR | Принятое решение и причина |
|---|---|
| 01 | Godot4.7.2.stable.official.ed1daf0bf + GDScript/Compatibility; версия действительно исполняется, templates/export проверяются отдельно. |
| 02 | RefCounted Kernel без SceneTree/physics/audio/network, все изменения через команды и10Гц; UI не определяет успех. |
| 03 | Entity.properties — immutable baseline v1. REACH slot.zone_id не равен WATER polygon; over_water проверяет геометрию. |
| 04 | Все witness views обязательны; zero-based полуоткрытые окна; MOVING не наблюдает.25/35clear ticks, gap2/3, exposure5; confirmed vote не отзывается на1tick. |
| 05 | Witness slot даёт eye delta, gaze остаётся на постановке. Occluder segment абсолютный, inclusive/collinear blocking. |
| 06 | BeginPerformance/BeginRehearsal явные команды, harness advance_ticks — не игроковый чит. Law commit атомарен до косметической TRANSFORMATION; active self-proof запрещён. |
| 07 | L02/L03 stoneLcapacity5: carrier2+cargo2=4. Массу персонажа нельзя игнорировать ради авторской trace. |
| 08 | Semantic hash исключает operational counters/history, canonical keys и int normalization; content_digest защищает от другой геометрии той же версии. |
| 09 | Rehearsal точный sandbox rollback; active action экспортирует pre-action stable checkpoint; law commit новый stable plan. Settings независимы от кампании. |
| 10 | AssignRoute не является доставкой. Только реальное прохождение nodes даёт latched result; общие supports считают суммарную нагрузку tasks. |
| 11 | Static checks, headless logic, desktop preview, audio listening, APK/device и внешний тест — разные свидетельства. PASS одной группы не переносится на другую. |
| 12 | S2 механики задаются registered properties/predicates/effects/requirements, без if level_id и строковых выражений. M02 требует actual visible transition tick, M03 двух реальных spatial anchors и контакта50. |
| 13 | Initial laws начинают PLAN_RESOLUTION; новое шоу оттуда сохраняет мир. Intermediate routes возвращают план. REACH использует прямых соседей и destination zone, что делает L07/L30 достижимыми. |
| 14 | Carried/wheeled учитывают carrier+load; walk animal самостоятельный; towed не перемещает carrier и требует rope; weight50 размещается hoist. |
| 15 | Пища защищается реально закрытым colocated box от thermal delta; moving ownerzone следует payload; included mass считается один раз. Water-phase route умеет WAITING_FOR_CONDITION, StopResolution сохраняет достигнутый мир. |

Третья печать при двух active laws открывает LAW_SELECTION без изменения свойств. Cancel возвращает прежний hash. Invalid replacement ID отвергается атомарно; null означает запрос выбора. Максимум2закона сохраняется при каждом commit.

Для M03 endpoint offsets заданы явно; две ссылки на один anchor и remote anchored object не подходят. Grounded frame может временно нести контрольный груз, floating frame не даёт бесконечную capacity. Для M02 real cold pack теперь materialSTEEL, fakeflame остаётся DECOY без emitter — исключения по номеру уровня не требуются.

Restore усилен после прежних11дефектов: отсутствующие zones/candidate/water ledgers/intact flags, неверные counters/reach/route refs и несогласованная hysteresis больше не принимаются. Derived props пересчитываются и сверяются до commit. SaveService отдельно обязан не затереть valid backup повреждённым primary; owner этого сервиса — Разработчик.

Дополнения после восстановления v2:

- `support_offset` задаёт вектор от источника опоры к поддерживаемому предмету. Проверяются actual source slot, intact/removed, геометрическое совпадение и capacity. L08 имеет два действительно рабочих варианта опоры — поплавок или подвес, скрываемые разными постановками.
- Save envelope schema2 подписывает header+body; schema1 сохраняет читаемость тела, но unsigned revision не определяет приоритет. Числа header канонизируются в int до подписи, само JSON body проверяется в исходной сериализации.
- Пользовательские mute живут на buses. Кроссфейды/duck/stem mix не меняют bus mute. Music navigation ограничена двумя player timelines, повтор текущей incoming главы не перезапускает clock. Pause наследуется каждым play, включая callback в том же frame после background.
- TOOL-01 реализуется отдельной native сценой Godot, а не пунктом обычной игры или вебстраницей. Edit Definition не является gameplay command. Dependent geometry не смещается автоматически; ручные ticks и canonical operations сохраняются в preview journal. Экспорт требует явного выбора файла и подтверждения пути, валидирует данные, сохраняет предыдущий пригодный файл. Canonical replay проверяется отдельно и сообщает конкретный отказ ядра.
- Puppet AnimationPlayer — только косметический API. Возврат к loop выполняется до completion signal, чтобы subscriber мог запустить следующий жест без перезаписи. Nominal height и draw order валидируются до замены существующего rig; это не заменяет review реальной сборки частей художником.
- Measured HUD сохраняет точные Stage/Puppet/AnimationPlayer IDs при reflow. Визуальная интерполяция использует два подтверждённых ticks, не предсказывает будущую безопасную позицию. Animal instance хранится как `entity:<id>`, assetCaramelka отдельно от idgoat.
- Native ScrollContainer получает press/drag через PASS filters. Выбор Stage-target завершается только при коротком uncanceled release; scroll-begin отменяет tap. Touch emulation capability допустима только в тестовой среде без touchscreen, вместе с явным отрицательным контролем и positive tap; это не production adapter.
- Audio shutdown не просто очищает arrays: Node ещё жив во время graceful-close. Terminal flag и остановка processing предшествуют очистке; late callbacks остаются no-op. Проверка с немедленным free недостаточна, поэтому отдельный keepalive test входит в приёмку.
- Полный synthetic UI journey начинается с authored initial state и нажимает реальные Controls. Авторский replay задаёт намерение, но прямые kernel commands/restore не заменяют клиентское прохождение. L30 cancel fixture отдельно остаётся ограниченным;59проверок нового suite подтверждают все три сложных уровня до победы.
- Entity hit area минимум144×144логических единиц; overlap разрешается по близости к painted target, выбранный допустимый slot сохраняет приоритет. Увеличение области не меняет геометрию simulation или release/cancel правила.
- APK приёмка опирается на фактические ZIP/binary XML/signature bytes и frozen runtime digest с import settings/export preset. Преобразованные import metadata и compiled GDSC подтверждаются ссылками и guarded isolated build; их нельзя объявлять исходным текстом. Локальная debug подпись и структурная16KB совместимость отдельно от physical-device/store acceptance.
