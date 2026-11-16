from __future__ import annotations

import csv
from datetime import datetime, timezone
import io
import json
import struct
from typing import Any


SUBTYPE_NAMES = {
    (0, 0): "assoc_req",
    (0, 1): "assoc_resp",
    (0, 2): "reassoc_req",
    (0, 4): "probe_req",
    (0, 5): "probe_resp",
    (0, 8): "beacon",
    (0, 10): "disassoc",
    (0, 11): "auth",
    (0, 12): "deauth",
}


def freq_to_channel(freq_mhz: int) -> int:
    if freq_mhz == 2484:
        return 14
    if 2412 <= freq_mhz <= 2472:
        return (freq_mhz - 2412) // 5 + 1
    if 5180 <= freq_mhz <= 5825:
        return (freq_mhz - 5000) // 5
    return 0


def format_mac(raw: bytes) -> str:
    return ":".join(f"{b:02x}" for b in raw[:6])


def is_randomized_mac(mac: str) -> bool:
    try:
        first = int(mac.split(":")[0], 16)
    except (ValueError, IndexError):
        return False
    return bool(first & 0x02) and not bool(first & 0x01)


def parse_capture_bytes(contents: bytes, filename: str = "capture.pcap") -> list[dict[str, Any]]:
    lower = filename.lower()
    if lower.endswith(".pcapng") or contents[:4] == b"\x0a\x0d\x0d\x0a":
        return parse_pcapng_bytes(contents)
    if lower.endswith(".pcap") or contents[:4] in {
        b"\xd4\xc3\xb2\xa1",
        b"\xa1\xb2\xc3\xd4",
        b"\x4d\x3c\xb2\xa1",
        b"\xa1\xb2\x3c\x4d",
    }:
        return parse_pcap_bytes(contents)
    if lower.endswith(".csv"):
        return parse_csv_bytes(contents)
    if lower.endswith(".jsonl") or lower.endswith(".ndjson") or lower.endswith(".json"):
        return parse_jsonl_bytes(contents)
    # Fallback sniff by content
    stripped = contents.lstrip()
    if stripped.startswith(b"{") or stripped.startswith(b"["):
        return parse_jsonl_bytes(contents)
    if b"," in stripped[:256]:
        return parse_csv_bytes(contents)
    return parse_pcap_bytes(contents)


def parse_pcap_bytes(contents: bytes) -> list[dict[str, Any]]:
    if len(contents) < 24:
        raise ValueError("Capture file too small to be a valid PCAP")

    magic = contents[:4]
    if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
        endian = "<"
    elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        endian = ">"
    else:
        raise ValueError("Unsupported PCAP magic header")

    ns_precision = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
    _, _, _, _, _, _, linktype = struct.unpack(f"{endian}IHHiIII", contents[:24])

    offset = 24
    observations: list[dict[str, Any]] = []
    while offset + 16 <= len(contents):
        ts_sec, ts_sub, incl_len, _orig_len = struct.unpack(f"{endian}IIII", contents[offset : offset + 16])
        offset += 16
        if incl_len == 0 or offset + incl_len > len(contents):
            break
        pkt = contents[offset : offset + incl_len]
        offset += incl_len
        ts = ts_sec + (ts_sub / 1e9 if ns_precision else ts_sub / 1e6)
        obs = decode_80211_packet(pkt, linktype=linktype, timestamp=ts)
        if obs:
            observations.append(obs)
    return observations


