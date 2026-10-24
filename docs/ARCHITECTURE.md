# «Почти бог»: архитектура восстановленного проекта

Этот документ относится к фактическому восстановлению после потери scratch-среды. Старые результаты355PASS относятся к утраченным файлам. Новые результаты пишутся заново в `tests/reports/`. Ядром и его тестами владеет Архитектор, UI/services/build — Разработчик, authoring данных — Менеджер.

Движок: **4.7.2.stable.official.ed1daf0bf**, GDScript, Compatibility. Точная версия подтверждена фактическими headless-запусками. Rules version восстановленного ядра: `0.2.0-recovered`; несовместимые старые checkpoints отклоняются.

## Слои и API

`core/simulation_kernel.gd` — RefCounted, единственный писатель LevelState. `core/content_validator.gd` проверяет форму и ссылки до изменения живой сессии. Ядро не использует Node/SceneTree, RigidBody2D, звук, сеть, wall clock или render delta. UI передаёт команды и читает state/events. Анимации интерполируют состояние и не определяют доказательство/доставку.

```gdscript
validate_definition(data: Dictionary) -> Array[String]
load_level(data: Dictionary, seed_value: int = 1) -> bool
dispatch(command: Dictionary) -> Dictionary
advance_ticks(count: int) -> Array
snapshot() -> Dictionary
restore(saved: Dictionary) -> bool
stable_checkpoint() -> Dictionary
state_hash() -> String
evaluate(predicate: String, parameters: Dictionary = {}) -> bool
assert_predicate(text: String) -> bool
visibility_for(witness_id: String, view: Dictionary = {}) -> Dictionary
witness_eye(witness_id: String, view: Dictionary = {}) -> Vector2
```

Dispatch принимает `{type,payload,precondition_hash?}` и возвращает `{accepted,reason_code,state_hash,events}`. Runtime может добавлять command_id/tick/source. Неверные команды атомарно отклоняются. Events имеют уникальный event_id, type, tick, payload. Счётчик event IDs, история Undo и косметические данные не входят в semantic hash.

## LevelState

Сериализуемые поля: версии/schema/content digest/level/seed; phase/tick/phase_tick; active_laws/candidate_law/pending_law; entities; witnesses; proofs; goals; routes; zones; actor_reach; deliveries; occluder_enabled; failure_reason; resolution_had_pending_routes.

Entity state: slot, integer position, removed, orientation, effective, support, closed/open, enabled, intact, heat_ticks, attachment_target, secured/moored. Immutable baseline берётся из `Entity.properties`. Derived properties всегда пересчитываются из baseline и полного law set.

Witness state: slot, view_progress/gap_streak/view_completed по view ID, expose_streak, eligible_vote/exposed/status, visible_results/method_visible, water_seen_from/water_transition. Proof: ready/votes/sealed. Water zone: phase, thermal_charge, neutral_ticks. Route task: route_id/carrier_id/transport_mode/progress/completed/waiting_for.

Hash — SHA-256 recursively sorted canonical JSON состояния; int-подобные JSON numbers нормализуются. Content digest учитывает определение уровня, поэтому одинаковая content_version с другой геометрией не принимает старый checkpoint. Snapshot — глубокая копия. Restore проверяет все новые S2-поля, ссылки, целые счётчики, фазы, множество законов, view maps, route progress и hysteresis; derived properties пересчитываются и сверяются до принятия. При отказе прежний state сохраняется.

## Время, фазы и сохранения

Симуляция10Гц. Планирование не двигает время. Только PERFORMANCE/REHEARSAL/RUN_RESOLUTION обрабатывают ticks. На каждом шаге: scheduled effects → pre-observation → thermal transitions → derived support → witnesses/routes → goals/events. Лимиты: show200, resolution300ticks. Обход сущностей и tasks стабилен по ID. FPS не передаётся в правила.

Без начальных законов и с доступным proof старт PLAN_SHOW. С начальными законами либо без неактивного proof — PLAN_RESOLUTION. SetLawCandidate/BeginPerformance доступны из обеих плановых фаз. Новое шоу не сбрасывает физические позиции, reach, старые доставки и законы.

ProofReady останавливает время. ActivateLaw коммитит набор законов, effective properties и support атомарно в PLAN_RESOLUTION. TRANSFORMATION — ограниченный по времени overlay уже совершённого commit; skip или kill не отменяет закон. При двух слотах третья печать открывает LAW_SELECTION, cancel возвращает точный прежний state, неизвестный replacement ID отклоняется. Максимум2закона, повтор активного закона не даёт дополнительного эффекта.

