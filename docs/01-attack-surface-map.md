# 1. Attack Surface Map

[← Назад к индексу](../README.md)

```
                     ┌───────────────────────────┐
                     │        Rider phone         │
                     │  (Whoosh / Urent mobile)   │
                     └───────────┬─────────┬──────┘
                        TLS/HTTPS│         │BLE (GATT)
                                 │         │
                 ┌───────────────▼──┐   ┌──▼────────────────────┐
                 │   Backend API /   │   │   Scooter BLE module   │
                 │  rental platform  │   │ (dashboard MCU, напр.  │
                 │ (auth, billing,   │   │  nRF51/nRF52-класс)    │
                 │  state machine)   │   └──┬─────────────────────┘
                 └───────┬───────────┘      │ UART / internal bus
                         │ MQTT/HTTP(S)      │
                         │ (телеметрия,      ▼
                         │  команды)   ┌───────────────┐
                 ┌───────▼─────────┐  │ ESC / motor    │
                 │ IoT/Telematics   │  │ controller     │
                 │ module (GPS,     │  └───────────────┘
                 │ SIM/eSIM, lock   │
                 │ actuator)        │
                 └──────────────────┘
```

Поверхности атаки, ранжированные по интересу (приоритизация задачи):

| # | Поверхность | Ключевой вопрос |
|---|---|---|
| 1 | BLE dashboard ↔ mobile app | Есть ли команды, исполняемые без валидной сессии/пароля? |
| 2 | BLE dashboard ↔ ESC/UART (внутренняя шина) | Можно ли обойти дашборд и говорить с ESC напрямую? |
| 3 | Backend REST/GraphQL API | BOLA/IDOR, broken auth, insecure device binding |
| 4 | Telematics module ↔ Backend (MQTT/HTTP) | Command signing, replay, TLS/cert validation |
| 5 | Mobile app | Hardcoded secrets, insecure storage, BLE-implementation bugs |
| 6 | Firmware trust chain | Secure boot, signature verification, OTA integrity |
| 7 | Rental state machine | Desync между backend state и physical state |

Поверхности 1 и 7 — единственные, для которых в этом репозитории есть готовые
**read-only** инструменты физической проверки (см. [`tools/`](../tools/README.md) и
[Field Testing Guide](15-field-testing-guide.md)). Поверхности 3–6 требуют либо доступа
к backend-эндпоинтам в рамках официальной bug bounty программы, либо статического анализа
мобильного приложения/прошивки — методология описана в соответствующих разделах, но не
покрыта скриптами в этой ревизии.
