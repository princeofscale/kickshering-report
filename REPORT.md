# Security Research Report: BLE / Firmware / IoT Security of Ninebot–Segway Rental Scooters (Whoosh / Urent Fleets)

**Классификация:** Legal security research / bug-bounty preparatory analysis
**Дата:** 2026-09-03
**Автор:** security research session (desk-based, без физического доступа к прод-устройствам)
**Статус:** Черновой отчёт первого прохода. Требует верификации на собственном тестовом устройстве перед подачей в bug bounty.

---

## 0. Дисклеймер и методологическое ограничение

Это исследование выполнено **полностью в кабинетном (desk-based) режиме**: у меня нет физического самоката, нет образцов прошивки, предоставленных заказчиком, нет packet capture с реального устройства и нет доступа к мобильным приложениям Whoosh/Urent в рамках этой сессии. Поэтому:

- Все пункты ниже промаркированы по шкале **CONFIRMED / PROBABLE / POSSIBLE / UNCONFIRMED / DISPROVEN** строго по фактическому объёму доказательств.
- Раздел "Главная гипотеза" (см. §12) **не подтверждён** для флотов Whoosh/Urent конкретно — см. вывод в §12.4.
- Я не выполнял и не буду описывать шаги, позволяющие разблокировать, остановить или иным образом воздействовать на чужой арендованный самокат в проде. Все "safe PoC" ниже — это лабораторные/эмуляционные/статические методы.
- Everything below is a synthesis of **публично опубликованных** источников (академические статьи, security-advisory, open-source reverse-engineering проекты, СМИ, официальные заявления операторов) плюс протокольный/архитектурный анализ поверх них. Список источников — §14.

---

## 1. Attack Surface Map

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

Поверхности атаки, ранжированные по интересу (см. §11 приоритизации задачи):

| # | Поверхность | Ключевой вопрос |
|---|---|---|
| 1 | BLE dashboard ↔ mobile app | Есть ли команды, исполняемые без валидной сессии/пароля? |
| 2 | BLE dashboard ↔ ESC/UART (внутренняя шина) | Можно ли обойти дашборд и говорить с ESC напрямую? |
| 3 | Backend REST/GraphQL API | BOLA/IDOR, broken auth, insecure device binding |
| 4 | Telematics module ↔ Backend (MQTT/HTTP) | Command signing, replay, TLS/cert validation |
| 5 | Mobile app | Hardcoded secrets, insecure storage, BLE-implementation bugs |
| 6 | Firmware trust chain | Secure boot, signature verification, OTA integrity |
| 7 | Rental state machine | Desync между backend state и physical state |

---

## 2. Исследованные модели

