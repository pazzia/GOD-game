# APK-UX-051: изолированная Android-поставка для тестирования

Подготовлена версия **0.5.1-preview, versionCode 7**. Сборка и публикация
выполняются на GitHub после согласованного freeze; локальная APK-сборка
в этой задаче не запускалась.

## Идентичность установки

Оба workflow явно передают:

```text
--preview-package com.almostgod.game.review.r${GITHUB_RUN_ID}.a${GITHUB_RUN_ATTEMPT}
```

Каждый run и каждый повторный attempt получают отдельный package, поскольку
CI использует временную тестовую подпись. Имя приложения — **«Почти бог · UX тест»**.
Сборка предназначена для установки рядом с прежними `com.almostgod.game`
и `com.almostgod.game.preview`, без их удаления или очистки данных.
Прохождение и настройки нового пакета отдельные, миграция не реализована.
Это **не обновление старой установки и не постоянная подпись**. Старый
private key не восстанавливался, GitHub Secrets не настраивались.

`--preview-package` допускает только положительные числовые run/attempt IDs
под `com.almostgod.game.review.r…` и требует `--new-debug-identity`.
Legacy defaults builder/CLI сохранены; publishing workflows их не используют.
Неверный override отклоняется до доступа к SDK и signing identity.

Builder проверяет package, версию и minSDK **в готовом AndroidManifest**.
Builder и независимый CI gate также проверяют, что все provider authority
токены принадлежат именно новому package. Authority старой preview,
соседнего attempt и смешанные semicolon-списки блокируют публикацию.
Внутренний дубль двух authorities закреплённого экспортера не изменялся:
задача — исключить пересечение с другим установленным приложением.
На стадии подготовки фактического нового manifest ещё не было; результат
последующей CI-проверки приведён ниже.

Provenance записывает точный `android_package`, `installation_mode`, отсутствие
постоянной подписи и переноса данных. Release notes предупреждают о параллельной
установке и не требуют удалить старую игру. Результат — отдельный
`AlmostGod-0.5.1-preview.apk` в GitHub Releases; LFS-копию делает менеджер
после проверки скачанных байтов.

## Подготовка инструментов и наблюдаемость ошибок

Закреплённые версии, lockfiles, URL и SHA-512/SHA-256 не изменены.
Downloader делает не более трёх попыток с паузами 1 и 2 секунды только для
явно временных transport-ошибок, HTTP408/429/5xx и незавершённого чтения.
Отказы доступа, 404, proxy403, неизвестные URLError и несовпадение контрольной
суммы не повторяются. Полный файл проверяется до атомарной замены cache.

Bootstrap пишет отдельный `bootstrap.log`; `pipefail` не позволяет `tee`
скрыть его ошибку. Лог сохраняется always-artifact и доступен диагностическому
workflow. Сразу после checkout исторический verification report удаляется:
ошибка bootstrap не может показать старый PASS как результат текущего run.

## Выполненные проверки

```bash
python3 -m unittest discover -s tests -p test_verification_tools.py -v
python3 -m py_compile tools/build_android.py tools/ci_android.py tools/bootstrap_native.py tests/test_verification_tools.py
git diff --check
```

Результат Python: **25 tests, OK**. Проверены границы namespace, неизменность
legacy-режимов, несовпадение run/attempt, provider authorities, реальные поля
manifest, ранний отказ до signing, безопасный текст установки, bounded retry,
запрет повторов при отказах/hash mismatch, атомарность и прерванное чтение.
YAML трёх workflow разобран; все shell-steps прошли `bash -n`. Моделирование
неуспешного bootstrap дало exit9 в обоих workflow; cleanup исторического
отчёта расположен до bootstrap.

[Машиночитаемые результаты и отпечатки проверенных файлов](android-verification.json).

На стадии подготовки полный прогон Godot и новая CI-сборка не выполнялись.
Установка на эмуляторе/телефоне и обновление установленного legacy package
по-прежнему не испытаны. Проверка Python сама по себе их не подтверждает.

## Первый CI-прогон ux1

[Run40313133435](https://github.com/pazzia/GOD-game/actions/runs/40313133435)
на commit `388b0949968c0bb8acfdd0166df5f28254b5ff9d` завершился ошибкой.
Bootstrap, импорт и все проверки кроме `test_touch_capability.gd` прошли.
В touch-наборе: 14 проверок, 2 ошибки, 30 native touch events. Оба отказа —
последовательная инспекция свидетелей w2 и w3 в L30 при крупном тексте:
имя наблюдателя/текущий обзор не подтвердились после настоящего касания.
Это передано менеджеру для отдельного UI/QA-разбора; причиной не объявлен
ни сбой SDK, ни старая fixture без воспроизведения.

Runtime во время CI-проверки не менялся. Экспорт APK, фактическая проверка
нового package/providers и публикация Release **не запускались** из-за gate.
[Снимок диагностического JSON](android-ci-ux1.json) получен через штатный
диагностический workflow, запущенный менеджером. Приватные ключи не читались.

## Второй CI-прогон ux2

[Run40316007540](https://github.com/pazzia/GOD-game/actions/runs/40316007540)
на commit `f29e4d282c784fb626f26fbf645f82a89fd7ab4a` завершился **SUCCESS**.
Все 33 обязательных набора прошли, ошибок движка и изменения runtime
во время проверки нет. Runtime digest:
`b61f531c136fa30d5e67b8df83f29e2011c49b786bf5d7d7ecdcf5b2d1ee2f15`.

CI проверил подпись, версию 0.5.1-preview/code7, package
`com.almostgod.game.review.r40316007540.a1` и обе provider authority в его
namespace. Сам экспорт и публикация прошли. Небольшие отчёты скачаны отдельно
и сверены с SHA256SUMS; source/digest/package/33-suite set проверены заново.
Полные APK-байты этим агентом не скачивались: SHA-256 и размер пока сверены
между опубликованными CI-отчётами, provenance и SHA256SUMS. Дальнейшая проверка
полного файла и итоговая игровая приёмка остаются за менеджером.

[Страница выпуска](https://github.com/pazzia/GOD-game/releases/tag/android-preview-0.5.1-ux2)
содержит отдельный `AlmostGod-0.5.1-preview.apk`, 163 651 486 байт, SHA-256
`438a3b72a4ca642613da865b5284ee3cb2d96e8d104af457004c82272c26b1cd`.
[Сводка проверки метаданных](android-ci-ux2.json). Физическая установка и
перенос сохранений не испытывались; новая изолированная установка не
объявляется обновлением прежнего package или стабильной подписью.
