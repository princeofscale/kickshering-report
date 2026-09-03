# 13. Bug Bounty Report — рабочий шаблон

[← Назад к индексу](../README.md)

Ниже — шаблон, который следует использовать при подаче находки в программу оператора,
заполненный как **иллюстративный пример на основе публично известного исторического CVE** (то
есть НЕ новая находка, а демонстрация формата, применённого к уже раскрытой уязвимости для
калибровки).

```
Title: BLE unlock/control commands accepted without device-side session validation
Affected product: Ninebot ES2 / ES4 (Segway-Ninebot), Xiaomi M365 — consumer BLE dashboard firmware, pre-2019 patch
Affected version: Firmware predating the 2019 Zimperium disclosure fix (exact build numbers per CVE-2019-13387 advisory)
Attack surface: BLE GATT interface between scooter dashboard MCU and companion mobile app
Prerequisites: BLE proximity to target device; no valid app session, no password/PIN required (per original finding)
Technical root cause: Password/session state was enforced only in the companion mobile application; the scooter's BLE
  firmware did not track or require authenticated session state before accepting control commands
  (throttle, brake, anti-theft lock/unlock) or unsigned firmware writes.
Safe reproduction: On an owned/lab device — passive BLE GATT service/characteristic enumeration (nRF Connect /
  tools/ios-app in this repo), followed by a write to the documented control characteristic while the companion
  app is closed / no session active, observing whether the command is accepted. No production/rented device,
  no third party's device.
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
Suggested remediation: See docs/12-remediation.md (device-side session enforcement, signed firmware, AEAD
  encryption, anti-downgrade protection).
```

Для **новой, ещё не подтверждённой гипотезы** (главная гипотеза, [§8](08-main-hypothesis.md))
правильная bug-bounty-подача на данный момент — это не "Title/Affected product/..." репорт
(потому что нет PoC на реальном устройстве), а **research brief / responsible pre-disclosure**,
формулируемый так:

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

Если ваша собственная физическая проверка (см.
[Field Testing Guide](15-field-testing-guide.md)) даст конкретные, воспроизводимые
результаты уровня D/E из [§10](10-safe-poc-methodology.md), используйте первый шаблон,
заполнив его собственными данными (модель, дата, лог-файл из `logs/` как evidence) — и
подавайте его **только** через официальный канал responsible disclosure оператора (bug bounty
программа, security@ контакт), не публично.
