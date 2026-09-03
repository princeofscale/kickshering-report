# 7. Rental State Machine Analysis

[← Назад к индексу](../README.md)

## 7.1 Модель состояний

```
AVAILABLE → RESERVED → UNLOCKED → ACTIVE_RIDE → PAUSED → ENDED → LOCKED
                ↑___________________________|  (timeout/cancel возврат в AVAILABLE)
```

## 7.2 Кто имеет право менять каждое состояние

Концептуальная модель, типична для индустрии; не подтверждена документацией Whoosh/Urent
конкретно.

| Переход | Инициатор (ожидаемо) | Кто ДОЛЖЕН подтвердить | Риск при broken design |
|---|---|---|---|
| AVAILABLE → RESERVED | Mobile app → Backend | Backend (billing eligibility, geofence) | Резервирование чужого/недоступного устройства без проверки |
| RESERVED → UNLOCKED | Backend → BLE (unlock command к дашборду) | И backend (billing/session valid), И устройство (BLE auth) | **Ключевая точка гипотезы**: если устройство разблокируется по локальной BLE-команде без подтверждения от backend — это authorization bypass |
| UNLOCKED → ACTIVE_RIDE | Физически: педаль/газ | Локально (устройство детектирует движение) | Обычно низкий риск |
| ACTIVE_RIDE → PAUSED | Mobile app → Backend → BLE (soft-lock) | Backend + устройство (иначе physical state ≠ backend state) | Рассинхрон: backend думает "paused" (не тарифицирует полностью), а физически можно ехать |
| PAUSED/ACTIVE_RIDE → ENDED | Mobile app / geofence/timeout → Backend | Backend (billing final) | Race condition при parallel `end-ride` запросах |
| ENDED → LOCKED | Backend → BLE | Устройство должно физически подтвердить lock (иначе "ended" в системе ≠ "locked" физически → следующий пользователь может неожиданно найти "свободный", но не заблокированный самокат) | State desync — устройство может думать, что unlocked, backend — что locked |

## 7.3 Ключевые концептуальные риски

Для проверки методологией §10/§15, не для эксплуатации:

- **Может ли BLE изменить состояние без backend authorization?** — Это и есть центр главной
  гипотезы; см. [§8](08-main-hypothesis.md).
- **Может ли backend изменить состояние без device confirmation?** — Возможно на уровне
  "оптимистичного" UI/биллинга (backend помечает `ENDED`, но устройство физически не
  получило/не подтвердило `LOCK`); риск: следующий "райд" на самом деле продолжение
  предыдущего физического состояния без правильной пере-аутентификации BLE-сессии.
- **Потеря сети** — если телематический модуль офлайн, какая команда выполняется локально по
  умолчанию (fail-open к unlock или fail-safe к lock)? Это критичный design-вопрос для safety,
  но нет данных о поведении конкретно Whoosh/Urent устройств при потере сети.
- **Replay старого состояния** — если BLE-команда `unlock` не содержит nonce/timestamp/
  session-token, привязанный к конкретной backend-сессии, теоретически возможен replay ранее
  перехваченного (на **своём же** устройстве, в лабораторных условиях) пакета. Достоверность
  этого для текущих rental-моделей — POSSIBLE, требует packet capture с реального устройства
  для подтверждения наличия/отсутствия nonce — именно это можно частично проверить через
  [`tools/`](../tools/README.md) (см. [Field Testing Guide](15-field-testing-guide.md)).