| Модель | Оператор (заявлено публично) | Поколение BLE-протокола | Источник |
|---|---|---|---|
| Ninebot MAX G30 (модиф.) | Whoosh — базовая модель проката | "Classic" Ninebot BLE (SHA-1 keygen + AES-ECB, пара-based key exchange) | Whoosh corporate news, `ha-ninebot` README |
| Ninebot Max Plus (модиф., усиленная рама/подвеска) | Whoosh (обновлённая линейка), МТС Юрент (Москва — с двойной передней подвеской и съёмным аккумулятором по требованию Департамента транспорта Москвы) | Вероятно тот же "classic"-класс протокола, что и G30-семейство (не подтверждено для проприетарной rental-прошивки) | Whoosh corporate news; iXBT; отраслевые статьи об Юрент |
| Ninebot ES2 / ES4 | Историческая параллель (не заявлено как текущий флот Whoosh/Urent) | Pre-2019-patch "classic" протокол, **на момент CVE-2019-13387 — де-факто без device-side auth enforcement** | Zimperium / CVE-2019-13387 |
| Segway/Ninebot miniPRO (hoverboard-класс, не kick-scooter) | Не относится к kick-scooter rental флоту | Проприетарный BLE, unencrypted при передаче | IOActive Advisory 2017 |
| Xiaomi M365 / Pro1 / Pro2 / 1S / Essential / Mi3 | Не Ninebot-брендированные, но тот же ODM-контур (Ninebot производил M365 для Xiaomi) | Legacy + модернизированный протокол вплоть до 2021 | E-Spoofer (WiSec'23) |
| Segway Max G3 и новее | Не заявлено как rental-модель Whoosh/Urent на момент отчёта | Новый AES-encrypted протокол (полностью отличается от classic) | `ha-ninebot`, NootNooot BLE-протокол doc |

**Важная оговорка:** ни в одном публичном источнике я не нашёл официальной технической спецификации rental-кастомизации BLE-стека для Whoosh или Urent (МТС Юрент). Обе компании публично подтверждают партнёрство с Segway-Ninebot и использование модифицированных прошивок (изменение отклика газа, изменение скоростных ограничений по геозонам, кастомная логика подъёма в горку), но **не публикуют**, изменена ли аутентификационная модель BLE относительно консьюмерской версии. Это — центральный пробел, который закрывает главную гипотезу (§12) в статус UNCONFIRMED, а не CONFIRMED/DISPROVEN.

---

## 3. BLE Architecture

### 3.1 Два поколения протокола (подтверждено несколькими независимыми RE-проектами)

1. **Classic Ninebot/Xiaomi protocol** (используется на ES-серии, M365-семействе, MAX G30 и "родственных" моделях):
   - Пакетный формат: `5A A5 <len> <src> <dst> <cmd> <arg> <payload> <checksum>` (UART/BLE UART-характеристика) — задокументировано в `etransport/ninebot-docs`, `CamiAlfa/M365-BLE-PROTOCOL`, `ub4raf/Ninebot-PROTOCOL`.
   - Криптослой (`NinebotCrypto`, реконструкция протокола majsi): key-generation на основе **SHA-1**, шифрование **AES**, при этом community-реализация explicitly отмечает известный **"crypto iterator bug"** и что часть функциональности "currently broken" в реализации библиотеки (это баг конкретной OSS-либы, не обязательно самого устройства, но указывает на хрупкость протокола при реализации третьими сторонами).
   - Pairing-процедура: обмен 16-байтным случайным блоком, который становится новым сессионным ключом связи; используется 14-байтный серийный номер скутера как часть материала для последующих обменов.
   - **AES в режиме ECB** упоминается как использованный примитив в нескольких RE-описаниях — ECB детерминирован (одинаковый plaintext-блок → одинаковый ciphertext-блок), что является известной криптографической слабостью (утечка структуры данных, потенциально упрощает pattern-анализ трафика). Это PROBABLE (согласовано несколькими независимыми источниками), а не напрямую верифицировано мной по байтам протокола.

2. **Newer AES-encrypted protocol** (Max G3 и новее, согласно `ha-ninebot`):
   - Полностью отдельная реализация, задокументирована через реверс `com.ninebot.segway` (React Native + Hermes) и его нативной криптобиблиотеки `libnbcrypto.so` (NootNooot Segway-Ninebot BLE Protocol doc, Codeberg Pages).
   - Нет публичных данных о том, что эта версия имеет тот же класс уязвимостей, что и legacy-протокол; заявленный дизайн ближе к правильному session-key-обмену.

### 3.2 Известный исторический класс уязвимости (CONFIRMED, но НЕ для текущего Whoosh/Urent флота)

**CVE-2019-13387** (Zimperium, февраль 2019, публикация: "Don't Give Me a Brake"):
- Затронутые устройства: **Xiaomi M365, Ninebot ES2, Ninebot ES4** (Segway-Ninebot).
- Корневая причина: **пароль/PIN проверялся только на стороне мобильного приложения**, а не на стороне скутера. Скутер не отслеживал состояние аутентификации сессии ("device doesn't keep track of the authentication state").
- Практический эффект: подключение к BLE GATT без пароля/ID → возможность отправлять команды разгона/торможения/деактивации (anti-theft lock), а также **установка произвольной прошивки без проверки подписи** → DoS / внезапное торможение или ускорение под едущим райдером.
- Это ровно тот класс бага, о котором говорит "главная гипотеза" пользователя — но он документирован для **другого поколения устройств (ES2/ES4, до-патчевая прошивка 2019 года)**, а не для текущих rental-кастомизаций Whoosh (Max G30/Max Plus) или Urent.
- Реакция Segway-Ninebot/Xiaomi: подтверждено, что вендор признал проблему; на практике более новые модели (в т.ч. те, что описывает `NinebotCrypto`/`ha-ninebot` как "classic"-протокол post-fix) используют pairing key exchange, что указывает на частичный fix линии продукта после 2019 года — но нет single authoritative advisory, подтверждающего полное закрытие проблемы на всех SKU.

**IOActive Advisory (июль 2017)** — Segway/Ninebot miniPRO (self-balancing hoverboard, **не kick-scooter**):
- Незашифрованный BLE-трафик между приложением и устройством.
- OTA-обновление контроллера **без аутентификации**, позволяющее модифицировать прошивку и, в частности, отключить rider-detection.
- GPS-координаты райдеров были публично индексируемы через API приложения (отдельный баг класса IDOR/data exposure).
- Значимость для нашего скоупа: демонстрирует **историческую культуру безопасности Segway/Ninebot embedded-стека** (одна и та же компания, тот же период) — полезный контекст для приоритизации гипотез, но **другой продукт**, нельзя переносить as-is на kick-scooter rental флот.

**E-Spoofer / WiSec'23 (Casagrande, Cestaro, Losiouk, Conti, Antonioli)**:
- Первое систематическое исследование security проприетарных BLE-протоколов **именно Xiaomi**-скутеров (M365, Pro1, Pro2, 1S, Essential, Mi3), 2016–2021 гг.
- Два новых класса атак: **Malicious Pairing** и **Session Downgrade** (скрытая downgrade-команда позволяет откатить защищённую сессию к легаси-небезопасному протоколу).
- Прямо **не заявлено**, что Ninebot-брендированные rental-модели были частью тестового набора — работа фокусируется на Xiaomi-ветке экосистемы. Возможность переноса Session Downgrade-паттерна на Ninebot classic-протокол — **POSSIBLE**, но не подтверждена в этой статье и не проверена мной.

### 3.3 Firmware-trust наблюдения по консьюмерской линии (ScooterHacking community)

- Community (ScooterHacking.org) публично документирует, что дашборд-прошивка (nRF51-класс чипа) на Ninebot Max/G30 **дампится без Read-Out Protection**, и что кастомная (community) прошивка "заставляет шифрование выглядеть так, будто его вообще нет", сохраняя при этом всю функциональность дашборда.
- Существует официальный Ninebot IAP tool и сторонний ScooterHacking Utility, использующие BLE-scan → connect → flash workflow для **OTA-обновления BLE- и DRV(motor)-прошивки без разборки корпуса**.
- Более новые официальные BLE/DRV-обновления **добавили защиту от даунгрейда** — сообщество отмечает, что community-сборки firmware намеренно убирают этот флаг ("versions that don't contain any flashing restriction").
- Вывод (PROBABLE): на уровне **потребительского** железа Max/G30 существует реальный, задокументированный, доступный по BLE OTA-механизм обновления прошивки без разборки корпуса, изначально без downgrade-protection и (в ранних ревизиях) без readout-защиты чипа. Это прямо противоречит по духу заявлению технического директора МТС Юрент (см. §5.2) о том, что "нет проводного или беспроводного интерфейса для быстрого подключения к плате скутера" — хотя это заявление могло относиться конкретно к **rental-кастомизированной** прошивке/конфигурации, где данный BLE OTA-путь мог быть отключён или защищён дополнительным ключом. **Это расхождение — самая конкретная зацепка для дальнейшего исследования**, и именно она должна быть предметом безопасной лабораторной проверки (см. §11), а не голословного заявления в любую сторону.

---

## 4. Firmware Findings (обобщение по консьюмерской линии; rental-специфика — UNCONFIRMED)

Так как реальные образцы прошивки rental-юнитов Whoosh/Urent не были предоставлены и не были получены в рамках этого исследования, раздел ограничен тем, что задокументировано публично для консьюмерской линии Ninebot, плюс методология, которую нужно применить, если/когда появится доступ к образцу.

Известные по открытым источникам паттерны (относятся к консьюмерским прошивкам Ninebot ES/Max семейства, POSSIBLE-применимость к rental-вариантам):

- **Отсутствие read-out protection** на некоторых ревизиях nRF51 дашборд-чипа (позволяет полный дамп прошивки локально, физическим доступом).
- **BLE OTA без подписи в ранних ревизиях** — community успешно перепрошивала дашборд/DRV без предъявления производителем cryptographic signature check (иначе кастомные "unlock 30 km/h" прошивки не работали бы).
- Позднее добавлена **anti-downgrade защита** на официальном уровне — то есть вендор реагировал на community activity, что указывает на итеративное, а не изначально secure-by-design, укрепление.

Методология, которую следует применить к реальному образцу (если появится доступ на лабораторном устройстве, приобретённом легально, не украденном и не арендованном чужом):

1. `binwalk`/`strings`/entropy-анализ образа на предмет embedded credentials, hardcoded AES/BLE ключей, debug UART/JTAG pinout hints, magic-байтов известных бутлоадеров.
2. Сравнение hash/diff между официальной консьюмерской прошивкой (публично доступной через Ninebot IAP/ScooterHacking mirror) и rental-прошивкой (если когда-либо будет физически получена законно, например, со списанного/переданного оператором в утиль устройства с письменного разрешения) — именно diff покажет, действительно ли rental-firmware меняет auth-модель.
3. Проверка наличия debug/test flags (`#ifdef DEBUG`, тестовые UART-команды, оставленные for-manufacturing коды) через strings + cross-reference с известными Ninebot command tables (`ub4raf/Ninebot-PROTOCOL`).
4. Проверка bootloader на предмет secure boot / signature verification (наличие RSA/ECDSA constants, verify-функций в дизассемблированном коде).

**Статус:** UNCONFIRMED для rental-специфики. Ничего из вышеперечисленного не было независимо верифицировано мной на реальном бинарнике в рамках этой сессии — это карта методологии, а не результат анализа.

---

## 5. IoT / Telematics & Backend Findings

### 5.1 Архитектура телематики (по вендорской документации Segway commercial line)

- Публично задокументированы поколения IoT-модулей Segway для шеринга: **Segway Scooter IoT 2nd Gen**, **3rd Gen**, и модель **ZK601LE** — это модули с GPS/GSM/BLE, интегрируемые сторонними телематическими платформами (пример: сторонний парсер telemetry-протокола существует в открытом доступе как коммерческий продукт telematics-агрегатора).
- Более новая линейка **Segway Kickscooter T60 / T60 Lite** ("Bot Series") явно позиционируется как **cloud-driven**: устройство способно полуавтономно доехать до точки зарядки/парковки под управлением Segway cloud platform — то есть архитектурно команда "поехать" может исходить от backend без прямого физического участия человека, что расширяет поверхность атаки на backend→device command channel, но это отдельная, более новая продуктовая линия, не подтверждено как используемая Whoosh/Urent сегодня.

### 5.2 Официальные публичные заявления операторов (нужно трактовать как заявления, не как независимо верифицированные факты)

- **МТС Юрент**, технический директор Андрей Калинин, май 2025 (Gazeta.ru): по его словам, **невозможно** взломать стоящий на улице самокат со смартфона/компьютера, так как **нет доступного проводного или беспроводного интерфейса для быстрого подключения к "мозгам"/материнской плате самоката**; для попытки взлома потребовалась бы разборка устройства, прямая распайка программатора на контроллер и заливка прошивки в отдельные модули — что требует профильного специалиста высокой квалификации. В этой же статье упоминаются реальные вектора мошенничества: злоупотребление промокодами, атаки на серверы компании, кража самокатов для перепрошивки под другие цели (продажа/личное использование).
- Это заявление **противоречит по духу** публично задокументированной возможности BLE-OTA прошивки консьюмерских Ninebot Max/G30 дашбордов без разборки (см. §3.3). Возможные объяснения расхождения (все — POSSIBLE, не подтверждены):
  a) Rental-прошивка отключает или защищает дополнительным паролем/ключом стандартный Ninebot IAP BLE OTA-путь;
  b) Заявление технического директора относится к атаке "снять контроль над едущим самокатом здесь и сейчас" (то есть про real-time unlock/control), а не про офлайн-перепрошивку неарендованного простаивающего устройства — это разные модели угроз, которые в публичном заявлении не разделены явно;
  c) Заявление — маркетинговое упрощение, не строго техническое.
