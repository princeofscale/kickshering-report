# Python BLE scripts (optional, laptop-based)

[← Назад к tools](../README.md) · [← Назад к индексу](../../README.md)

Кроссплатформенные (macOS/Linux/Windows) Python-скрипты на базе
[`bleak`](https://github.com/hbldh/bleak), дублирующие функциональность
[`tools/ios-app`](../ios-app/README.md) для случаев, когда у вас также есть ноутбук — например,
для автоматизации серии сканирований или для более удобной работы с JSON-логами на большом
экране. **Не обязательны**, если вы работаете только с iPhone — используйте `tools/ios-app`.

Оба скрипта **read-only по конструкции**: ни один не содержит вызова `write_gatt_char`.

## Установка

```bash
python3 -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## `ble_passive_scan.py` — пассивный сканер advertising

Безопасно рядом с любым устройством, включая чужие — только слушает рекламные пакеты, никогда
не подключается.

```bash
python3 ble_passive_scan.py --seconds 60 --out ../../logs/scan_log.json
# опционально отфильтровать по имени:
python3 ble_passive_scan.py --seconds 60 --name-filter "MAX" --out ../../logs/scan_log.json
```

## `ble_gatt_enumerate.py` — read-only GATT enumerate одного устройства

**Только для собственного устройства или собственной активной аренды.** Требует явного флага
`--i-own-this-device` — это намеренная защита от случайного запуска против чужого устройства.

```bash
# Сначала возьмите адрес устройства из вывода ble_passive_scan.py
python3 ble_gatt_enumerate.py AA:BB:CC:DD:EE:FF --i-own-this-device --out ../../logs/gatt_log.json
```

Скрипт подключается, перечисляет все services/characteristics, логирует `properties.` Читает
(и только читает) характеристики со свойством `read`. Ни при каких условиях не пишет в
характеристики — в файле физически нет вызова `write_gatt_char`.

## `analyze_gatt_log.py` — офлайн-анализатор экспортированных логов

Не трогает Bluetooth. Читает JSON-лог (из iOS-приложения или из `ble_*` скриптов) и
формирует Markdown-таблицу: подсвечивает устройства известного Ninebot/Xiaomi семейства,
находит Nordic UART Service и его RX/TX характеристики, перечисляет все write-способные
характеристики (потенциальный команд-канал, уровень E из
[docs/10](../../docs/10-safe-poc-methodology.md)) — **не записывая в них**, и умеет делать
diff двух GATT-снапшотов (до/после аренды).

```bash
# анализ одного снапшота
python3 analyze_gatt_log.py ../../logs/2026-09-03-max-plus/post-rental-gatt.json

# сравнение до/после аренды (ключевой шаг гипотезы, docs/15 шаг 3)
python3 analyze_gatt_log.py pre-rental-gatt.json --diff post-rental-gatt.json \
        --out ../../logs/2026-09-03-max-plus/analysis.md

# consistency-check по iOS "Export all" (несколько захватов, группировка по state):
#   повторы одного состояния должны совпадать (negative control, docs/20.4)
python3 analyze_gatt_log.py ble-snapshots-export.json --consistency
```

Понимает три формата: iOS raw export (`{gattSnapshots}`), python-скрипты (`{services}`) и
iOS «Export all» — массив сохранённых захватов с полями `state`/`label`/`advertising`.

Верифицированные UUID'ы/имена, с которыми сверяется анализатор, вынесены в
[`ninebot_reference.py`](ninebot_reference.py) и задокументированы в
[docs/16 — BLE Protocol Reference](../../docs/16-ble-protocol-reference.md).

## Формат логов

См. [`evidence_log_schema.md`](evidence_log_schema.md) — описание JSON-схемы, которую
использует и iOS-приложение, и эти скрипты, чтобы логи из разных источников можно было
сравнивать (см. [Field Testing Guide, Шаг 3](../../docs/15-field-testing-guide.md#шаг-3--уровень-d-diff-до-аренды-vs-во-время-аренды-ключевой-шаг-гипотезы-только-на-своей-собственной-аренде)).
