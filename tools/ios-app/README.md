# BLE Inspector — iOS app (Swift / CoreBluetooth)

[← Назад к tools](../README.md) · [← Назад к индексу](../../README.md)

Небольшое iOS-приложение для **пассивного сканирования** BLE-advertising и **read-only**
enumerate GATT-сервисов/характеристик. Собирается локально через Xcode и запускается на вашем
iPhone. Не публикуется в App Store, не требует платного Apple Developer аккаунта — обычного
(бесплатного) Apple ID достаточно для локальной установки на собственное устройство (с
ограничением: сборка с бесплатным аккаунтом переподписывается каждые 7 дней — для этого
исследования это не проблема, просто периодически пересобирайте через Xcode).

## Что делает приложение (всё офлайн, на самом телефоне)

Три вкладки:

- **Scan** — слушает BLE advertising (имя, RSSI, service UUIDs, manufacturer data), сортирует
  список так, что вероятные Ninebot/Xiaomi устройства (по имени `MISc`/`NBSc` или по рекламе
  Nordic UART Service) поднимаются наверх с бейджем «Ninebot/Xiaomi?». Тап по устройству →
  экран детали.
  - На экране детали: кнопка **Connect & analyze (read-only)** — сперва показывает диалог
    подтверждения авторизации, затем подключается и делает read-only enumerate. Автоматически
    декодирует Device Information (manufacturer / model / **firmware** / hardware / software /
    serial) в текст — это связка «модель → прошивка → BLE-версия», ради которой всё затевалось.
  - Тут же **on-device анализ**: находит Nordic UART Service, перечисляет write-способные
    характеристики (потенциальный команд-канал, уровень E — но приложение в них **не пишет**),
    выдаёт findings с пометкой важности.
  - **Presence-статистика**: сколько раз устройство замечено (Sightings) и диапазон RSSI —
    решающий безопасный тест «а виден ли BLE вообще» (docs/17.1, docs/18 Tuul).
  - **Manufacturer data**: разбирается company ID (напр. Xiaomi 0x038F); payload остаётся hex
    (формат payload — UNCONFIRMED, не додумывается).
  - Кнопка **Save snapshot** с меткой, тегом оператора, **State** (pre-rental / during-rental /
    control-A / control-B) и **Note** (конфаундеры: телефон/OS/версия/заряд/место/время). Вместе
    со снапшотом сохраняются advertising и presence-статистика.
- **Saved** — список захватов (метка · state · сервисы · дата); тап открывает Markdown-отчёт
  (GATT-карта + findings + advertising + presence + note), sharable. «Export all» выгружает всё
  одним JSON.
- **Diff** — выбираете два захвата (например, pre-rental и during-rental) → Markdown-отчёт:
  **структурный** GATT-diff (с явной пометкой «no change observed»), **Advertising**-diff (сервисы
  + manufacturer data — состояние часто здесь, а не в GATT) и **Presence**. Ключевой безопасный
  шаг проверки главной гипотезы (docs/08), **на телефоне, без ноутбука**.

**Никогда не пишет** в характеристики устройства — в коде физически нет вызова
`writeValue(_:for:type:)` (проверяемо: `grep writeValue` находит только комментарии). Это
осознанное ограничение, см. [`../README.md`](../README.md).

## Сборка и запуск (пошагово)

Потребуется **Mac с установленным Xcode** (бесплатно из Mac App Store) — сам iPhone код не
компилирует, но именно на нём приложение будет запускаться после сборки. Если у вас нет Mac,
на первом этапе используйте готовые приложения из App Store как замену (см. раздел ниже
"Альтернатива без Xcode/Mac").

1. Откройте Xcode → **File → New → Project… → iOS → App**.
2. Product Name: `BLEInspector`. Interface: **SwiftUI**. Language: **Swift**.
3. Сохраните проект куда угодно (например, рядом с этим репозиторием, но не обязательно внутри
   git-репозитория).
