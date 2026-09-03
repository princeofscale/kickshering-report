# Logs

[← Назад к индексу](../README.md)

Сюда сохраняются JSON-логи, экспортированные из [`tools/ios-app`](../tools/ios-app/README.md)
и [`tools/scripts`](../tools/scripts/README.md) во время физической проверки по
[Field Testing Guide](../docs/15-field-testing-guide.md).

## Структура

Создавайте подпапку на каждую сессию тестирования: `logs/<YYYY-MM-DD>-<модель>/`, например:

```
logs/
  2026-09-03-max-plus/
    scan_log.json
    pre-rental-gatt.json
    post-rental-gatt.json
    notes.md          # свободный текст: что наблюдали, что показалось интересным
```

Формат файлов описан в [`tools/scripts/evidence_log_schema.md`](../tools/scripts/evidence_log_schema.md).

## Перед коммитом лога — проверьте на приватные данные

- Логи могут содержать серийные номера/идентификаторы устройства. Обычно это не персональные
  данные, но если в advertising/GATT случайно попадёт что-то похожее на чужой account ID или
  телефон — не коммитьте, отредактируйте (замените на `REDACTED`).
- Не включайте скриншоты официального приложения с чужими персональными данными (даже
  случайно попавшими в кадр).