Undo — до50полных снимков/12МБ, включая votes/goals/laws/positions. Rehearsal полностью возвращает предшоу hash. `stable_checkpoint()` во время активного действия возвращает предшествующий план, после law commit — новый устойчивый план. UI/services сохраняют именно этот checkpoint. Settings читаются раньше первого звука. SaveService обязан temp/flush/verify/backup/atomic replace, сохранять последнюю valid backup и выбирать максимальный valid revision; его реализация принадлежит Разработчику.

## Геометрия и наблюдение

Координаты целые в24×28. Result visible: минимум2из3anchors; method visible: хотя бы1anchor. Проверяются range40, FOV100°, inclusive/collinear opaque intersections. Касание края блокирует. Screen segment v1 абсолютный и включён, когда owner в active_slot, не removed и enabled. Vision и Thermal независимы.

SetWitnessSlot переводит все authored eye positions на delta относительно initial slot, сохраняя look_at. Окна views полуоткрытые `[from,from+duration)`. Все views обязательны. Между ними MOVING_TO_VIEW без наблюдения; exposure streak сбрасывается.

Clear ticks растут только при истинном видимом результате и скрытом методе. Gap2 сохраняет прогресс, gap3 сбрасывает. Видимый метод сразу сбрасывает незавершённый clear progress; **уже подтверждённый голос остаётся пригоден до5подряд exposure ticks**, затем exposed до конца шоу. Только все completed views дают один голос. Инспектор L03 заканчивает на85логическом такте, после двух35tick ракурсов.

M02 требует наблюдаемого **реального phase-change tick**: этот witness видел liquid до thermal step и видит результат/пламя после перехода. «Когда-то видел воду, потом пропустил замерзание и позже увидел лёд» не считается. Первоначальный лёд также не доказывает M02. Вода при новом шоу не сбрасывается искусственно в liquid.

## Материалы, опоры и транспорт

- M01: все игровые STONE становятся buoyant, capacitiesS/M/L=1/3/5. Mass и anchoring сохраняются; TERRAIN исключён. До печати реальная опора должна существовать, быть intact, стоять в своём support_when_slot и совпадать с целью по `source.position + support_offset == target.position`; offset по умолчанию `[0,0]`. Явная support_capacity обязана выдерживать массу цели. Это позволяет поплавок под камнем и удалённый подвес нити L08 без исключений по ID уровня. После печати удаление float закон не отменяет.
- M02: FIRE меняет signed thermal direction на холод. HEATED_OBJECT остаётся тёплым, COLD_PACK холодным. Fake flame — DECOY без emitter; настоящий cold pack — STEEL/COLD_PACK. Источники используют radius и Thermal occlusion, delta суммируется, charge clamp[-30,+30], freeze−20/thaw+10, neutral1к0через каждые5нейтральных ticks.
- M03: effective paper load_capacity/tear_resistance150, масса и flammability неизменны. Baseline paper capacity1. Нужны два разных anchors в точных `span_anchor_offsets`/`span_endpoint_offsets` относительно paper. Remote anchored prop не поддерживает этот span. Контрольный weight50 должен реально находиться на load_slot и иметь контакт. Grounded frame может держать50до печати; негрунтовая frame не обходит capacity нижних floating anchors.

Paper usable capacity ограничивается aggregate floating anchor capacity минус собственная масса paper. L24:2×M3−paper1=5под нагрузку hero2+cargo3. После test50 на земле и удаления grounded frame это корректная конечная нагрузка. M03 не защищает от нормального FIRE:10непрерывных heat ticks повреждают flammable paper.

Замёрзшая вода — твёрдая поверхность: после отмены M01 камень остаётся на льду. Лёд не считается открытой водой для доказательства M01. После оттаивания обычный неподдержанный камень теряет опору. Paper anchors на твёрдом льду не считаются плавающими основаниями.

Carried/wheeled перемещают carrier и груз, в нагрузке обе массы. ANIMAL+locomotionwalk идёт самостоятельно. Towed двигает только груз, carrier остаётся на берегу; нужен существующий доступный канат достаточной длины. Heavy50 размещается hoist с capacity/service_slot_ids, а не руками. L02/L03 используют stoneL5для hero2+cargo2.

