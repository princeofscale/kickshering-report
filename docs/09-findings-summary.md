# 9. Confirmed / Probable / Possible / Unconfirmed — сводная таблица находок

[← Назад к индексу](../README.md)

| Находка | Продукт | Статус | Источник |
|---|---|---|---|
| BLE unlock/control без device-side password enforcement | Xiaomi M365, Ninebot ES2/ES4 (2019, до патча) | **CONFIRMED** | CVE-2019-13387 / Zimperium |
| Unauthenticated OTA firmware update, unencrypted BLE | Segway/Ninebot miniPRO (hoverboard, не kick-scooter) | **CONFIRMED**, но другой продукт | IOActive 2017 |
| Malicious Pairing + Session Downgrade атаки | Xiaomi M365/Pro1/Pro2/1S/Essential/Mi3 (2016–2021) | **CONFIRMED** для Xiaomi-ветки | E-Spoofer, WiSec'23 |
| BLE OTA дашборд-прошивки без разборки корпуса, ранние ревизии без RDP/anti-downgrade | Ninebot Max/G30 (консьюмер) | **PROBABLE** (community-подтверждено, не первичный академический источник) | ScooterHacking.org, joeybabcock.me |
| AES-ECB + SHA-1 как криптопримитивы "classic" протокола | Ninebot classic-протокольная линия (ES/Max G30 relatives) | **PROBABLE** | NinebotCrypto (scooterhacking), community RE |
| Транспорт "classic" протокола = Nordic UART Service (RX `…0002` write, TX `…0003` notify), header `55 AA`, cmd read/write `0x01`/`0x03` | Xiaomi/Ninebot консьюмерская линия | **CONFIRMED (по первоисточникам)** — см. [§16](16-ble-protocol-reference.md) | py9b `ble.py`, CamiAlfa `ninebot.h` |
| Broken authorization при создании заказа аренды через backend API | Неустановленный русскоязычный кикшеринг-оператор (не привязано конкретно к Whoosh/Urent) | **CONFIRMED существование класса**, оператор не идентифицирован | Habr, "Как мы кикшеринг взломали", апрель 2022 |
| Локальный BLE-unlock без rental-session на актуальных Whoosh/Urent юнитах | Whoosh (Max G30/Max Plus), Urent (Max Plus) | **UNCONFIRMED** | Данное исследование (гипотеза, не PoC) |
| Официальное заявление "нельзя удалённо подключиться к плате" | МТС Юрент | **Заявление вендора, не независимо верифицировано** | Gazeta.ru, май 2025 |
| Default BLE-ключ `ff…ff` на всём парке → универсальный unlock | Äike (потребительские; НЕ Ninebot) | **CONFIRMED** — [§18](18-aike-tuul-precedent.md) | Moorats/nns.ee, The Register, Hackaday, янв 2026 |
| Прокатные юниты защищены отключённым BLE | Tuul (шеринг, сестра Äike) | **CONFIRMED** — «absence of a feature = security feature» | те же |
| Encryption2 = AES-128 CCM-like (CTR+CBC-MAC) + 3-фазный handshake, ключи per-device | Современный Ninebot (Max Plus 2020–2023 и др.) | **PROBABLE** (вторичные пересказы NootNooot, согласованы) — [§16.4](16-ble-protocol-reference.md#164-криптослой--два-поколения-не-путать-по-стойкости) | NootNooot summaries, ha-ninebot |
| Аккаунт-шаринг между пользователями (policy, не BLE/firmware bug) | Whoosh | **POSSIBLE/анекдотично**, не техническая уязвимость | vc.ru, "Дырявый WHOOSH" |

Каждая строка со статусом UNCONFIRMED — кандидат на то, чтобы стать CONFIRMED или DISPROVEN
после физической проверки через [`tools/`](../tools/README.md); см.
[Field Testing Guide](15-field-testing-guide.md) для протокола сбора доказательств и
[§10](10-safe-poc-methodology.md) для того, как эти доказательства ложатся в таблицу
уровней A–G.