4. В навигаторе проекта Xcode **удалите** автоматически созданный `ContentView.swift` (оставьте
   `BLEInspectorApp.swift`), затем **добавьте** (drag & drop, или File → Add Files to
   "BLEInspector"…) все `.swift`-файлы из этого каталога:
   - [`BLEInspector/BLEInspectorApp.swift`](BLEInspector/BLEInspectorApp.swift) — заменяет
     сгенерированный Xcode файл (при добавлении разрешите перезаписать/используйте этот вместо
     дефолтного).
   - [`BLEInspector/BLEManager.swift`](BLEInspector/BLEManager.swift) — CoreBluetooth (read-only).
   - [`BLEInspector/Catalog.swift`](BLEInspector/Catalog.swift) — verified UUID/имена (docs/16).
   - [`BLEInspector/GATTAnalyzer.swift`](BLEInspector/GATTAnalyzer.swift) — офлайн-анализаторы.
   - [`BLEInspector/SnapshotStore.swift`](BLEInspector/SnapshotStore.swift) — сохранение захватов.
   - [`BLEInspector/ContentView.swift`](BLEInspector/ContentView.swift) — UI (3 вкладки).
5. Откройте `Info` таб настроек таргета (или `Info.plist`, если ваш шаблон его создаёт) и
   добавьте ключ **Privacy - Bluetooth Always Usage Description**
   (`NSBluetoothAlwaysUsageDescription`) со значением, например: `"Passive BLE research tool —
   scans and reads GATT metadata from user-owned or user-authorized devices only."`
   Без этого ключа iOS не даст приложению использовать Bluetooth.
6. Подключите iPhone к Mac по кабелю (или используйте wireless debugging), выберите его как
   Run Destination в Xcode.
7. В настройках таргета → **Signing & Capabilities** выберите свой Apple ID как Team (Xcode
   предложит создать бесплатный personal team, если его ещё нет).
8. Нажмите ▶ (Run). При первом запуске на iPhone потребуется зайти в
   **Settings → General → VPN & Device Management** и подтвердить доверие вашему
   Developer App сертификату.
9. Приложение запустится. Разрешите доступ к Bluetooth при запросе.

## Альтернатива без Xcode/Mac

Если у вас нет доступа к Mac, для Шага A/B/C из
[Field Testing Guide](../../docs/15-field-testing-guide.md) можно использовать готовые
приложения из App Store с аналогичной read-only функциональностью:
- **LightBlue** (Punch Through) — ручной GATT browser, поддерживает экспорт лога.
- **nRF Connect for Mobile** (Nordic Semiconductor) — доступен и на iOS, аналогичный
  функционал.

Их UI отличается, но задача та же: (1) passive scan → зафиксировать advertising, (2) connect →
enumerate services/characteristics/properties, (3) read (не write!) характеристики со
свойством read, (4) экспортировать/записать результат вручную (скриншот + текстовый лог
допустимы, если приложение не даёт JSON export).

## Файлы

- [`BLEInspector/BLEInspectorApp.swift`](BLEInspector/BLEInspectorApp.swift) — точка входа.
- [`BLEInspector/BLEManager.swift`](BLEInspector/BLEManager.swift) — CoreBluetooth-логика
  (scan, connect, discover, read-only reads, DIS-декод, JSON export). Без write-вызовов.
- [`BLEInspector/Catalog.swift`](BLEInspector/Catalog.swift) — verified Ninebot/Xiaomi UUID'ы
  и каталог стандартных Bluetooth SIG UUID → человекочитаемые имена (docs/16).
- [`BLEInspector/GATTAnalyzer.swift`](BLEInspector/GATTAnalyzer.swift) — офлайн-анализаторы:
  device identity, детект NUS, write-capable список, findings, diff, Markdown-отчёты.
- [`BLEInspector/SnapshotStore.swift`](BLEInspector/SnapshotStore.swift) — сохранение захватов
  на телефон (Documents/JSON) для diff «до/после».
- [`BLEInspector/ContentView.swift`](BLEInspector/ContentView.swift) — UI: вкладки Scan / Saved
  / Diff, экран детали с анализом, отчёты.

Перед запуском на реальном устройстве прочитайте `BLEManager.swift` и убедитесь сами, что там
нет write-вызовов (`grep writeValue` → только комментарии).

Это исследовательский код (research-grade), не продакшен-качества — при сборке в Xcode
возможны мелкие правки (например, доступность SwiftUI API под вашу версию iOS). Основная
CoreBluetooth-логика написана так, чтобы быть проверяемой построчно: перед запуском на
реальном устройстве прочитайте `BLEManager.swift` и убедитесь сами, что там нет write-вызовов.