- **Whoosh** — публичные материалы фокусируются на партнёрстве с Segway-Ninebot и улучшениях железа/UX (усиленная рама, герметичность мотор-колеса, "мягкий" отклик газа в новой прошивке), без заявлений о security-модели BLE.

### 5.3 Пример реального класса backend-уязвимости в индустрии кикшеринга (CONFIRMED существование класса, но не привязано конкретно к Whoosh/Urent)

- Публикация на Habr, апрель 2022, **"Как мы кикшеринг взломали"**: исследователь (white-hat) обнаружил, что API-эндпоинт вида `.../gatewayclient/api/v1/order/make`, используемый для инициации аренды, был уязвим (детали конкретного класса — authorization/state-validation issue при создании заказа); ответственно раскрыл сервису, получил благодарность и bug bounty от директора сервиса. **Название конкретного оператора в найденных мной сниппетах не установлено однозначно** — поэтому я не приписываю это ни Whoosh, ни Urent без дополнительной верификации первоисточника. Значимость: подтверждает, что **класс уязвимости "broken authorization при создании/изменении состояния аренды через backend API" реально встречался в русскоязычном кикшеринг-рынке** и вознаграждался операторами через bug bounty — то есть это разумный, дружелюбный к ответственному раскрытию, канал для further legitimate research.
- vc.ru, автор Alexey Hazoke, **"Дырявый WHOOSH..."** — это авторская критическая заметка, судя по заголовку и сниппетам, про способы бесплатного катания (вероятно, злоупотребление промокодами/тарифами, а не техническая уязвимость аутентификации устройства). Уровень доказательности: **POSSIBLE/UNCONFIRMED**, это не техническое дисклоужер-исследование, а личный пост — не должен рассматриваться как security advisory без независимой верификации.

