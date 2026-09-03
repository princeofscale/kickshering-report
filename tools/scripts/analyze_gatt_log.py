#!/usr/bin/env python3
"""
Offline analyzer for exported BLE logs (from tools/ios-app or the scan/enumerate scripts).

Part of the kickshering-report security research repository.
See ../../docs/16-ble-protocol-reference.md for the constants this checks against.

READ-ONLY / OFFLINE: this script touches no Bluetooth device. It parses a JSON
log file you already captured and produces a Markdown evidence table that:
  - flags devices matching known Ninebot/Xiaomi name prefixes,
  - flags the Nordic UART Service and its RX/TX characteristics if present,
  - lists every write-capable characteristic (potential command channel,
    level E in docs/10) -- WITHOUT ever writing to anything,
  - notes deviations from the expected classic-protocol GATT shape.

Accepts both log shapes documented in evidence_log_schema.md:
  - iOS export:   {"advertisements": [...], "gattSnapshots": [{"services":[...]}]}
  - Python export (ble_gatt_enumerate.py): {"services":[...]}  (single device)
  - Python export (ble_passive_scan.py):   {"advertisements":[...]}

Usage:
    python3 analyze_gatt_log.py ../../logs/2026-09-03-max-plus/post-rental-gatt.json
    python3 analyze_gatt_log.py pre.json --out ../../logs/2026-09-03-max-plus/analysis.md
    python3 analyze_gatt_log.py pre.json --diff post.json   # compare two GATT snapshots
"""
import argparse
import json
import sys
from typing import Any

import ninebot_reference as ref


def load(path: str):
    with open(path) as f:
        return json.load(f)


def extract_snapshots(doc) -> list[dict]:
    """Return a list of GATT snapshots ({name, services:[...]}) from any supported shape:
    - iOS raw export: {"gattSnapshots": [...]}
    - python enumerate: {"services": [...]}
    - iOS 'Export all' (SnapshotStore): a top-level list of SavedSnapshot, each with
      .snapshot, .state, .label -- unwrapped here, carrying state/label onto the snapshot."""
    if isinstance(doc, list):  # Export-all: [SavedSnapshot, ...]
        out = []
        for item in doc:
            snap = item.get("snapshot") if isinstance(item, dict) else None
            if snap is not None:
                snap = dict(snap)
                snap.setdefault("name", item.get("label"))
                snap["_state"] = item.get("state")
                snap["_label"] = item.get("label")
                out.append(snap)
        return out
    if "gattSnapshots" in doc:
        return doc["gattSnapshots"]
    if "services" in doc:  # single-device python enumerate export
        return [{"name": doc.get("name") or doc.get("address"), "services": doc["services"]}]
    return []


def char_props(char: dict) -> list[str]:
    return char.get("properties", [])


def analyze_snapshot(snap: dict) -> dict:
    services = snap.get("services", [])
    svc_uuids = {ref.normalize_uuid(s["uuid"]) for s in services}
    ninebot_services = sorted(u for u in svc_uuids if ref.is_ninebot_service(u))
    has_ninebot_service = bool(ninebot_services)

    write_like: list[tuple[str, str, list[str]]] = []  # (service, char, props)
    write_char_present = notify_char_present = False
    total_chars = 0
    for s in services:
        s_uuid = ref.normalize_uuid(s["uuid"])
        for c in s.get("characteristics", []):
            total_chars += 1
            c_uuid = ref.normalize_uuid(c["uuid"])
            props = char_props(c)
            if c_uuid in {ref.NUS_RX_CHAR_UUID, ref.NB_WRITE_CHAR_UUID}:
                write_char_present = True
            if c_uuid in {ref.NUS_TX_CHAR_UUID, ref.NB_NOTIFY_CHAR_UUID}:
                notify_char_present = True
            if ref.WRITE_LIKE_PROPERTIES.intersection(props):
                write_like.append((s_uuid, c_uuid, props))

    return {
        "name": snap.get("name"),
        "known_family": ref.known_name_prefix(snap.get("name")),
        "service_count": len(services),
        "characteristic_count": total_chars,
        "has_ninebot_service": has_ninebot_service,
        "ninebot_services": ninebot_services,
        "command_write_char_present": write_char_present,
        "notify_char_present": notify_char_present,
        "write_like": write_like,
        "service_uuids": sorted(svc_uuids),
    }


