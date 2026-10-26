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
Фактический новый manifest пока не получен: эта проверка выполнится после CI.

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

Не выполнялись: полный прогон Godot до freeze, новая CI-сборка, установка на
эмуляторе/телефоне, обновление уже установленного legacy package. Эти результаты
не объявляются пройденными по одной лишь проверке Python.