### 5.4 Концептуальные проверки (что нужно тестировать в разрешённом scope, если появится программа bug bounty)

Для backend/API поверхности (§5 в задании пользователя) — стандартный чек-лист, который стоит прогнать **только на собственном тестовом аккаунте/устройстве и только если у оператора есть публичная bug bounty программа или явное письменное разрешение**:

- BOLA/IDOR: попытка обратиться к `order_id`/`scooter_id`/`session_id` другого (тестового, вашего же второго) аккаунта — меняется ли ответ backend в зависимости от корректности ownership-проверки.
- Race condition при параллельных запросах `unlock`/`end-ride` — может ли гонка привести к двойному списанию, "бесплатной" минуте, или к рассинхрону state.
- Проверка device binding: можно ли инициировать сессию на `scooter_id`, который физически не в радиусе действия/не отсканирован (если QR/NFC/BLE-proximity не валидируется server-side).
- Replay: можно ли повторно отправить ранее перехваченный (для собственного тестового аккаунта, через свой же proxy) valid `unlock`-запрос после `end-ride`.
- TLS/cert pinning: смотреть, установлен ли certificate pinning в мобильном приложении (если нет — MITM на своём же трафике становится тривиальным, что облегчает весь остальной анализ, но само по себе некритичная находка без демонстрации downstream impact).

**Статус всего §5.4:** это чек-лист метода, а не результат — ничего из этого не выполнено против реальных Whoosh/Urent endpoint'ов в рамках этой сессии (нет подтверждённого scope/разрешения, нет тестовых аккаунтов, нет сетевого доступа к их API из этой среды).

---

## 6. Mobile Application Findings

Официальные приложения Whoosh и Urent не были получены/статически проанализированы в рамках этой сессии (APK/IPA не предоставлены, нет доступа к Google Play/App Store бинарникам из данной среды выполнения). Поэтому по этому пункту у меня **нет прямых находок** — только методология для последующего анализа в разрешённой среде:

1. `apktool`/`jadx` на APK → поиск hardcoded API keys, BLE service/characteristic UUID constants, hardcoded backend hostnames/staging-URLs, отладочных build-флагов (`BuildConfig.DEBUG`, oставленные test-эндпоинты).
2. Проверка реализации BLE-стека приложения: где именно (клиент или сервер) хранится и проверяется session/pairing state — по аналогии с корневой причиной CVE-2019-13387 ("password validated only app-side").
3. Проверка local storage (SharedPreferences/Keychain) на предмет незашифрованного хранения токенов сессии/BLE pairing keys.
4. Проверка certificate validation / pinning implementation (обход через Frida на **собственном** тестовом устройстве/аккаунте — не на чужом).

**Статус:** UNCONFIRMED / нет данных. Секция vc.ru ("Дырявый WHOOSH") намекает на пользовательские жалобы о шаринге аккаунтов между друзьями (не техническая уязвимость авторизации, а поведенческая/policy проблема — не в скоупе технического security review).

---

## 7. Rental State Machine Analysis

### 7.1 Модель состояний

```
AVAILABLE → RESERVED → UNLOCKED → ACTIVE_RIDE → PAUSED → ENDED → LOCKED
                ↑___________________________|  (timeout/cancel возврат в AVAILABLE)
```

### 7.2 Кто имеет право менять каждое состояние (концептуальная модель, типична для индустрии; не подтверждена документацией Whoosh/Urent конкретно)

| Переход | Инициатор (ожидаемо) | Кто ДОЛЖЕН подтвердить | Риск при broken design |
|---|---|---|---|
| AVAILABLE → RESERVED | Mobile app → Backend | Backend (billing eligibility, geofence) | Резервирование чужого/недоступного устройства без проверки |
| RESERVED → UNLOCKED | Backend → BLE (unlock command к дашборду) | И backend (billing/session valid), И устройство (BLE auth) | **Ключевая точка гипотезы**: если устройство разблокируется по локальной BLE-команде без подтверждения от backend — это authorization bypass |
| UNLOCKED → ACTIVE_RIDE | Физически: педаль/газ | Локально (устройство детектирует движение) | Обычно низкий риск |
| ACTIVE_RIDE → PAUSED | Mobile app → Backend → BLE (soft-lock) | Backend + устройство (иначе physical state ≠ backend state) | Рассинхрон: backend думает "paused" (не тарифицирует полностью), а физически можно ехать |
| PAUSED/ACTIVE_RIDE → ENDED | Mobile app / geofence/timeout → Backend | Backend (billing final) | Race condition при parallel `end-ride` запросах |
| ENDED → LOCKED | Backend → BLE | Устройство должно физически подтвердить lock (иначе "ended" в системе ≠ "locked" физически → следующий пользователь может неожиданно найти "свободный", но не заблокированный самокат) | State desync — устройство может думать, что unlocked, backend — что locked |

### 7.3 Ключевые концептуальные риски (для проверки методологией §11, не для эксплуатации)

