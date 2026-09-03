# 16. BLE Protocol Reference (verified constants)

[← Назад к индексу](../README.md)

Конкретные, **проверенные по первоисточникам** значения, которые нужны для практической
read-only проверки ([Field Testing Guide, §15](15-field-testing-guide.md)) и для настройки
инструментов ([`tools/`](../tools/README.md)). Каждая строка помечена источником. Значения без
источника — не включены.

> Все значения здесь — из **открытых reverse-engineering проектов для консьюмерских**
> Xiaomi/Ninebot скутеров. Применимость к **rental-кастомизированным** прошивкам Whoosh/Urent
> — POSSIBLE, но не подтверждена (см. [§2](02-models-researched.md), [§8](08-main-hypothesis.md)).
> Именно это ваши собственные read-only снапшоты (§15) призваны проверить: совпадают ли UUID'ы
> на реальном rental-устройстве с этой таблицей.

## 16.1 GATT — Nordic UART Service (NUS)

"Classic" Xiaomi/Ninebot протокол туннелируется поверх Nordic UART Service — фактически
последовательный поток внутри двух BLE-характеристик.

| Роль | UUID | Свойства (ожидаемо) | Источник |
|---|---|---|---|
| Service (NUS) | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | — | выводится из RX/TX (NUS base) |
| RX — запись **в** скутер (phone → scooter) | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` | `write` / `writeWithoutResponse` | `etransport/py9b` (`py9b/link/ble.py`, `_rx_char_uuid`) |
| TX — нотификации **от** скутера (scooter → phone) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` | `notify` | `etransport/py9b` (`_tx_char_uuid`) |
| CCCD (descriptor для включения notify) | `00002902-0000-1000-8000-00805f9b34fb` | — | `etransport/py9b` (стандартный BLE CCCD) |

**Важно для анализа:** RX-характеристика `...0002` имеет свойство **write** — то есть в
терминах [§10, уровень E](10-safe-poc-methodology.md) это и есть канал, через который
теоретически подаётся любая команда (включая гипотетический unlock). Инструменты в этом
репозитории **фиксируют** наличие этого write-свойства, но **никогда в него не пишут**. Сам
факт, что канал доступен на запись без предварительной сессии, — не уязвимость (это транспорт);
уязвимостью было бы, если устройство **исполняет** привилегированную команду из этого канала
без device-side проверки rental-сессии (историю такого см. CVE-2019-13387, [§3.2](03-ble-architecture.md#32-известный-исторический-класс-уязвимости-confirmed-но-не-для-текущего-whooshurent-флота)).

## 16.2 Advertising — имена устройств (name prefixes)

| Префикс имени | Значение | Источник |
|---|---|---|
| `MISc…` | Mi Scooter (Xiaomi-брендированные M365 и родственники) | `etransport/py9b` (`ble.py` фильтр имён) |
| `NBSc…` | Ninebot Scooter (Ninebot-брендированные, включая Max/ES-семейство) | `etransport/py9b` (`ble.py` фильтр имён) |

Rental-устройства могут иметь **изменённое** advertising-имя (оператор мог перепрошить/
переименовать) — поэтому инструменты не полагаются на префикс жёстко, а лишь подсвечивают
совпадения. Если ваше реальное rental-устройство рекламируется под другим именем, но
выставляет NUS-сервис `6e400001…` — это сильный сигнал того же протокольного семейства.

## 16.3 Пакетный формат ("classic", verified)

Из первоисточника `CamiAlfa/M365-BLE-PROTOCOL/ninebot.h`:

```
55 AA <len> <addr/dir> <cmd> <arg> <payload[0..len-2]> <checksum_lo> <checksum_hi>
│  │   │      │          │     │                          └─ checksum: little-endian,
│  │   │      │          │     │                             (~(sum of bytes from len..payload)) & 0xFFFF
│  │   │      │          │     └─ register/argument (зависит от cmd)
│  │   │      │          └─ команда: 0x01 = read, 0x03 = write
│  │   │      └─ адрес/направление (ESC / BMS / BLE, зависит от прошивки)
│  │   └─ длина полезной нагрузки (payload), max 0x38 (56 байт — лимит BLE-буфера)
│  └─ header byte 1 = 0xAA
└─ header byte 0 = 0x55
```

Значения `55 AA`, `0x01`/`0x03`, `0x38` — verbatim из `ninebot.h` (`NinebotHeader0=0x55`,
`NinebotHeader1=0xAA`, `Ninebotread=0x01`, `Ninebotwrite=0x03`, `NinebotMaxPayload=0x38`).
Точная семантика поля адреса/направления и полный register map — в `M365-BLE-PROTOCOL` и
`etransport/ninebot-docs` wiki; в этот отчёт включены только verified-константы, register map
целиком не воспроизводится (он большой и модель-зависимый).

## 16.4 Криптослой (PROBABLE, не byte-verified в этой сессии)

- `NinebotCrypto` (реконструкция majsi, репозиторий `scooterhacking/NinebotCrypto`): SHA-1 в
  key derivation, AES (в нескольких описаниях — режим **ECB**), CRC для контроля целостности.
- Pairing: обмен 16-байтным случайным блоком → сессионный ключ; используется 14-байтный
  серийный номер устройства.
- Более новый протокол (Max G3+): отдельная реализация через `libnbcrypto.so`, документирована
  NootNooot (Codeberg) — см. [§3.1](03-ble-architecture.md#31-два-поколения-протокола-подтверждено-несколькими-независимыми-re-проектами).

См. также [§12 Remediation](12-remediation.md) — почему ECB+SHA-1 стоит заменить на AEAD+HKDF.

## 16.5 Как это использовано в инструментах

- iOS-приложение и `tools/scripts/ble_passive_scan.py` подсвечивают устройства с именем
  `MISc*`/`NBSc*` и/или рекламирующие NUS-сервис.
- `tools/scripts/analyze_gatt_log.py` сверяет UUID'ы из экспортированного GATT-снапшота с этой
  таблицей и помечает: (a) найден ли NUS, (b) какие характеристики имеют `write` (потенциальный
  command-канал уровня E), (c) отклонения от ожидаемого набора — что и является материалом для
  diff "до/после аренды" ([§15, Шаг 3](15-field-testing-guide.md#шаг-3--уровень-d-diff-до-аренды-vs-во-время-аренды-ключевой-шаг-гипотезы-только-на-своей-собственной-аренде)).

## 16.6 Источники этого раздела

- `etransport/py9b` — `py9b/link/ble.py` (RX/TX/CCCD UUID, name prefixes `MISc`/`NBSc`).
- `CamiAlfa/M365-BLE-PROTOCOL` — `ninebot.h` (header `55 AA`, cmd `0x01`/`0x03`, max payload `0x38`).
- `scooterhacking/NinebotCrypto` — крипто-примитивы (SHA-1/AES/CRC), pairing.
- Полный список — [§14 Источники](14-sources.md).
