#!/usr/bin/env python3
"""
Active BLE GATT service/characteristic enumerator -- READ-ONLY.

Part of the kickshering-report security research repository.
See ../README.md and ../../docs/00-scope-and-methodology.md for scope/safety rules.

SAFETY / SCOPE:
  - This script connects to ONE specified device and enumerates its
    GATT services, characteristics, and properties.
  - It reads characteristics that advertise the "read" property.
  - It NEVER writes to any characteristic. There is no call to
    write_gatt_char (or any write primitive) anywhere in this file --
    by design, so it cannot be accidentally pointed at an
    unlock/control characteristic.
  - Only run this against a device you OWN, or one you are currently
    and legitimately renting under your own paid account (read-only
    enumeration during your own active, authorized ride does not
    change device or billing state). Never run against a device
    mid-ride by someone else, or a parked device you have not rented.

Usage:
    python3 ble_gatt_enumerate.py AA:BB:CC:DD:EE:FF --i-own-this-device --out gatt_log.json
"""
import argparse
import asyncio
import json
from datetime import datetime, timezone

from bleak import BleakClient


async def enumerate_device(address: str, out_path: str) -> None:
    result = {
        "tool": "ble_gatt_enumerate.py",
        "tool_note": "Read-only enumeration. No write_gatt_char call exists in this script.",
        "address": address,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "services": [],
    }

    print(f"Connecting to {address} for READ-ONLY enumeration...")
    async with BleakClient(address) as client:
        print(f"Connected: {client.is_connected}")
        for service in client.services:
            svc_record = {"uuid": str(service.uuid), "characteristics": []}
            for char in service.characteristics:
                props = list(char.properties)
                char_record = {"uuid": str(char.uuid), "properties": props, "value_hex": None}
                if "read" in props:
                    try:
                        value = await client.read_gatt_char(char.uuid)
                        char_record["value_hex"] = value.hex()
                        print(f"  READ  {char.uuid}  props={props}  value=0x{value.hex()}")
                    except Exception as e:  # noqa: BLE001 -- log and continue enumerating
                        char_record["read_error"] = str(e)
                        print(f"  READ  {char.uuid}  props={props}  error={e}")
                else:
                    print(f"  SKIP  {char.uuid}  props={props}  (no 'read' property, not touched)")
                svc_record["characteristics"].append(char_record)
            result["services"].append(svc_record)

    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"\nWrote GATT snapshot to {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("address", help="BLE device address/UUID (from ble_passive_scan.py output)")
    parser.add_argument(
        "--i-own-this-device",
        action="store_true",
        required=True,
        help="Required: confirms this is your own device, or your own currently active authorized rental",
    )
    parser.add_argument("--out", default="gatt_log.json", help="Output JSON path (default: gatt_log.json)")
    args = parser.parse_args()
    asyncio.run(enumerate_device(args.address, args.out))


if __name__ == "__main__":
    main()