- **Может ли BLE изменить состояние без backend authorization?** — Это и есть центр главной гипотезы; см. §12.
- **Может ли backend изменить состояние без device confirmation?** — Возможно на уровне "оптимистичного" UI/биллинга (backend помечает `ENDED`, но устройство физически не получило/не подтвердило `LOCK`); риск: следующий "райд" на самом деле продолжение предыдущего физического состояния без правильной пере-аутентификации BLE-сессии.
- **Потеря сети** — если телематический модуль офлайн, какая команда выполняется локально по умолчанию (fail-open к unlock или fail-safe к lock)? Это критичный design-вопрос для safety, но у меня нет данных о поведении конкретно Whoosh/Urent устройств при потере сети.
- **Replay старого состояния** — если BLE-команда `unlock` не содержит nonce/timestamp/session-token, привязанный к конкретной backend-сессии, теоретически возможен replay ранее перехваченного (на **своём же** устройстве, в лабораторных условиях) пакета. Достоверность этого для текущих rental-моделей — POSSIBLE, требует packet capture с реального устройства для подтверждения наличия/отсутствия nonce.

---

## 8. Главная гипотеза (§12 задания)

**Формулировка:** "Старый rental Ninebot может принимать локальные BLE-команды, не требуя действующей rental session или корректной server-side authorization."

### 8.1 Что установлено

| Уровень доказательности | Утверждение |
|---|---|
| CONFIRMED (историческое, другое поколение устройств) | На Ninebot ES2/ES4 и Xiaomi M365 (прошивка до патча 2019 г.) BLE-команды принимались устройством **без валидации пароля на стороне устройства** — CVE-2019-13387, Zimperium. |
| PROBABLE | Community independently подтверждает существование BLE OTA firmware-flashing пути на консьюмерских Max/G30 дашбордах без разборки корпуса, изначально без anti-downgrade защиты. |
| POSSIBLE | Тот же класс архитектурной слабости (auth enforcement на app-стороне, а не device-стороне) мог унаследоваться в "classic"-протокольную линию, используемую в том числе Max G30/Max Plus — но это не подтверждено для актуальных прошивок. |
| UNCONFIRMED | Применимо ли что-либо из вышеперечисленного к **rental-кастомизированным** прошивкам, реально развёрнутым Whoosh/Urent сегодня (2026 г., 7 лет после патча 2019 года и с учётом собственных модификаций прошивки операторами). |
| UNCONFIRMED (заявление, не факт) | Публичное заявление МТС Юрент (техдиректор, май 2025) о невозможности удалённого BLE-доступа к "мозгам" устройства — правдоподобно, но не является независимо верифицированным техническим аудитом, и по формулировке частично избегает вопроса именно про BLE unlock (акцент сделан на "перепрошивке", а не на "принятии unlock-команды в рамках штатного протокола"). |
| DISPROVEN | Ничего в собранных источниках не опровергает саму возможность существования такой уязвимости в принципе — то есть гипотеза не "снята со стола", но и не доказана применительно к целевым флотам. |

### 8.2 Authorization boundary — где реально принимается решение (концептуально)

В штатной архитектуре ожидается разделение на два независимых, но должных быть **синхронизированных**, домена доверия:
1. **BLE authorization domain** — устройство проверяет, что запрашивающий client прошёл pairing/challenge-response и владеет валидным session key.
2. **Rental authorization domain** — backend проверяет, что у аккаунта есть активная/только что созданная сессия аренды именно на этот `scooter_id`, оплата подтверждена, гео/парковочные условия соблюдены.

Уязвимость данного класса возникает именно тогда, когда **BLE authorization domain самодостаточен** (может выдать `unlock` только на основании локального BLE challenge-response, не спрашивая backend "а есть ли у этого райдера действующая сессия") — то есть когда устройство доверяет любому, кто прошёл BLE-pairing, вне зависимости от того, платил ли этот клиент за поездку. Это ровно то, что было верно для CVE-2019-13387 (только пароль на app-уровне) — там разрыв был ещё глубже, потому что pairing вообще не требовался.

### 8.3 Можно ли доказать это без разблокировки production-самоката?

Да, минимально-инвазивный путь доказательства (без нарушения условий задачи) состоит из:
1. Легально приобретённого/арендованного **на постоянной основе с разрешения владельца** экземпляра той же аппаратной платформы (например, консьюмерский Max/G30, физически идентичный тому, что использует Whoosh) — на нём безопасно повторить методологию из §3.3/§4.
2. Packet capture (например, через `nRF Sniffer for Bluetooth LE` или Wireshark+HCI snoop) BLE-обмена между **собственным** телефоном/приложением и **собственным** устройством во время штатной аренды/владения — анализ наличия nonce/challenge-response/session-token в `unlock`-пакете.
3. Diff между поведением устройства "до создания rental-сессии в приложении" (просто physically nearby) и "после" — то есть, реагирует ли BLE GATT-характеристика на `unlock`-подобный write вообще без предварительного backend round-trip.
4. Если утверждение операторов о "недоступном интерфейсе" верно — этот шаг сам по себе это либо подтвердит (устройство отказывает без сессии), либо опровергнет (устройство принимает write) — **не создавая бесплатную поездку и не покидая лабораторные условия**, потому что тестируется на собственном оборудовании владельца эксперимента.

### 8.4 Вывод

**Уязвимость не подтверждена** для актуальных Whoosh/Urent флотов. Существует обоснованная, evidence-based гипотеза (по историческому прецеденту CVE-2019-13387 и по архитектурным паттернам "classic" Ninebot BLE-протокола), заслуживающая дальнейшей safe-lab проверки по методике §8.3, но на сегодняшний день у меня нет ни одного независимого технического источника (packet capture, дизассемблированной rental-прошивки, или подтверждённого CVE), который бы напрямую демонстрировал этот баг на текущем, реально эксплуатируемом Whoosh- или Urent-флоте.

---

## 9. Confirmed / Probable / Possible / Unconfirmed — сводная таблица находок