def render_markdown(doc: dict, source_path: str) -> str:
    out: list[str] = []
    out.append(f"# GATT log analysis — `{source_path}`\n")
    out.append("_Generated offline by `analyze_gatt_log.py` — no device was contacted._\n")

    ads = doc.get("advertisements", []) if isinstance(doc, dict) else []
    if ads:
        out.append("## Advertising records\n")
        out.append("| Name | Family (by prefix) | RSSI | Advertised services |")
        out.append("|---|---|---|---|")
        for a in ads:
            name = a.get("name") or "(unnamed)"
            fam = ref.known_name_prefix(a.get("name")) or "—"
            rssi = a.get("rssi", "?")
            svcs = ", ".join(a.get("service_uuids", a.get("serviceUUIDs", []))) or "—"
            out.append(f"| {name} | {fam} | {rssi} | {svcs} |")
        out.append("")

    snaps = extract_snapshots(doc)
    if snaps:
        out.append("## GATT snapshots\n")
        for snap in snaps:
            a = analyze_snapshot(snap)
            out.append(f"### Device: {a['name'] or '(unknown)'}\n")
            out.append(f"- Known family by name prefix: **{a['known_family'] or 'not matched'}**")
            out.append(f"- Services: {a['service_count']}, characteristics: {a['characteristic_count']}")
            out.append(f"- Ninebot transport service present: **{'YES' if a['has_ninebot_service'] else 'no'}**"
                       f" (command write char: {'yes' if a['command_write_char_present'] else 'no'},"
                       f" notify char: {'yes' if a['notify_char_present'] else 'no'})")
            if a["has_ninebot_service"]:
                out.append(f"  - Ninebot service UUID(s): {', '.join(a['ninebot_services'])}")
                out.append("  - → matches a Ninebot/Xiaomi transport (docs/16, family A NUS or family B native). "
                           "The write char is the command channel; this tool never writes to it.")
            out.append("")
            if a["write_like"]:
                out.append("- **Write-capable characteristics (potential command channel, level E — NOT written to):**")
                out.append("")
                out.append("  | Service UUID | Characteristic UUID | Properties |")
                out.append("  |---|---|---|")
                for s_uuid, c_uuid, props in a["write_like"]:
                    note = " (command channel)" if ref.is_command_write_char(c_uuid) else ""
                    out.append(f"  | {s_uuid} | {c_uuid}{note} | {', '.join(props)} |")
                out.append("")
            else:
                out.append("- No write-capable characteristics found in this snapshot.")
                out.append("")

    out.append("## Interpretation notes\n")
    out.append("- Presence of a write-capable characteristic is **transport**, not a vulnerability "
               "by itself (see docs/16.1). The security question is whether the device *executes* a "
               "privileged command from that channel without a valid device-side rental session.")
    out.append("- To move the main hypothesis (docs/08) forward safely, compare a snapshot taken "
               "BEFORE starting your own authorized rental with one taken AFTER — use `--diff`.")
    return "\n".join(out)


