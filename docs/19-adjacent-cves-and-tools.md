# 19. Смежные CVE (2025–2026) и ландшафт инструментов

[← Назад к индексу](../README.md)

Контекст из внешнего research-вклада, **перепроверенный по первоисточникам** (важно: там были
неточности в классификации — исправлены ниже). Ни одна из этих CVE не относится напрямую к
Ninebot rental, но они уточняют модель угроз и калибруют, что реалистично.

## 19.1 Смежные CVE

| CVE | Устройство | Реальный механизм (verified) | Что research исказил |
|---|---|---|---|
| **CVE-2025-70994** | Yadea T5 e-bike | **RF-брелок EV1527, фиксированный код** (не rolling code). Replay перехваченного сигнала брелока → синтез unlock/start. **Это суб-ГГц RF, НЕ BLE.** Проксимити 30–50 м. CWE-1390. Координировано с CISA (ICSA-26-113-01). | Research подал это как «BLE-перехват LOCK→UNLOCK». Механизм replay-концептуально похож, но **канал — радиобрелок, не Bluetooth**. Для нашей BLE-задачи прямо не применимо. |
| **CVE-2026-1354** | Zero Motorcycles (firmware v44 и ранее) | **Forced BLE pairing**: прошивка не проверяет личность устройства при сопряжении → злоумышленник форсирует pairing → через OTA заливает вредоносную прошивку. Патч анонсирован на май 2026. | В целом описано верно (BLE + OTA). Это ближайший по духу к «BLE-firmware-trust» кейс, но другой класс устройств (мотоцикл). |
| CVE-2019-13387 (для полноты) | Xiaomi M365 / Ninebot ES2/ES4 | device-side не проверял пароль сессии (см. [§3.2](03-ble-architecture.md#32-известный-исторический-класс-уязвимости-confirmed-но-не-для-текущего-whooshurent-флota)) | — |
| IOActive 2017 | Ninebot miniPRO | unencrypted BLE + OTA без auth (см. [§3.2](03-ble-architecture.md)) | — |

**Вывод по CVE:** актуальные bluetooth-атаки на микромобильность существуют (Zero — forced
pairing/OTA), но (а) касаются **firmware-trust / pairing**, а не «локального unlock штатной
командой без сессии»; (б) для самих Ninebot rental **действующих CVE нет**. Yadea — вообще про
RF-брелок, не BLE, и не должен цитироваться как BLE-прецедент.

## 19.2 Ландшафт инструментов (для честной картины — с разделением read-only / модификация)

| Инструмент | Класс | Пригоден для нашей read-only проверки? |
|---|---|---|
| `nRF Connect` / `LightBlue` (iOS) | read-only BLE browser | **Да** — запасной вариант к `tools/ios-app` |
| `tools/` этого репозитория | read-only scan/enumerate/analyze | **Да** — основной |
| `ownbee/ninebot-ble`, NootNooot CLI, `py9b` | R/W BLE-клиенты (нужен валидный ключ/пароль) | Только как справка по протоколу; их write-функции **вне scope** |
| Ninebot IAP (ScooterHacking) | прошивальщик (flash/unlock) | **Нет** — модификация прошивки, высокий риск, не для чужого/арендованного |
| Android «lock/unlock» приложения | отправка команд блокировки | **Нет** — write-команды, вне scope |
| Flipper Zero и подобное | scan/relay | Только пассивный scan; relay/replay против чужого устройства — вне scope |

**Принцип:** существование публичных R/W-инструментов не меняет наши границы. Мы используем
**только** read-only ветку (scan, enumerate, analyze). Любой инструмент, который пишет в
устройство/меняет прошивку, применяется исключительно на **собственном** железе с явного
разрешения — и не является частью полевого протокола [§17](17-whoosh-urent-checklist.md).

## 19.3 Источники

- [CISA ICSA-26-113-01 — Yadea T5](https://www.cisa.gov/news-events/ics-advisories/icsa-26-113-01); [SentinelOne CVE-2025-70994](https://www.sentinelone.com/vulnerability-database/cve-2025-70994/); [PoC/advisory (EV1527 RF)](https://github.com/ktauchathuranga/CVE-2025-70994).
- [Sentinelone CVE-2026-1354 — Zero Motorcycles](https://www.sentinelone.com/vulnerability-database/cve-2026-1354/); [SecurityWeek обзор](https://www.securityweek.com/electric-motorcycles-and-scooters-face-hacking-risks-to-security-and-rider-safety/).
- [djensenius — Segway GT3 Pro BLE Protocol Reference](https://gist.github.com/djensenius/48d6aef55a4ad403775cc5ff5fe92f53) (native Ninebot service UUID, notify `…0004`).