| Находка | Продукт | Статус | Источник |
|---|---|---|---|
| BLE unlock/control без device-side password enforcement | Xiaomi M365, Ninebot ES2/ES4 (2019, до патча) | **CONFIRMED** | CVE-2019-13387 / Zimperium |
| Unauthenticated OTA firmware update, unencrypted BLE | Segway/Ninebot miniPRO (hoverboard, не kick-scooter) | **CONFIRMED**, но другой продукт | IOActive 2017 |
| Malicious Pairing + Session Downgrade атаки | Xiaomi M365/Pro1/Pro2/1S/Essential/Mi3 (2016–2021) | **CONFIRMED** для Xiaomi-ветки | E-Spoofer, WiSec'23 |
| BLE OTA дашборд-прошивки без разборки корпуса, ранние ревизии без RDP/anti-downgrade | Ninebot Max/G30 (консьюмер) | **PROBABLE** (community-подтверждено, не первичный академический источник) | ScooterHacking.org, joeybabcock.me |
| AES-ECB + SHA-1 как криптопримитивы "classic" протокола | Ninebot classic-протокольная линия (ES/Max G30 relatives) | **PROBABLE** | NinebotCrypto (scooterhacking), community RE |
| Broken authorization при создании заказа аренды через backend API | Неустановленный русскоязычный кикшеринг-оператор (не привязано конкретно к Whoosh/Urent) | **CONFIRMED существование класса**, оператор не идентифицирован | Habr, "Как мы кикшеринг взломали", апрель 2022 |
| Локальный BLE-unlock без rental-session на актуальных Whoosh/Urent юнитах | Whoosh (Max G30/Max Plus), Urent (Max Plus) | **UNCONFIRMED** | Данное исследование (гипотеза, не PoC) |
| Официальное заявление "нельзя удалённо подключиться к плате" | МТС Юрент | **Заявление вендора, не независимо верифицировано** | Gazeta.ru, май 2025 |
| Аккаунт-шаринг между пользователями (policy, не BLE/firmware bug) | Whoosh | **POSSIBLE/анекдотично**, не техническая уязвимость | vc.ru, "Дырявый WHOOSH" |

---

## 10. Safe Lab PoC — методология (без production impact)

Для КАЖДОЙ гипотезы применяется уровневая модель A–G из задания. Ниже — шаблон, заполненный для главной BLE-гипотезы как пример методологии (не как результат):

| Уровень | Что проверяется | Подтверждено? | Артефакт | Воспроизводимость | Минимальный безопасный тест | Impact | CVSS-подобная оценка | Remediation |
|---|---|---|---|---|---|---|---|---|
| A. Наблюдаемость | BLE advertising виден для устройства | Да, тривиально ожидаемо (BLE-устройства рекламируют себя для обнаружения приложением) | — | Высокая | Пассивный BLE scan (`nRF Connect`) рядом со своим устройством | Низкий сам по себе | n/a | Randomized/rotating BLE MAC (уже стандарт для многих BLE-стеков) |
| B. Подключение | Возможность установить GATT-соединение без предварительной сессии в приложении | UNCONFIRMED для целевых моделей | — | — | На своём устройстве: попытка connect до открытия приложения | Низкий | n/a | Rate-limiting/whitelist подключений вне активной сессии |
| C. Аутентификация | Требуется ли pairing/PIN/challenge-response при подключении | PROBABLE, что да, для "classic"-протокола после 2019 (pairing key exchange описан в NinebotCrypto) | Community RE docs | Средняя | Packet capture своего pairing-обмена | — | — | Усилить крипто-примитивы (заменить ECB/SHA-1 актуальными AEAD-схемами) |
| D. Авторизация | Проверяет ли устройство ПОСЛЕ pairing, что есть активная rental-сессия именно у этого клиента | **UNCONFIRMED** — ключевой открытый вопрос | — | — | Diff поведения "authenticated BLE, но нет активной аренды" vs "authenticated BLE + активная аренда" на своём устройстве | Потенциально Высокий, если подтвердится | n/a до подтверждения | Server-side session token, проверяемый устройством как часть unlock-команды (не только pairing key) |
| E. Доступ к чувствительной функции | Доступна ли `unlock`-характеристика на запись при уровне D = fail | Не проверено | — | — | (см. D) | — | — | — |
| F. Воздействие на устройство | Реальная физическая разблокировка без оплаты | **Намеренно не тестировалось** — вне этического/legal скоупа без письменного разрешения на конкретном устройстве | — | — | Не выполняется на чужом/арендованном устройстве | Высокий, если F достижим на проде | — | — |
| G. Воздействие на fleet/backend | Массовое применение / автоматизация против чужих устройств | **Вне скоупа категорически**, не исследуется и не будет | — | — | Никогда без explicit fleet-wide bug bounty scope | Критический потенциально | — | Anomaly detection на backend (множественные unlock без billing-события) |

---

## 11. Severity Assessment

### 11.1 Исторический баг (для контекста, уже CONFIRMED и, предположительно, давно пропатчен для затронутых моделей)

- **CVE-2019-13387** — CVSS v3.1 (иллюстративно, по типу воздействия): AV:A (Adjacent — BLE-радиус)/AC:L/PR:N/UI:N/S:C/C:L/I:H/A:H ≈ **8.0–8.8 (High/Critical)** — physical safety impact (внезапное торможение под едущим человеком) обычно поднимает практическую критичность выше формального CVSS.

### 11.2 Гипотеза для актуальных Whoosh/Urent флотов (§8)

Так как гипотеза UNCONFIRMED, формальный CVSS не присваивается production-инстансу. Если бы уровень D (§10) подтвердился на реальном устройстве в лабораторных условиях, потенциальный CVSS соответствовал бы схожему диапазону (**High**, из-за physical safety + free-ride/theft impact), но это **гипотетическая оценка "если подтвердится"**, а не оценка существующего подтверждённого риска.

### 11.3 Broken authorization на backend (класс, §5.3)

- Типично оценивается как **Medium–High** в зависимости от того, ограничивается ли эффект бесплатной поездкой (Medium, business impact) или позволяет полный account/device takeover (High).

---

## 12. Remediation Recommendations (общие, industry-standard)

