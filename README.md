# Security Research: BLE / Firmware / IoT Security of Ninebot–Segway Rental Scooters (Whoosh / Urent)

**Классификация:** Legal security research / bug-bounty preparatory analysis
**Статус:** Активное исследование. Часть выводов — desk-based (публичные источники), часть —
предназначена для physical, read-only проверки на собственном оборудовании через
[`tools/`](tools/README.md).

## Что это

Исследование безопасности BLE, прошивки, IoT/телематики, мобильного приложения и backend/API
арендных электросамокатов Ninebot/Segway, используемых операторами Whoosh и Urent (МТС Юрент).
Работа ведётся по принципу **observe → identify → reproduce safely → document → assess
impact**, строго в рамках легального security research: без тестирования чужих арендованных
самокатов, без обхода оплаты, без реальной эксплуатации найденных гипотез на проде.

## Передать исследование другому ИИ

[`RESEARCH-PROMPT.md`](RESEARCH-PROMPT.md) — готовый, самодостаточный промпт для ИИ-ресёрчера:
он кратко описывает состояние проекта, задаёт evidence-first правила и открытые вопросы, и
требует критиковать/улучшать, а не пересказывать. Обновляйте в нём блок «Текущее состояние» по
мере прогресса.

## Структура репозитория

- [`docs/`](docs/00-scope-and-methodology.md) — полный отчёт, разбитый по разделам (не один
  файл — см. оглавление ниже).
- [`tools/`](tools/README.md) — **read-only** инструменты для физической проверки: iOS-
  приложение (Swift/CoreBluetooth, собирается через Xcode и запускается на iPhone) и
  Python-скрипты (`bleak`, для опционального использования с laptop).
- `logs/` — место для сохранения экспортированных JSON-логов с реальных проверок (см.
  [Field Testing Guide](docs/15-field-testing-guide.md)).

## Оглавление отчёта

0. [Scope, Methodology, Disclaimer](docs/00-scope-and-methodology.md)
1. [Attack Surface Map](docs/01-attack-surface-map.md)
2. [Исследованные модели](docs/02-models-researched.md)
3. [BLE Architecture](docs/03-ble-architecture.md)
4. [Firmware Findings](docs/04-firmware-findings.md)
5. [IoT / Telematics & Backend Findings](docs/05-iot-backend-findings.md)
6. [Mobile Application Findings](docs/06-mobile-app-findings.md)
7. [Rental State Machine Analysis](docs/07-rental-state-machine.md)
8. [Главная гипотеза](docs/08-main-hypothesis.md)
9. [Сводная таблица находок](docs/09-findings-summary.md)
10. [Safe Lab PoC — методология](docs/10-safe-poc-methodology.md)
11. [Severity Assessment](docs/11-severity-assessment.md)
12. [Remediation Recommendations](docs/12-remediation.md)
13. [Bug Bounty Report — шаблоны](docs/13-bug-bounty-templates.md)
14. [Источники](docs/14-sources.md)
15. [**Field Testing Guide (iPhone)**](docs/15-field-testing-guide.md) — пошаговый протокол
    физической проверки
16. [**BLE Protocol Reference**](docs/16-ble-protocol-reference.md) — verified UUID'ы, имена,
    пакетный формат (по первоисточникам)
17. [**Полевой чек-лист Whoosh/Urent (iPhone)**](docs/17-whoosh-urent-checklist.md) — что и как
    проверять завтра, только с телефона, read-only
18. [**Прецедент Äike/Tuul**](docs/18-aike-tuul-precedent.md) — default-key unlock и «BLE
    выключен = защита» (подтверждённый отраслевой прецедент)
19. [**Смежные CVE и ландшафт инструментов**](docs/19-adjacent-cves-and-tools.md) — Yadea/Zero
    (2025–26), read-only vs модификация

## Итоговое резюме (один абзац)

Публично задокументирован **реальный исторический прецедент** (CVE-2019-13387, 2019 г.) ровно
того класса уязвимости, который сформулирован в главной гипотезе — BLE-команды, принимаемые
устройством Ninebot ES2/ES4 и Xiaomi M365 без валидации сессии на стороне устройства. Это
доказывает, что архитектурный паттерн **возможен и уже случался** на аппаратно-родственной
линейке продуктов. Однако **прямых доказательств**, что этот же паттерн сохраняется в
**текущих**, **rental-кастомизированных** прошивках, которые реально используют Whoosh
(Ninebot Max G30/Max Plus) и Urent/МТС Юрент (Ninebot Max Plus) сегодня, **не обнаружено**.
Официальное заявление представителя Urent отрицает практическую осуществимость удалённого
BLE-доступа к "мозгам" устройства, но это заявление вендора, не независимый аудит, и оно
частично расходится с задокументированной сообществом возможностью BLE OTA-прошивки
консьюмерских Max/G30-дашбордов без разборки корпуса. **Итог по главной гипотезе: не
подтверждена, но обоснованно достойна дальнейшей safe-lab проверки** — см.
[Field Testing Guide](docs/15-field-testing-guide.md) для того, как проверить это на своём
iPhone без риска для чужих устройств.

## Быстрый старт для физической проверки (iPhone)

1. Прочитайте [`tools/README.md`](tools/README.md) — правила безопасности инструментов.
2. Соберите [`tools/ios-app`](tools/ios-app/README.md) через Xcode на свой iPhone (бесплатный
   Apple ID достаточен для локальной установки).
3. Следуйте [Field Testing Guide](docs/15-field-testing-guide.md) шаг за шагом.
4. Сохраните экспортированные логи в `logs/` и обновите соответствующие разделы `docs/`.