AssignRoute только планирует. RunResolution движет по integer edge progress; картинки интерполируют между узлами. Все одновременно использующие support tasks суммируют массу. Одновременно назначить одного carrier двум незавершённым tasks нельзя. При unmet water_phase task WAITING_FOR_CONDITION: актор ждёт на безопасном узле, мир продолжает нагрев/охлаждение. Недостающая опора/перегруз не допускают опасного движения.

После завершения промежуточных routes без всех goals возвращаемся PLAN_RESOLUTION. RunResolution без routes нужен для термоподготовки. StopResolution без незавершённых routes сохраняет текущий мир и возвращает в план. REACH-доступность — текущая область + прямые reachable_zone_ids, не транзитивный closure; route.destination_reach_zone_id меняет область после реального достижения.

## Крепления, ветер, пища

Interact attach/detach/open/close/remove имеет явные проверяемые targets. Два clamp attachments дают secured ширме. Rope mooring держит boat только за grounded/anchored небуйный target; M01stoneanchor перестаёт быть годной донной опорой. Scheduled effects — registered move_if_unsecured/set_occluder_enabled в заданный phase_tick, без выполнения кода из JSON. Rehearsal их откатывает.

Food ownerzone следует entity через thermal_owner_entity_id. Закрытый colocated box с protection_slot_ids блокирует сам thermal delta, а не только damage flag. После cold_damage_below испорченная еда не восстанавливается закрытием короба. Payload реально погружается до AssignRoute; удалённый издалека предмет не телепортируется в crate. `payload_mass_included:true` считает массу состава ровно один раз. L12/L20 перевозят bread,dessert,box, masscrate2+hero2=4, boxmass0. Положение payload движется с crate, closed state сохраняется.

## Цели и L30

Required goals — AND. State goals актуальны в конечном мире, latched доставки сохраняются после дальнейшей смены законов; Undo возвращает временную линию целиком. Доставка фиксируется только после движения по всем nodes. В L30: M01 → первая доставка на сухой настил → M02 → холодный этап → M03/выбор замены → paper finish. Сухой latched груз не исчезает при заменеM01; final paper anchors не должны зависеть от уже утративших плавучесть stone. Альтернатива заменыM02 требует защиты от обычного огня.

## Новые проверки после восстановления

`test_campaign.gd`: все30основных traces +16альтернатив, повторяемость и JSON checkpoint roundtrip,732assertions. `test_s2_regressions.gd`:37целевых отрицательных/граничных проверок прежнего независимого review. `test_validation.gd`:26malformed definition/state cases, включая новые S2-поля. `test_kernel.gd`:31проверка geometry/observation/gaps/Undo/rehearsal/clock adapters/checkpoints/frozen support и реальной подвесной опоры. Все четыре suite заново исполнены после восстановления и независимо повторены Менеджером с0failures.

## Сервисы и авторский инструмент

SaveService schema2 включает schema/revision/body в проверяемую подпись, выбирает максимальный пригодный revision и сохраняет последнюю пригодную backup. Legacy schema1 читается с revision0, поскольку её revision не был подписан. Нормализация whole-number JSON values защищает typed UI. Некорректный checkpoint не стирает завершённые уровни; ядро отдельно проверяет его content digest и derived properties.

AudioService создаёт две Music timelines, каждая через Music bus; три stems каждой главы используют AudioStreamSynchronized. Кроссфейд глав1,2с equal-power; при быстрых запросах хранится последний pending выбор, повторный выбор уже входящей главы отменяет лишнюю очередь без restart. Фазовый mix меняется на следующем музыкальном такте за450мс. Повторные вызовы той же фазы не переносят границу. Gain envelopes меняют громкость players/stems, а пользовательские mute остаются на buses. Explicit pause применяется после каждого нового play. Все это проверено на реальных AudioStreamPlayer nodes с управляемыми часами;20мин прослушивания, физическое устройство, звонки и Bluetooth этим не подтверждаются.

`tools/level_workbench.tscn` — отдельная native developer scene без ссылки из player menu. Production StageView получает отдельное ядро, overlay использует его world transform и visibility. WorkbenchModel редактирует только Definition, хранит полный author undo/redo и journal канонических шагов/ручных ticks, чтобы правка не сбрасывала выбранное время. Before/after law — отдельные restored kernels; comparison не меняет live timeline. Slot position, absolute occluder endpoint и relative evidence offset редактируются раздельно. Explicit JSON export выполняет структурную/ссылочную проверку, temp/readback, сохраняет пригодный .bak и atomically replaces файл. Автор проверяет проходимость отдельным canonical trace; валидная геометрия сама по себе не является доказательством интересного или проходимого уровня. Подробности и команды в `LEVEL_WORKBENCH.md`.