1. **Device-side authorization, не только app-side.** Устройство обязано валидировать наличие действующего, backend-подписанного session-токена перед исполнением `unlock`/`speed-change`/`firmware-update`, а не полагаться на то, что "приложение уже проверило пароль".
2. **Заменить AES-ECB на AEAD-схему** (AES-GCM/ChaCha20-Poly1305) с уникальным nonce на сообщение — устраняет детерминированность шифротекста и обеспечивает встроенную integrity-проверку, попутно делая replay значительно сложнее при правильной nonce-политике.
3. **Заменить SHA-1 в key-derivation** на HKDF/SHA-256+ — SHA-1 считается криптографически ослабленным для новых дизайнов.
4. **Command signing + freshness (nonce/timestamp) для критичных команд** (`unlock`, `firmware-update`, `disable anti-theft`) — сервер подписывает команду с коротким TTL, устройство отклоняет "старые" или уже использованные подписи (защита от replay).
5. **Secure boot + подпись прошивки**, обязательная проверка на bootloader-уровне перед flashing, вне зависимости от того, идёт ли обновление через официальный canal или "инженерный" BLE UART путь.
6. **Anti-downgrade protection** как обязательный default на всех линиях (включая rental), не опционально добавляемый постфактум.
7. **Backend-side anomaly detection**: unlock-события без соответствующего billing/session-события должны алертить fleet-операции.
8. **Явное разделение rental- и consumer-прошивки** по auth-модели должно быть задокументировано (внутренне) и периодически верифицировано через diff-аудит между релизами — это закрывает ключевой "пробел доказательности", который блокирует итог §8 от однозначного вывода.
9. **Публичная (или partner-only) bug bounty программа** для этой продуктовой категории — прецедент (Habr, 2022) показывает, что отрасль уже реагирует конструктивно на responsible disclosure; формализация программы снижает риск того, что находки останутся непропатченными или попадут в серую зону.

---

## 13. Bug Bounty Report — рабочий шаблон

Ниже — шаблон, который следует использовать при подаче находки в программу оператора, заполненный как **иллюстративный пример на основе публично известного исторического CVE** (то есть НЕ новая находка, а демонстрация формата, применённого к уже раскрытой уязвимости для калибровки).

```
Title: BLE unlock/control commands accepted without device-side session validation
Affected product: Ninebot ES2 / ES4 (Segway-Ninebot), Xiaomi M365 — consumer BLE dashboard firmware, pre-2019 patch
Affected version: Firmware predating the 2019 Zimperium disclosure fix (exact build numbers per CVE-2019-13387 advisory)
Attack surface: BLE GATT interface between scooter dashboard MCU and companion mobile app
Prerequisites: BLE proximity to target device; no valid app session, no password/PIN required (per original finding)
Technical root cause: Password/session state was enforced only in the companion mobile application; the scooter's BLE
  firmware did not track or require authenticated session state before accepting control commands
  (throttle, brake, anti-theft lock/unlock) or unsigned firmware writes.
Safe reproduction: On an owned/lab device — passive BLE GATT service/characteristic enumeration (nRF Connect),
  followed by a write to the documented control characteristic while the companion app is closed / no session
  active, observing whether the command is accepted. No production/rented device, no third party's device.
Observed result (per original public disclosure): commands accepted without prior authentication;
  arbitrary firmware could be pushed without signature verification.
Expected result: device rejects any state-changing BLE write absent a valid, backend-issued session token
  verified device-side; firmware writes require signature verification against a vendor key.
Security impact: Unauthenticated remote (BLE-proximity) command injection; unsigned firmware flashing;
  potential for sudden deceleration/acceleration under a riding user (physical safety impact); device theft
  via forced unlock without payment.
Business impact: Free/unauthorized rides, fleet-wide reputational and liability risk, potential regulatory
  exposure given physical safety implications.
Severity: High (CVSS ~8.0-8.8 given physical safety amplification), per original disclosure.
Evidence: Zimperium public blog post "Don't Give Me a Brake" (Feb 2019); CVE-2019-13387; corroborating
  press coverage (Threatpost, The Hacker News, TechSpot).
Suggested remediation: See §12 above (device-side session enforcement, signed firmware, AEAD encryption,
  anti-downgrade protection).
```

Для **новой, ещё не подтверждённой гипотезы** (главная гипотеза, §8) правильная bug-bounty-подача на данный момент — это не "Title/Affected product/..." репорт (потому что нет PoC на реальном устройстве), а **research brief / responsible pre-disclosure**, формулируемый так:

```
Subject: Request for scoped test access — potential device-side authorization gap in BLE unlock flow
  (Ninebot Max G30 / Max Plus rental customization)

Summary: Historical precedent (CVE-2019-13387) demonstrates that this hardware/firmware lineage has previously
  shipped with BLE authorization enforced only client-side. Current rental firmware's authorization model is
  not publicly documented. Requesting either (a) a lab/staging device or firmware sample under NDA, or
  (b) confirmation that device-side session validation was implemented post-2019, to close or escalate
  this hypothesis through safe, non-production testing.

No production device has been or will be tested without explicit scoped authorization.
```

---

## 14. Источники

