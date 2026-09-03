# 14. Источники

[← Назад к индексу](../README.md)

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
21. Apple — [Core Bluetooth framework documentation](https://developer.apple.com/documentation/corebluetooth) (используется в `tools/ios-app`).
22. [`hbldh/bleak`](https://github.com/hbldh/bleak) — cross-platform Python BLE library (используется в `tools/scripts`).
23. Rasmus Moorats — ["Reverse engineering my cloud-connected e-scooter and finding the master key to unlock all scooters"](https://blog.nns.ee/2026/01/06/aike-ble/), nns.ee, янв 2026 (Äike default-key, первоисточник).
24. [The Register — "Bankrupt scooter startup left one private key to rule them all"](https://www.theregister.com/2026/01/16/bankrupt_scooter_startup_key/); [Hackaday — "The Defunct Scooter Company, And The Default Key"](https://hackaday.com/2026/01/23/the-defunct-scooter-company-and-the-default-key/); [Korben](https://korben.info/en/magic-key-unlocks-every-aike-scooter.html) — Äike/Tuul, янв 2026.
25. NootNooot — Encryption2 (AES-128 CCM-like, 3-фазный handshake): [Segway-Ninebot BLE Protocol](https://nootnooot.codeberg.page/segway-ninebot-ble/) (primary, egress-blocked в этой сессии; подтверждено вторичными пересказами и `BobMcGlobus/ha-ninebot`).
26. [djensenius — Segway GT3 Pro BLE Protocol Reference](https://gist.github.com/djensenius/48d6aef55a4ad403775cc5ff5fe92f53) — verified native Ninebot service UUID `6e400001-0000-0000-006e-696e65626f74` (ASCII "ninebot"), notify `…0004`.
27. [CISA ICSA-26-113-01 / CVE-2025-70994 — Yadea T5](https://www.cisa.gov/news-events/ics-advisories/icsa-26-113-01) (RF-брелок EV1527, не BLE); [CVE-2026-1354 — Zero Motorcycles](https://www.sentinelone.com/vulnerability-database/cve-2026-1354/) (forced BLE pairing → OTA). См. [§19](19-adjacent-cves-and-tools.md).
