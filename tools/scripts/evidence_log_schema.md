# Evidence log schema

[← Назад к scripts](README.md) · [← Назад к tools](../README.md) · [← Назад к индексу](../../README.md)

Общая структура JSON-логов, экспортируемых `tools/ios-app` и `tools/scripts/*.py`, чтобы их
можно было сравнивать между собой и ссылаться на них из `docs/`.

## Passive scan record (advertising)

```json
{
  "timestamp": "2026-09-03T12:00:00Z",
  "address_or_peripheral_id": "AA:BB:CC:DD:EE:FF",
  "name": "MAX_G30_XXXXXX",
  "rssi": -55,
  "service_uuids": ["0000fe95-0000-1000-8000-00805f9b34fb"],
  "manufacturer_data_hex": {"0157": "0102030405"}
}
```

- `address_or_peripheral_id`: MAC-адрес (Python/`bleak` на macOS/Linux) или CoreBluetooth
  `peripheral.identifier` (UUID, на iOS адрес аппаратно скрыт ОС — это нормально, не баг
  инструмента).
- `service_uuids`: список UUID сервисов, заявленных в advertising-пакете (может быть пустым,
  если устройство не рекламирует сервисы напрямую).

## GATT snapshot (после connect + enumerate)

```json
{
  "peripheralID": "AA:BB:CC:DD:EE:FF или CoreBluetooth UUID",
  "name": "MAX_G30_XXXXXX",
  "timestamp": "2026-09-03T12:01:00Z",
  "services": [
    {
      "uuid": "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
      "characteristics": [
        {
          "uuid": "6e400002-b5a3-f393-e0a9-e50e24dcca9e",
          "properties": ["write", "writeWithoutResponse"],
          "isReadable": false,
          "valueHex": null
        },
        {
          "uuid": "6e400003-b5a3-f393-e0a9-e50e24dcca9e",
          "properties": ["notify"],
          "isReadable": false,
          "valueHex": null
        }
      ]
    }
  ]
}
```

- `properties`: точный список GATT-свойств характеристики. Наличие `write` или
  `writeWithoutResponse` **не означает**, что вы должны туда писать — это просто метаданные,
  которые фиксируются для анализа (см. [`docs/10-safe-poc-methodology.md`](../../docs/10-safe-poc-methodology.md),
  уровень E).
- `valueHex`: заполняется только для характеристик с `isReadable: true` (или `"read" in
  properties` в Python-варианте). Для остальных всегда `null` — это ожидаемо, не ошибка.
- `decodedString` (только iOS-экспорт): ASCII/UTF-8 декод значения для известных строковых
  характеристик Device Information Service (manufacturer/model/serial/firmware/hardware/
  software). Именно это поле даёт связку «модель → firmware». В Python-экспорте отсутствует —
  анализатор `analyze_gatt_log.py` его не требует и корректно обрабатывает оба формата.

## Как использовать для Field Testing Guide, Шаг 3 (diff до/после аренды)

1. Сохраните снапшот "до" как `logs/<date>-<model>/pre-rental-gatt.json`.
2. Сохраните снапшот "после" как `logs/<date>-<model>/post-rental-gatt.json`.
3. Сравните: `diff pre-rental-gatt.json post-rental-gatt.json` (или любой JSON-diff
   инструмент). Обратите внимание на:
   - Появились/исчезли ли сервисы или характеристики.
   - Изменились ли `properties` у существующих характеристик.
   - Изменились ли `valueHex` у читаемых характеристик.
4. Занесите результат в [`docs/10-safe-poc-methodology.md`](../../docs/10-safe-poc-methodology.md)
   и [`docs/08-main-hypothesis.md`](../../docs/08-main-hypothesis.md) со ссылкой на конкретные
   файлы в `logs/`.