Дополнительные фактические suites: services26/0; independent service boundaries28/0; envelope migration/header edges11/0; conductor21/0; independent transport edges13/0; native workbench72/0. Puppet peer review9/0 подтверждает transforms/state/signal API на явных fixture textures, не художественную приёмку раздельно нарисованных частей. Native кадры редактора получены под Xvfb/llvmpipe и осмотрены отдельно от headless assertions.

## Интегрированное представление

Measured HUD вычисляет высоту текста после shaping, размещает сцену в общей области984×656 и держит primary/footer отдельно от вертикального ScrollContainer. Reflow сохраняет тот же Stage и его AnimationPlayer nodes, captions и callbacks. Stage использует реальные Felix/Plum rigs и `entity:<id>` для каждого CH09_RIG: логический id животного не обязан совпадать с asset idCaramelka. Отсутствующий в новом уровне animal удаляется из набора; actor positions берутся из текущих правил и route progress.

Render interpolation проходит только между двумя уже подтверждёнными simulation ticks. После смены kernel/content, скачка ticks, смены фазы или завершения пути предыдущий sample сбрасывается; WAITING_FOR_CONDITION не создаёт предполагаемого движения. Render alpha не входит в LevelState/hash. Общий Stage PROCESS_MODE_DISABLED при background останавливает всех descendant AnimationPlayers; resume восстанавливает устойчивый checkpoint по прежнему контракту сохранений.

Stage commits tap на release, а не press; movement threshold, canceled release и NOTIFICATION_SCROLL_BEGIN отменяют выбор. Mouse filters позволяют событию дойти до родительского native ScrollContainer. Тестовая touch capability включается только в fixture; production не устанавливает Input emulation flags. Независимый OFF/ON эксперимент с одинаковыми ScreenTouch/ScreenDrag подтвердил native поведение в headless/Desktop среде без touchscreen; это не physical-device test.

Audio shutdown терминален: `_closed=true` и `set_process(false)` выполняются до очистки player arrays. Поздние phase/theme/play/duck/resume вызовы не запускают обработку заново. Этот порядок важен, поскольку game сохраняет Node живым ещё150мс при выходе. Новый независимый keepalive suite проверяет активный crossfade, paused случай, повторное закрытие и поздние callbacks.

Новые peer suites на замороженных runtime исходниках: Stage28/0, touch capability8/0(42touch events), полноценные native UI journeys L11/L21/L30 —59/0(290pointer events), terminal audio8/0. Journey использует authored trace только как план кнопок, начинается с исходного уровня и не вызывает kernel.dispatch/restore для продвижения. UI navigation до offscreen кнопок использует native ensure_control_visible; actual pan проверен отдельным touch suite. Время journey ускорено8×; человеческий UX/телефонная производительность не заявляются.

Headless pass подтверждает реализованную логику, но не качество рисунка/звука, удобство touch, FPS на телефоне, APK установку или внешний тест удовольствия. UI capability gate и фактические платформенные проверки отражаются отдельно в PROJECT_STATE/отчёте Менеджера.

Финальная Stage hit policy: минимум144×144логических единиц для entity, ближайший painted target при перекрытии, допустимый selected-slot имеет приоритет. Выбор по-прежнему завершается на uncanceled release. Независимо повторены affected-input7/0, touch capability8/0 и owner UI31/0; финальный Stage SHA `1b49e3eeff1309472f566d2cc3391ff0b76833d042bd64d11eecac1b82af180a`.

Финальный Android debug export независимо проверен по фактическим ZIP/binary XML/signature bytes:710проверок/0ошибок. APK SHA `4cdd114c9afc50566226d49a7352918019dbee02c12ae9685cf4b929a9232451`, frozen runtime digest `cb83d6eae698674b8f25768da86d10853c0a73128c5381af8534b9c88eaac66c`. Source digest включает import settings и export preset; compiled scripts проверяются через remap/GDSC и guarded staged build, а не сравнением с исходным текстом. Все238PNG/222audio,30levels,9rig metadata/81parts и3ENV metadata/15layers доступны в APK. Packed cast всех30уровней не содержит повторяющихся world actor identities. Полный отчёт — `tests/reports/apk-independent.json`; это структурная и подписьная приёмка debug-артефакта, не запуск на телефоне или store release.