def parse_pcapng_bytes(contents: bytes) -> list[dict[str, Any]]:
    offset = 0
    linktypes: list[int] = []
    observations: list[dict[str, Any]] = []
    endian = "<"

    while offset + 12 <= len(contents):
        block_type, block_len = struct.unpack(f"{endian}II", contents[offset : offset + 8])
        if block_type == 0x0A0D0D0A and offset + 12 <= len(contents):
            bom = contents[offset + 8 : offset + 12]
            if bom == b"\x4d\x3c\x2b\x1a":
                endian = "<"
            elif bom == b"\x1a\x2b\x3c\x4d":
                endian = ">"
            block_type, block_len = struct.unpack(f"{endian}II", contents[offset : offset + 8])

        if block_len < 12 or offset + block_len > len(contents):
            break

        body = contents[offset + 8 : offset + block_len - 4]
        if block_type == 0x00000001 and len(body) >= 2:
            linktype = struct.unpack(f"{endian}H", body[:2])[0]
            linktypes.append(linktype)
        elif block_type == 0x00000006 and len(body) >= 20:
            iface_id, ts_hi, ts_lo, cap_len, _ = struct.unpack(f"{endian}IIIII", body[:20])
            pkt = body[20 : 20 + cap_len]
            linktype = linktypes[iface_id] if iface_id < len(linktypes) else 127
            ts = ((ts_hi << 32) | ts_lo) / 1e6
            obs = decode_80211_packet(pkt, linktype=linktype, timestamp=ts)
            if obs:
                observations.append(obs)
        elif block_type == 0x00000003 and len(body) >= 4:
            pkt = body[4:]
            linktype = linktypes[0] if linktypes else 127
            obs = decode_80211_packet(pkt, linktype=linktype, timestamp=float(len(observations)))
            if obs:
                observations.append(obs)

        offset += block_len
    return observations


