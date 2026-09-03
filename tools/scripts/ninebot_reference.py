"""
Verified Ninebot/Xiaomi BLE constants (shared by the analysis scripts).

Every value here is sourced from a public reverse-engineering project and
documented in ../../docs/16-ble-protocol-reference.md. These describe the
CONSUMER "classic" protocol; applicability to rental-customized firmware is
POSSIBLE but unconfirmed -- which is exactly what a GATT snapshot from a real
rental device is meant to test against.

No secrets, keys, or exploit payloads live here -- only public,
interoperability-oriented identifiers.
"""

# Nordic UART Service (NUS) -- the transport used by the classic protocol.
# Source: etransport/py9b (py9b/link/ble.py)
NUS_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_RX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # phone -> scooter (write)
NUS_TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # scooter -> phone (notify)
CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"

# Advertising name prefixes. Source: etransport/py9b (ble.py name filter).
KNOWN_NAME_PREFIXES = {
    "MISc": "Mi Scooter (Xiaomi-branded M365 and relatives)",
    "NBSc": "Ninebot Scooter (Ninebot-branded, incl. Max/ES family)",
}

# Classic packet framing. Source: CamiAlfa/M365-BLE-PROTOCOL (ninebot.h).
PACKET_HEADER = bytes([0x55, 0xAA])
CMD_READ = 0x01
CMD_WRITE = 0x03
MAX_PAYLOAD = 0x38  # 56 bytes -- BLE buffer limit

# Property names that indicate a characteristic could carry commands to the
# device (level E in docs/10-safe-poc-methodology.md). Presence is logged, never used.
WRITE_LIKE_PROPERTIES = {"write", "writeWithoutResponse", "authenticatedSignedWrites"}


def normalize_uuid(uuid: str) -> str:
    """Lowercase; expand a 16-bit shorthand (e.g. 'fe95') to full 128-bit base UUID."""
    u = uuid.strip().lower()
    if len(u) == 4:  # 16-bit shorthand
        return f"0000{u}-0000-1000-8000-00805f9b34fb"
    return u


def known_name_prefix(name: str | None) -> str | None:
    """Return the human label if `name` starts with a known prefix, else None."""
    if not name:
        return None
    for prefix, label in KNOWN_NAME_PREFIXES.items():
        if name.startswith(prefix):
            return label
    return None
