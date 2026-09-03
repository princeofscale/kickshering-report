#!/usr/bin/env python3
"""
Passive BLE advertisement scanner/logger.

Part of the kickshering-report security research repository.
See ../README.md and ../../docs/00-scope-and-methodology.md for scope/safety rules.

SAFETY: This script only listens to BLE advertising packets. It never
connects, pairs, bonds, or writes to any device. Safe to run near any
BLE device, including ones you do not own, because passive scanning is
how every BLE central (incl. the official rental app) discovers
devices in the first place -- no device or backend state is changed.

Usage:
    python3 ble_passive_scan.py --seconds 60 --out scan_log.json
    python3 ble_passive_scan.py --seconds 120 --name-filter Ninebot --out scan_log.json
"""
import argparse
import asyncio
import json
from datetime import datetime, timezone

from bleak import BleakScanner


async def scan(seconds: float, out_path: str, name_filter: str | None) -> None:
    records = []

    def callback(device, advertisement_data):
        name = device.name or advertisement_data.local_name
        if name_filter and (not name or name_filter.lower() not in name.lower()):
            return

        rec = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "address": device.address,
            "name": name,
            "rssi": advertisement_data.rssi,
            "service_uuids": list(advertisement_data.service_uuids),
            "manufacturer_data_hex": {
                str(k): v.hex() for k, v in advertisement_data.manufacturer_data.items()
            },
        }
        records.append(rec)
        print(
            f"[{rec['timestamp']}] {rec['name'] or '(unnamed)'} "
            f"{rec['address']} RSSI={rec['rssi']} services={rec['service_uuids']}"
        )

    print("Passive scan starting -- listening to advertising only, no connections will be made.")
    scanner = BleakScanner(callback)
    await scanner.start()
    try:
        await asyncio.sleep(seconds)
    finally:
        await scanner.stop()

    payload = {
        "tool": "ble_passive_scan.py",
        "tool_note": "Passive advertisement scan only. No connections were made.",
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "advertisements": records,
    }
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
    print(f"\nWrote {len(records)} advertisement record(s) to {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seconds", type=float, default=60, help="Scan duration in seconds (default: 60)")
    parser.add_argument("--out", default="scan_log.json", help="Output JSON path (default: scan_log.json)")
    parser.add_argument(
        "--name-filter",
        default=None,
        help="Only log devices whose advertised name contains this substring (e.g. 'Ninebot', 'MAX', 'Segway')",
    )
    args = parser.parse_args()
    asyncio.run(scan(args.seconds, args.out, args.name_filter))


if __name__ == "__main__":
    main()