def decode_80211_packet(pkt: bytes, *, linktype: int, timestamp: float) -> dict[str, Any] | None:
    rssi = -65
    channel = 0
    rate_mbps = 0.0
    frame_start = 0

    if linktype == 127:  # DLT_IEEE802_11_RADIOTAP
        if len(pkt) < 8:
            return None
        _ver, _pad, rt_len, present = struct.unpack("<BBHI", pkt[:8])
        if rt_len > len(pkt) or rt_len < 8:
            return None

        cursor = 8
        first_present = present
        cur_present = present
        while cur_present & 0x80000000:
            if cursor + 4 > rt_len:
                break
            cur_present = struct.unpack("<I", pkt[cursor : cursor + 4])[0]
            cursor += 4

        def align(pos: int, boundary: int) -> int:
            rem = pos % boundary
            return pos if rem == 0 else pos + (boundary - rem)

        # Bit 0: TSFT (8 bytes, align 8)
        if first_present & (1 << 0):
            cursor = align(cursor, 8) + 8
        # Bit 1: Flags (1 byte, align 1)
        if first_present & (1 << 1):
            cursor += 1
        # Bit 2: Rate (1 byte, align 1)
        if first_present & (1 << 2):
            if cursor < rt_len:
                rate_mbps = pkt[cursor] * 0.5
            cursor += 1
        # Bit 3: Channel (2+2 bytes, align 2)
        if first_present & (1 << 3):
            cursor = align(cursor, 2)
            if cursor + 4 <= rt_len:
                freq_mhz, _flags = struct.unpack("<HH", pkt[cursor : cursor + 4])
                channel = freq_to_channel(freq_mhz)
            cursor += 4
        # Bit 4: FHSS (2 bytes, align 2)
        if first_present & (1 << 4):
            cursor = align(cursor, 2) + 2
        # Bit 5: dBm Antenna Signal (1 byte signed, align 1)
        if first_present & (1 << 5):
            if cursor < rt_len:
                rssi = struct.unpack("<b", pkt[cursor : cursor + 1])[0]
            cursor += 1

        frame_start = rt_len
    elif linktype == 105:  # DLT_IEEE802_11
        frame_start = 0
    else:
        return None

    mac_frame = pkt[frame_start:]
    if len(mac_frame) < 10:
        return None

    fc0, fc1 = mac_frame[0], mac_frame[1]
    ftype = (fc0 >> 2) & 0x03
    fsub = (fc0 >> 4) & 0x0F

    if ftype == 1:
        # Control frame (e.g. RTS/CTS/ACK) only carries Addr1/Addr2 depending on length
        sa = format_mac(mac_frame[10:16]) if len(mac_frame) >= 16 else format_mac(mac_frame[4:10])
        return {
            "node_id": "pcap_capture",
            "source": "pcap_upload",
            "timestamp": datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat() if timestamp > 1e8 else "",
            "ts_sec": round(timestamp, 4),
            "channel": channel or 6,
            "rssi": int(rssi),
            "frame_type": "ctrl",
            "subtype": "ctrl",
            "sa": sa,
            "bssid": sa,
            "ssid": "",
            "rate": rate_mbps,
            "pkt_len": len(mac_frame),
            "randomized": is_randomized_mac(sa),
        }

    if len(mac_frame) < 24:
        return None

    to_ds = fc1 & 0x01
    from_ds = (fc1 >> 1) & 0x01
    addr1 = format_mac(mac_frame[4:10])
    addr2 = format_mac(mac_frame[10:16])
    addr3 = format_mac(mac_frame[16:22])
    sa = addr2
    if ftype == 0:
        bssid = addr3
    elif to_ds == 0 and from_ds == 1:
        bssid = addr2
    elif to_ds == 1 and from_ds == 0:
        bssid = addr1
    else:
        bssid = addr3

    ssid = ""
    security = ""
    if ftype == 0 and fsub in (0, 4, 5, 8):
        ie_offset = 24 if fsub == 4 else (28 if fsub == 0 else 36)
        if fsub in (5, 8) and len(mac_frame) >= 36:
            cap_info = struct.unpack("<H", mac_frame[34:36])[0]
            security = "WPA/PRIV" if (cap_info & 0x0010) else "OPEN"
        pos = ie_offset
        while pos + 2 <= len(mac_frame):
            tag = mac_frame[pos]
            tag_len = mac_frame[pos + 1]
            if pos + 2 + tag_len > len(mac_frame):
                break
            val = mac_frame[pos + 2 : pos + 2 + tag_len]
            if tag == 0 and not ssid:
                ssid = val.decode("utf-8", errors="ignore").strip("\x00")
            elif tag == 3 and tag_len == 1 and channel == 0:
                channel = int(val[0])
            elif tag == 48:
                security = "WPA2"
            pos += 2 + tag_len

    frame_type_str = "mgmt" if ftype == 0 else ("data" if ftype == 2 else "other")
    subtype_str = SUBTYPE_NAMES.get((ftype, fsub), "data" if ftype == 2 else "mgmt")
    ts_iso = (
        datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()
        if timestamp > 1e8
        else datetime.now(timezone.utc).isoformat()
    )
    return {
        "node_id": "pcap_capture",
        "source": "pcap_upload",
        "timestamp": ts_iso,
        "ts_sec": round(timestamp, 4),
        "channel": channel or 6,
        "rssi": int(rssi),
        "frame_type": frame_type_str,
        "subtype": subtype_str,
        "sa": sa,
        "bssid": bssid,
        "ssid": ssid,
        "security": security,
        "rate": rate_mbps,
        "pkt_len": len(mac_frame),
        "randomized": is_randomized_mac(sa),
    }


def parse_csv_bytes(contents: bytes) -> list[dict[str, Any]]:
    text = contents.decode("utf-8", errors="replace")
    reader = csv.DictReader(io.StringIO(text))
    observations: list[dict[str, Any]] = []
    for idx, row in enumerate(reader):
        norm = {str(k or "").strip().lower(): str(v or "").strip() for k, v in row.items()}
        if not norm:
            continue
        rssi_raw = norm.get("rssi") or norm.get("signal") or norm.get("dbm") or "-65"
        ch_raw = norm.get("channel") or norm.get("ch") or "6"
        sa = (norm.get("sa") or norm.get("mac") or norm.get("source") or norm.get("bssid") or f"02:00:00:00:00:{idx % 250:02x}").lower()
        bssid = (norm.get("bssid") or sa).lower()
        subtype = norm.get("subtype") or norm.get("type") or "beacon"
        frame_type = norm.get("frame_type") or ("data" if subtype == "data" else "mgmt")
        observations.append(
            {
                "node_id": norm.get("node_id") or "csv_capture",
                "source": "csv_upload",
                "timestamp": norm.get("timestamp") or norm.get("ts") or "",
                "ts_sec": float(idx) * 0.2,
                "channel": _safe_int(ch_raw, 6),
                "rssi": _safe_int(rssi_raw, -65),
                "frame_type": frame_type,
                "subtype": subtype,
                "sa": sa,
                "bssid": bssid,
                "ssid": norm.get("ssid") or "",
                "security": norm.get("security") or "",
                "rate": _safe_float(norm.get("rate"), 0.0),
                "pkt_len": _safe_int(norm.get("pkt_len"), 64),
                "randomized": is_randomized_mac(sa),
            }
        )
    return observations