1. Zimperium — ["Don't Give Me a Brake — Xiaomi Scooter Hack Enables Dangerous Accelerations and Stops"](https://zimperium.com/blog/dont-give-me-a-brake-xiaomi-scooter-hack-enables-dangerous-accelerations-and-stops-for-unsuspecting-riders), Feb 2019; CVE-2019-13387.
2. [The Hacker News — "Xiaomi Electric Scooters Vulnerable to Life-Threatening Remote Hacks"](https://thehackernews.com/2019/02/xiaomi-electric-scooter-hack.html), Feb 2019.
3. [Threatpost — "Xiaomi M365 Electric Scooter Hacked and Remotely Controlled"](https://threatpost.com/xiaomi-m365-scooter-hack/141731/).
4. [TechSpot — "Vulnerability in Xiaomi's M365 scooter lets hackers control speed, slam on brakes"](https://www.techspot.com/news/78751-vulnerability-xiaomi-m365-scooter-hackers-control-speed-slam.html).
5. IOActive — ["Security Advisory: Ninebot/Segway miniPRO"](https://www.ioactive.com/wp-content/uploads/pdfs/IOActive-Security-Advisory-Ninebot-Segway-miniPRO_Final.pdf), 2017; [press release](https://www.ioactive.com/article/ioactive-finds-critical-security-vulnerabilities-in-segway-ninebot-minipro-hoverboard/).
6. Casagrande, Cestaro, Losiouk, Conti, Antonioli — ["E-Spoofer: Attacking and Defending Xiaomi Electric Scooter Ecosystem"](https://dl.acm.org/doi/10.1145/3558482.3590176), ACM WiSec'23; [EURECOM page](https://www.eurecom.fr/en/publication/7262); [GitHub toolkit](https://github.com/Skiti/E-Spoofer).
7. NootNooot — ["Segway-Ninebot BLE Protocol"](https://nootnooot.codeberg.page/segway-ninebot-ble/), Codeberg Pages (reverse-engineered from `com.ninebot.segway` app + `libnbcrypto.so`).
8. [`etransport/py9b`](https://github.com/etransport/py9b) — Ninebot/Xiaomi scooter communication library.
9. [`etransport/ninebot-docs` wiki — protocol page](https://github.com/etransport/ninebot-docs/wiki/protocol).
10. [`scooterhacking/NinebotCrypto`](https://github.com/scooterhacking/NinebotCrypto) — reimplementation of majsi's Ninebot/Xiaomi crypto protocol reverse-engineering.
11. [`ownbee/ninebot-ble`](https://github.com/ownbee/ninebot-ble) — Python BLE client, includes newer encrypted protocol via `miauth`.
12. [`BobMcGlobus/ha-ninebot`](https://github.com/BobMcGlobus/ha-ninebot) — Home Assistant integration, documents both "classic" (Max G30 and relatives) and newer AES-encrypted (Max G3+) protocol generations.
13. [`CamiAlfa/M365-BLE-PROTOCOL`](https://github.com/CamiAlfa/M365-BLE-PROTOCOL), [`ub4raf/Ninebot-PROTOCOL`](https://github.com/ub4raf/Ninebot-PROTOCOL) — packet-format reverse engineering.
14. ScooterHacking.org — [forum/articles on Ninebot Max G30 firmware, BLE dashboard dumping, IAP flashing](https://articles.scooterhacking.org/index.php/2019/10/28/g30-mods/); [Joey Babcock — Ninebot Max/G30 firmware wiki](https://joeybabcock.me/wiki/Ninebot_Max/G30_Firmware).
15. Whoosh corporate news — ["Стратегическое партнерство Whoosh и Segway-Ninebot"](http://news.whoosh-bike.ru/whoosh_segway_ninebot); ["Whoosh стартует сезон с обновленной моделью электросамоката"](http://news.whoosh-bike.ru/ir/whoosh_startuet_sezon_s_obnovlennoy_modelyu_elektrosamokata); [iXBT coverage, март 2024](https://www.ixbt.com/news/2024/03/18/v-kiksheringe-whoosh-predstavili-obnovljonnuju-model-jelektrosamokata-k-zapusku-sezona.html).
16. Habr — ["Как мы кикшеринг взломали"](https://habr.com/ru/articles/660575/), апрель 2022 (backend API authorization finding, responsibly disclosed, rewarded).
17. Habr / Bastion — ["«У нас воруют — мы находим...» Как устроена система безопасности шеринга самокатов Юрент"](https://habr.com/ru/companies/bastion/articles/669500/).
18. vc.ru — Alexey Hazoke, ["Дырявый WHOOSH. Или как можно бесплатно кататься на самокатах"](https://vc.ru/id1857026/868077-dyryavyi-whoosh-ili-kak-mozhno-besplatno-katatsya-na-samokatah).
19. Gazeta.ru — ["Бесплатный проезд и кража. Что хакер может сделать с прокатным самокатом?"](https://www.gazeta.ru/tech/2025/05/22/21078458.shtml), май 2025 (МТС Юрент, техдиректор Андрей Калинин, on-record statement).
20. Segway Commercial — [Kickscooter T60 / T60 Lite](https://b2b.segway.com/kickscooter-t60/), [Bot Series blog post](https://b2b.segway.com/blog/smarter-than-ever-segways-new-bot-series-uses-ai-to-make-shared-rides-safer/); [Flespi device docs for Segway Scooter IoT 2nd/3rd Gen, ZK601LE](https://flespi.com/devices/segway-ninebot-zk601le).

---

## 15. Итоговое резюме для читателя, которому нужен один абзац

Публично задокументирован **реальный исторический прецедент** (CVE-2019-13387, 2019 г.) ровно того класса уязвимости, который сформулирован в главной гипотезе задания — BLE-команды, принимаемые устройством Ninebot ES2/ES4 и Xiaomi M365 без валидации сессии на стороне устройства. Это доказывает, что архитектурный паттерн **возможен и уже случался** на аппаратно-родственной линейке продуктов. Однако **прямых доказательств**, что этот же паттерн сохраняется в **текущих**, **rental-кастомизированных** прошивках, которые реально используют Whoosh (Ninebot Max G30/Max Plus) и Urent/МТС Юрент (Ninebot Max Plus) сегодня, **не обнаружено**. Официальное заявление представителя Urent отрицает практическую осуществимость удалённого BLE-доступа к "мозгам" устройства, но это заявление вендора, не независимый аудит, и оно частично расходится с задокументированной сообществом возможностью BLE OTA-прошивки консьюмерских Max/G30-дашбордов без разборки корпуса. **Итог по главной гипотезе: не подтверждена, но обоснованно достойна дальнейшей safe-lab проверки** по методологии §8.3/§10, а не отклонения с порога и не принятия как факта без доказательств.
