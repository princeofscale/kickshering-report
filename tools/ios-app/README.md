# BLE Inspector — iOS app (Swift / CoreBluetooth)

[← Назад к tools](../README.md) · [← Назад к индексу](../../README.md)

Небольшое iOS-приложение для **пассивного сканирования** BLE-advertising и **read-only**
enumerate GATT-сервисов/характеристик. Собирается локально через Xcode и запускается на вашем
iPhone. Не публикуется в App Store, не требует платного Apple Developer аккаунта — обычного
(бесплатного) Apple ID достаточно для локальной установки на собственное устройство (с
ограничением: сборка с бесплатным аккаунтом переподписывается каждые 7 дней — для этого
исследования это не проблема, просто периодически пересобирайте через Xcode).

## Что делает приложение

- **Scan**: слушает BLE advertising пакеты (имя, RSSI, service UUIDs, manufacturer data),
  отображает список обнаруженных устройств в реальном времени.
- **Connect & Enumerate** (по тапу на устройство): подключается, читает список services →
  characteristics → properties. Для характеристик со свойством `read` автоматически выполняет
  чтение и логирует hex-значение.
- **Export Log**: экспортирует накопленный лог (advertising records + последний GATT snapshot)
  в JSON через стандартный iOS share sheet (AirDrop себе на Mac, "Save to Files", отправить в
  заметки и т.д.).
- **Никогда не пишет** в характеристики устройства — в коде физически нет вызова
  `writeValue(_:for:type:)`. Это осознанное ограничение, см. [`../README.md`](../README.md).

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
   "BLEInspector"…) файлы из этого каталога:
   - [`BLEInspector/BLEInspectorApp.swift`](BLEInspector/BLEInspectorApp.swift) — заменяет
     сгенерированный Xcode файл (при добавлении разрешите перезаписать/используйте этот вместо
     дефолтного).
   - [`BLEInspector/BLEManager.swift`](BLEInspector/BLEManager.swift)
   - [`BLEInspector/ContentView.swift`](BLEInspector/ContentView.swift)
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

- [`BLEInspector/BLEInspectorApp.swift`](BLEInspector/BLEInspectorApp.swift) — точка входа
  SwiftUI-приложения.
- [`BLEInspector/BLEManager.swift`](BLEInspector/BLEManager.swift) — вся CoreBluetooth-логика
  (scan, connect, discover services/characteristics, read-only reads, JSON export).
- [`BLEInspector/ContentView.swift`](BLEInspector/ContentView.swift) — UI (список устройств,
  лог, кнопки Scan/Export).

Это исследовательский код (research-grade), не продакшен-качества — при сборке в Xcode
возможны мелкие правки (например, доступность SwiftUI API под вашу версию iOS). Основная
CoreBluetooth-логика написана так, чтобы быть проверяемой построчно: перед запуском на
реальном устройстве прочитайте `BLEManager.swift` и убедитесь сами, что там нет write-вызовов.