def parse_jsonl_bytes(contents: bytes) -> list[dict[str, Any]]:
    text = contents.decode("utf-8", errors="replace").strip()
    if not text:
        return []
    items: list[dict[str, Any]] = []
    if text.startswith("["):
        loaded = json.loads(text)
        raw_list = loaded if isinstance(loaded, list) else []
    else:
        raw_list = []
        for line in text.splitlines():
            line = line.strip()
            if not line or not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("type") == "status":
                continue
            if isinstance(obj.get("observations"), list):
                raw_list.extend(obj["observations"])
            else:
                raw_list.append(obj)

    for idx, obj in enumerate(raw_list):
        if not isinstance(obj, dict):
            continue
        sa = str(obj.get("sa") or obj.get("mac") or obj.get("bssid") or f"02:00:00:00:01:{idx % 250:02x}").lower()
        bssid = str(obj.get("bssid") or sa).lower()
        items.append(
            {
                "node_id": str(obj.get("node_id") or "jsonl_capture"),
                "source": str(obj.get("source") or "jsonl_upload"),
                "timestamp": str(obj.get("timestamp") or ""),
                "ts_sec": _safe_float(obj.get("ts_sec"), idx * 0.2),
                "channel": _safe_int(obj.get("channel"), 6),
                "rssi": _safe_int(obj.get("rssi"), -65),
                "frame_type": str(obj.get("frame_type") or "mgmt"),
                "subtype": str(obj.get("subtype") or "beacon"),
                "sa": sa,
                "bssid": bssid,
                "ssid": str(obj.get("ssid") or ""),
                "security": str(obj.get("security") or ""),
                "rate": _safe_float(obj.get("rate"), 0.0),
                "pkt_len": _safe_int(obj.get("pkt_len"), 64),
                "randomized": bool(obj.get("randomized", is_randomized_mac(sa))),
            }
        )
    return items


def slice_capture_into_frames(
    observations: list[dict[str, Any]],
    *,
    bucket_seconds: float = 1.0,
    max_frames: int = 30,
) -> list[list[dict[str, Any]]]:
    if not observations:
        return []
    ts_values = [float(o.get("ts_sec", 0.0)) for o in observations]
    min_ts = min(ts_values)
    max_ts = max(ts_values)
    if max_ts - min_ts <= 0.001:
        chunk_size = max(1, (len(observations) + max_frames - 1) // max(1, min(max_frames, len(observations))))
        return [observations[i : i + chunk_size] for i in range(0, len(observations), chunk_size)][:max_frames]

    step = max(0.25, bucket_seconds)
    buckets: dict[int, list[dict[str, Any]]] = {}
    for obs in observations:
        idx = int((float(obs.get("ts_sec", 0.0)) - min_ts) // step)
        buckets.setdefault(idx, []).append(obs)
    ordered = [buckets[k] for k in sorted(buckets.keys())]
    return ordered[:max_frames]


def _safe_int(val: Any, default: int) -> int:
    try:
        return int(float(str(val).strip()))
    except (ValueError, TypeError):
        return default


def _safe_float(val: Any, default: float) -> float:
    try:
        return float(str(val).strip())
    except (ValueError, TypeError):
        return default