def diff_snapshots(doc_a: dict, doc_b: dict, path_a: str, path_b: str) -> str:
    snaps_a = extract_snapshots(doc_a)
    snaps_b = extract_snapshots(doc_b)
    out: list[str] = []
    out.append(f"# GATT diff — `{path_a}` (A) vs `{path_b}` (B)\n")
    out.append("_Offline comparison. Focus: does the reachable GATT surface change with rental state?_\n")

    def surface(doc_snaps: list[dict]) -> dict[str, set[str]]:
        """Map service UUID -> set of 'charUUID[props]' strings, merged across devices."""
        m: dict[str, set[str]] = {}
        for snap in doc_snaps:
            for s in snap.get("services", []):
                s_uuid = ref.normalize_uuid(s["uuid"])
                bucket = m.setdefault(s_uuid, set())
                for c in s.get("characteristics", []):
                    bucket.add(f"{ref.normalize_uuid(c['uuid'])} [{','.join(char_props(c))}]")
        return m

    sa, sb = surface(snaps_a), surface(snaps_b)
    all_services = sorted(set(sa) | set(sb))
    any_change = False
    out.append("| Service UUID | Only in A | Only in B |")
    out.append("|---|---|---|")
    for svc in all_services:
        a_only = sorted(sa.get(svc, set()) - sb.get(svc, set()))
        b_only = sorted(sb.get(svc, set()) - sa.get(svc, set()))
        if a_only or b_only:
            any_change = True
            out.append(f"| {svc} | {'<br>'.join(a_only) or '—'} | {'<br>'.join(b_only) or '—'} |")
    if not any_change:
        out.append("| _(no differences — identical service/characteristic/property surface)_ | — | — |")
    out.append("")
    out.append("## Reading this diff\n")
    if not any_change:
        out.append("- **Identical surface** before/after rental start. This does NOT prove the hypothesis "
                   "(it needs a real write test on an isolated lab device, out of scope here), but it shows "
                   "the BLE GATT structure does not gate on rental state — worth further study on owned hardware.")
    else:
        out.append("- **Surface changed** with rental state. If characteristics became reachable only AFTER "
                   "an authorized rental started, that points to backend involvement in BLE availability, "
                   "which would weaken the 'local BLE unlock without session' hypothesis.")
    return "\n".join(out)


def consistency_report(doc, path: str) -> str:
    """Group snapshots by _state (from an iOS Export-all) and check surface stability
    across repeats -- the negative-control test (docs/20.4): repeated captures of the
    SAME state should be identical; differences are noise/confounders, not findings."""
    snaps = extract_snapshots(doc)
    groups: dict[str, list[dict]] = {}
    for s in snaps:
        groups.setdefault(s.get("_state") or "(no state)", []).append(s)
    out = [f"# Consistency check — `{path}`\n",
           "_Repeated captures of the same state should match. Divergence = noise/confounder._\n"]
    for state, items in sorted(groups.items()):
        surfaces = [frozenset().union(*[set(v) for v in surface_map(i).values()]) if surface_map(i) else frozenset()
                    for i in items]
        stable = all(x == surfaces[0] for x in surfaces)
        out.append(f"## State: {state} — {len(items)} capture(s): "
                   f"**{'STABLE' if stable else 'DIVERGENT'}**")
        if not stable:
            base = surfaces[0]
            for idx, srf in enumerate(surfaces[1:], start=2):
                only_new = sorted(srf - base)
                only_gone = sorted(base - srf)
                if only_new or only_gone:
                    out.append(f"- capture #{idx}: +{only_new or '—'} / -{only_gone or '—'}")
        out.append("")
    return "\n".join(out)


def surface_map(snap: dict) -> dict[str, set[str]]:
    m: dict[str, set[str]] = {}
    for s in snap.get("services", []):
        key = ref.normalize_uuid(s["uuid"])
        m.setdefault(key, set())
        for c in s.get("characteristics", []):
            m[key].add(f"{ref.normalize_uuid(c['uuid'])} [{','.join(char_props(c))}]")
    return m


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", help="Path to a JSON log (iOS export, python export, or iOS Export-all list)")
    parser.add_argument("--diff", metavar="OTHER_LOG", help="Second GATT log to diff against the first")
    parser.add_argument("--consistency", action="store_true",
                        help="Group by capture state and check stability across repeats (negative control)")
    parser.add_argument("--out", help="Write Markdown to this path instead of stdout")
    args = parser.parse_args()

    doc = load(args.log)
    if args.consistency:
        md = consistency_report(doc, args.log)
    elif args.diff:
        md = diff_snapshots(doc, load(args.diff), args.log, args.diff)
    else:
        md = render_markdown(doc, args.log)

    if args.out:
        with open(args.out, "w") as f:
            f.write(md + "\n")
        print(f"Wrote analysis to {args.out}")
    else:
        print(md)


if __name__ == "__main__":
    sys.exit(main())
