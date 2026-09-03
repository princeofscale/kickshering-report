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

# Family A -- Legacy / M365 (Nordic UART Service). Source: etransport/py9b (ble.py)
NUS_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_RX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # phone -> scooter (write)
NUS_TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # scooter -> phone (notify)
CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"

# Family B -- Native Ninebot service. Source: djensenius Segway GT3 Pro BLE Reference.
# Suffix 6e 69 6e 65 62 6f 74 == ASCII "ninebot". NOTE: notify is ...0004, NOT ...0003.
NB_SERVICE_UUID = "6e400001-0000-0000-006e-696e65626f74"
NB_WRITE_CHAR_UUID = "6e400002-0000-0000-006e-696e65626f74"  # phone -> scooter (write)
NB_NOTIFY_CHAR_UUID = "6e400004-0000-0000-006e-696e65626f74"  # scooter -> phone (notify)

# Any service UUID whose suffix contains this ASCII-"ninebot" marker is a native Ninebot service.
NINEBOT_ASCII_MARKER = "696e65626f74"

# The two transport service UUIDs we recognize as Ninebot/Xiaomi.
KNOWN_SERVICE_UUIDS = {NUS_SERVICE_UUID, NB_SERVICE_UUID}

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


def is_ninebot_service(uuid: str) -> bool:
    """True if the UUID is a known Ninebot transport service (either family),
    or any UUID whose suffix embeds the ASCII 'ninebot' marker."""
    u = normalize_uuid(uuid)
    return u in KNOWN_SERVICE_UUIDS or NINEBOT_ASCII_MARKER in u.replace("-", "")


def is_command_write_char(uuid: str) -> bool:
    """True for the write ('command') characteristic of either service family."""
    u = normalize_uuid(uuid)
    return u in {NUS_RX_CHAR_UUID, NB_WRITE_CHAR_UUID}
