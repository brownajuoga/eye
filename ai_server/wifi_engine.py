from __future__ import annotations

from collections import Counter, deque
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import math
import random
import threading
import time
from typing import Any


FRAME_WIDTH = 640
FRAME_HEIGHT = 420


def _now_ts() -> float:
    return time.time()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _anon_tag(value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8", errors="ignore")).hexdigest()
    return f"anon:{digest[:2]}:{digest[2:4]}:{digest[4:6]}"


def _stable_angle(identifier: str, channel: int) -> float:
    digest = hashlib.md5(identifier.encode("utf-8", errors="ignore")).hexdigest()
    base = int(digest[:8], 16) / float(0xFFFFFFFF)
    ch_offset = ((channel % 13) / 13.0) * 0.45
    return (base * 2.0 * math.pi + ch_offset) % (2.0 * math.pi)


def rssi_to_distance_norm(rssi: int) -> float:
    # Map [-30 dBm .. -95 dBm] smoothly to normalized radius [0.10 .. 0.44]
    clamped = max(-95, min(-30, int(rssi)))
    frac = (-30 - clamped) / 65.0
    return round(0.10 + (frac ** 0.85) * 0.34, 4)


class WifiEngine:
    """Stateful RF signal-processing, WIDS, tripwire, occupancy, and spectrum engine."""

    def __init__(self, *, window_seconds: float = 45.0):
        self.window_seconds = window_seconds
        self._lock = threading.RLock()
        self._emitters: dict[str, dict[str, Any]] = {}
        self._recent_frames: deque[dict[str, Any]] = deque(maxlen=600)
        self._deauth_times: deque[float] = deque(maxlen=250)
        self._known_ssid_profiles: dict[str, dict[str, Any]] = {}
        self._waveform: deque[dict[str, Any]] = deque(maxlen=90)
        self._anchors: dict[str, dict[str, float]] = {
            "sensor": {"x": 0.50, "y": 0.68},
        }
        self._active_source_id: str = "standby"
        self._active_source_name: str = "Standby (No Live Source)"
        self._active_source_kind: str = "standby"
        self._replay_meta: dict[str, Any] | None = None
        self._last_alerts: deque[dict[str, Any]] = deque(maxlen=40)
        self._total_packets = 0

    def reset_state(self) -> None:
        with self._lock:
            self._emitters.clear()
            self._recent_frames.clear()
            self._deauth_times.clear()
            self._known_ssid_profiles.clear()
            self._waveform.clear()
            self._last_alerts.clear()
            self._replay_meta = None
            self._total_packets = 0

    def update_anchors(self, anchors: dict[str, dict[str, Any]]) -> dict[str, dict[str, float]]:
        with self._lock:
            for key, pos in anchors.items():
                if not isinstance(pos, dict):
                    continue
                x = max(0.05, min(0.95, float(pos.get("x", 0.5))))
                y = max(0.08, min(0.88, float(pos.get("y", 0.5))))
                self._anchors[str(key)] = {"x": round(x, 4), "y": round(y, 4)}
            return deepcopy(self._anchors)

    def set_replay_meta(self, meta: dict[str, Any] | None) -> None:
        with self._lock:
            self._replay_meta = deepcopy(meta) if meta else None

    def ingest_batch(
        self,
        observations: list[dict[str, Any]],
        *,
        policy: dict[str, Any],
        source_id: str = "wifi",
        source_name: str = "Wi-Fi Sensor",
        source_kind: str = "live",
        replay_meta: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        wifi_cfg = policy.get("wifi", {})
        wifi_mode = str(wifi_cfg.get("mode", "multi")).lower()
        privacy_mode = bool(wifi_cfg.get("privacy_mode", False))
        tripwire_z_thresh = float(wifi_cfg.get("tripwire_z_threshold", 2.1))
        deauth_thresh = int(wifi_cfg.get("deauth_rate_threshold", 5))
        known_aps = wifi_cfg.get("known_aps", {}) or {}

        now = _now_ts()
        with self._lock:
            self._active_source_id = source_id
            self._active_source_name = source_name
            self._active_source_kind = source_kind
            if replay_meta is not None:
                self._replay_meta = deepcopy(replay_meta)

            # Prune expired frames & stale emitters
            cutoff = now - self.window_seconds
            while self._recent_frames and self._recent_frames[0]["ts"] < cutoff:
                self._recent_frames.popleft()
            while self._deauth_times and self._deauth_times[0] < (now - 12.0):
                self._deauth_times.popleft()

            batch_deauths = 0
            batch_canary = 0
            evil_twins: list[dict[str, Any]] = []
            primary_link_rssi: int | None = None
            primary_link_baseline: float | None = None
            max_disturbance = 0.0

            for raw in observations:
                self._total_packets += 1
                rssi = max(-100, min(-15, int(raw.get("rssi", -65))))
                channel = int(raw.get("channel", 6) or 6)
                frame_type = str(raw.get("frame_type", "mgmt")).lower()
                subtype = str(raw.get("subtype", "beacon")).lower()
                sa = str(raw.get("sa") or raw.get("mac") or raw.get("bssid") or "02:00:00:00:00:01").lower()
                bssid = str(raw.get("bssid") or sa).lower()
                ssid = str(raw.get("ssid") or "").strip()
                security = str(raw.get("security") or "").strip()
                rate = float(raw.get("rate", 0.0) or 0.0)
                randomized = bool(raw.get("randomized", False))
                in_use = bool(raw.get("in_use", False))

                is_ap = subtype in {"beacon", "probe_resp", "canary_ap"} or (in_use and sa == bssid)
                is_threat_frame = subtype in {"deauth", "disassoc", "canary_probe", "canary_assoc"}

                if subtype in {"deauth", "disassoc"}:
                    self._deauth_times.append(now)
                    batch_deauths += 1
                if subtype in {"canary_probe", "canary_assoc"}:
                    batch_canary += 1

                # Evil Twin check for AP beacons / probe responses
                if is_ap and ssid:
                    twin = self._check_evil_twin(
                        ssid=ssid,
                        bssid=bssid,
                        security=security,
                        rssi=rssi,
                        channel=channel,
                        known_aps=known_aps,
                    )
                    if twin:
                        evil_twins.append(twin)

                emitter_key = f"ap:{bssid}" if is_ap else f"sta:{sa}"
                state = self._emitters.get(emitter_key)
                if state is None:
                    angle = _stable_angle(emitter_key, channel)
                    state = {
                        "id": emitter_key,
                        "anon_id": _anon_tag(emitter_key),
                        "raw_mac": sa,
                        "bssid": bssid,
                        "ssid": ssid,
                        "security": security,
                        "category": "ap" if is_ap else "client",
                        "randomized": randomized,
                        "in_use": in_use,
                        "channel": channel,
                        "angle": angle,
                        "rssi": rssi,
                        "ewma_rssi": float(rssi),
                        "ewma_var": 2.0,
                        "z_score": 0.0,
                        "disturbance": 0.0,
                        "packet_count": 0,
                        "recent_times": deque(maxlen=40),
                        "threat": None,
                        "last_seen": now,
                        "rate": rate,
                    }
                    self._emitters[emitter_key] = state
                else:
                    # Update signal dynamics
                    prev_ewma = float(state["ewma_rssi"])
                    delta = float(rssi) - prev_ewma
                    std = max(1.6, math.sqrt(max(1.0, float(state["ewma_var"]))))
                    z = abs(delta) / std
                    state["ewma_rssi"] = prev_ewma * 0.84 + float(rssi) * 0.16
                    state["ewma_var"] = float(state["ewma_var"]) * 0.85 + (delta * delta) * 0.15
                    state["z_score"] = round(z, 3)
                    # Instantaneous disturbance normalized [0..1]
                    inst_dist = min(1.0, (z / max(1.5, tripwire_z_thresh * 1.45)) * 0.75 + (abs(delta) / 18.0) * 0.25)
                    state["disturbance"] = round(max(float(state["disturbance"]) * 0.55, inst_dist), 3)
                    state["rssi"] = rssi
                    state["channel"] = channel or state["channel"]
                    if ssid:
                        state["ssid"] = ssid
                    if security:
                        state["security"] = security
                    if rate > 0:
                        state["rate"] = rate
                    if in_use:
                        state["in_use"] = True
                    state["last_seen"] = now

                state["packet_count"] += 1
                state["recent_times"].append(now)

                if is_threat_frame:
                    state["threat"] = subtype
                    state["disturbance"] = max(float(state["disturbance"]), 0.92)
                elif evil_twins and any(t["bssid"] == bssid for t in evil_twins):
                    state["threat"] = "evil_twin"
                    state["disturbance"] = 1.0
                elif float(state["disturbance"]) < 0.25 and state.get("threat") not in {"deauth", "disassoc", "evil_twin"}:
                    state["threat"] = None

                if state["in_use"] or (primary_link_rssi is None and state["category"] == "ap"):
                    primary_link_rssi = rssi
                    primary_link_baseline = float(state["ewma_rssi"])

                max_disturbance = max(max_disturbance, float(state["disturbance"]))
                self._recent_frames.append(
                    {
                        "ts": now,
                        "channel": channel,
                        "rssi": rssi,
                        "subtype": subtype,
                        "frame_type": frame_type,
                        "emitter_key": emitter_key,
                        "rate": rate,
                        "is_ap": is_ap,
                    }
                )

            # Remove very stale non-pinned emitters (> window_seconds)
            stale_keys = [
                k for k, v in self._emitters.items()
                if (now - float(v["last_seen"])) > self.window_seconds and not v.get("in_use")
            ]
            for k in stale_keys:
                del self._emitters[k]

            # Record oscilloscope waveform sample
            if primary_link_rssi is None and observations:
                primary_link_rssi = int(sum(int(o.get("rssi", -65)) for o in observations) / len(observations))
                primary_link_baseline = float(primary_link_rssi)
            if primary_link_rssi is not None:
                self._waveform.append(
                    {
                        "ts": now,
                        "rssi": primary_link_rssi,
                        "baseline": round(primary_link_baseline or primary_link_rssi, 2),
                        "disturbance": round(max_disturbance, 3),
                    }
                )

            snapshot = self._build_snapshot_locked(
                now=now,
                wifi_mode=wifi_mode,
                privacy_mode=privacy_mode,
                tripwire_z_thresh=tripwire_z_thresh,
                deauth_thresh=deauth_thresh,
                batch_deauths=batch_deauths,
                batch_canary=batch_canary,
                evil_twins=evil_twins,
            )
            return snapshot

    def _check_evil_twin(
        self,
        *,
        ssid: str,
        bssid: str,
        security: str,
        rssi: int,
        channel: int,
        known_aps: dict[str, Any],
    ) -> dict[str, Any] | None:
        # Explicit watchlist check first
        trusted = known_aps.get(ssid)
        if trusted:
            allowed_bssids = [str(x).lower() for x in (trusted if isinstance(trusted, list) else [trusted])]
            if bssid not in allowed_bssids:
                return {
                    "type": "evil_twin",
                    "ssid": ssid,
                    "bssid": bssid,
                    "expected_bssids": allowed_bssids,
                    "rssi": rssi,
                    "channel": channel,
                }
            return None

        # Dynamic baseline twin check
        profile = self._known_ssid_profiles.get(ssid)
        if profile is None:
            self._known_ssid_profiles[ssid] = {
                "bssids": {bssid},
                "security": security,
            }
            return None

        prev_security = str(profile.get("security", ""))
        if security and prev_security and security != prev_security and bssid not in profile["bssids"]:
            return {
                "type": "evil_twin",
                "ssid": ssid,
                "bssid": bssid,
                "expected_security": prev_security,
                "observed_security": security,
                "rssi": rssi,
                "channel": channel,
            }
        profile["bssids"].add(bssid)
        return None

    def _build_snapshot_locked(
        self,
        *,
        now: float,
        wifi_mode: str,
        privacy_mode: bool,
        tripwire_z_thresh: float,
        deauth_thresh: int,
        batch_deauths: int,
        batch_canary: int,
        evil_twins: list[dict[str, Any]],
    ) -> dict[str, Any]:
        cutoff_active = now - 15.0
        sensor_anchor = self._anchors.get("sensor", {"x": 0.50, "y": 0.68})
        sx, sy = sensor_anchor["x"], sensor_anchor["y"]

        entities: list[dict[str, Any]] = []
        links: list[dict[str, Any]] = []
        active_clients = 0
        active_aps = 0
        ap_disturbances: list[float] = []
        max_z = 0.0
        probe_bursts = 0

        for key, st in self._emitters.items():
            age = now - float(st["last_seen"])
            if age > self.window_seconds:
                continue
            recent_hits = sum(1 for t in st["recent_times"] if t >= cutoff_active)
            pps = round(recent_hits / 15.0, 2)
            fade = max(0.25, 1.0 - (age / self.window_seconds) * 0.75)

            if key in self._anchors:
                px = self._anchors[key]["x"]
                py = self._anchors[key]["y"]
            else:
                dist = rssi_to_distance_norm(int(st["rssi"]))
                ang = float(st["angle"])
                px = max(0.06, min(0.94, sx + dist * math.cos(ang)))
                py = max(0.08, min(0.86, sy + dist * math.sin(ang) * 0.78))

            disturbance = float(st["disturbance"])
            z_score = float(st["z_score"])
            max_z = max(max_z, z_score)

            if st["category"] == "ap":
                active_aps += 1
                ap_disturbances.append(disturbance)
            else:
                active_clients += 1
                if recent_hits >= 3:
                    probe_bursts += 1

            display_label = st["anon_id"] if privacy_mode else (st["ssid"] or st["raw_mac"][-8:])
            entity = {
                "id": st["anon_id"] if privacy_mode else key,
                "raw_key": key,
                "label": display_label,
                "bssid": st["anon_id"] if privacy_mode else st["bssid"],
                "ssid": "" if (privacy_mode and st["category"] != "ap") else st["ssid"],
                "security": st["security"],
                "category": "threat" if st.get("threat") else st["category"],
                "threat": st.get("threat"),
                "channel": st["channel"],
                "rssi": st["rssi"],
                "ewma_rssi": round(float(st["ewma_rssi"]), 1),
                "z_score": z_score,
                "disturbance": disturbance,
                "pps": pps,
                "randomized": bool(st["randomized"]),
                "in_use": bool(st["in_use"]),
                "fade": round(fade, 2),
                "x": round(px, 4),
                "y": round(py, 4),
            }
            entities.append(entity)

            if st["category"] == "ap" or st["in_use"]:
                links.append(
                    {
                        "id": f"link:{entity['id']}",
                        "from_x": sx,
                        "from_y": sy,
                        "to_x": entity["x"],
                        "to_y": entity["y"],
                        "label": entity["label"],
                        "rssi": st["rssi"],
                        "disturbance": disturbance,
                        "crossing": z_score >= tripwire_z_thresh or disturbance >= 0.62,
                    }
                )

        # Channel spectrum 1..13 utilization + overlap interference
        ch_counts: Counter[int] = Counter()
        ch_ap_counts: Counter[int] = Counter()
        ch_rssi: dict[int, list[int]] = {}
        slow_frames = 0
        for f in self._recent_frames:
            ch = int(f.get("channel") or 0)
            if 1 <= ch <= 13:
                ch_counts[ch] += 1
                if f.get("is_ap"):
                    ch_ap_counts[ch] += 1
                ch_rssi.setdefault(ch, []).append(int(f.get("rssi", -75)))
            rate = float(f.get("rate") or 0.0)
            if 0 < rate <= 5.5:
                slow_frames += 1

        max_ch_hits = max(ch_counts.values(), default=1)
        channels: list[dict[str, Any]] = []
        peak_congestion = 0.0
        best_channel = 1
        best_score = 999.0
        for ch in range(1, 14):
            direct = ch_counts.get(ch, 0)
            overlap = sum(
                ch_counts.get(other, 0) * (1.0 - abs(ch - other) * 0.25)
                for other in range(max(1, ch - 3), min(14, ch + 4))
                if other != ch
            )
            congestion = min(1.0, (direct + overlap * 0.5) / max(8.0, float(max_ch_hits) * 1.35))
            peak_congestion = max(peak_congestion, congestion)
            mean_rssi = round(sum(ch_rssi[ch]) / len(ch_rssi[ch]), 1) if ch in ch_rssi else -95.0
            channels.append(
                {
                    "channel": ch,
                    "frames": direct,
                    "ap_count": ch_ap_counts.get(ch, 0),
                    "congestion": round(congestion, 3),
                    "mean_rssi": mean_rssi,
                }
            )
            if ch in (1, 6, 11):
                score = direct + overlap * 0.6
                if score < best_score:
                    best_score = score
                    best_channel = ch

        # Aggregate domain signals & alerts
        deauth_count_12s = len(self._deauth_times)
        avg_disturbance = round(max(ap_disturbances or [0.0]), 3)
        tripwire_triggered = any(link["crossing"] for link in links) or max_z >= tripwire_z_thresh

        # Occupancy estimation combines non-AP active clients + RF disturbance activity
        client_contrib = active_clients
        motion_contrib = 1 if (tripwire_triggered and client_contrib == 0) else 0
        occ_count = client_contrib + motion_contrib
        density_level = (
            "empty" if occ_count == 0 else ("low" if occ_count <= 2 else ("moderate" if occ_count <= 5 else "crowded"))
        )

        # Unique SSIDs seen recently (beacon spam indicator)
        recent_ssids = {str(st.get("ssid", "")) for st in self._emitters.values() if st.get("ssid")}
        beacon_spam = len(recent_ssids) >= 25

        detections = self._build_detections(
            entities=entities,
            tripwire_triggered=tripwire_triggered,
            avg_disturbance=avg_disturbance,
            max_z=max_z,
            deauth_count=deauth_count_12s,
            deauth_thresh=deauth_thresh,
            batch_canary=batch_canary,
            evil_twins=evil_twins,
            beacon_spam=beacon_spam,
            peak_congestion=peak_congestion,
            occ_count=occ_count,
            probe_bursts=probe_bursts,
            slow_frames=slow_frames,
            wifi_mode=wifi_mode,
        )

        alerts: list[dict[str, Any]] = []
        for det in detections:
            if det["label"] in {
                "deauth_flood",
                "evil_twin",
                "rssi_tripwire_motion",
                "canary_hit",
                "beacon_spam",
                "channel_congestion",
            }:
                alerts.append(
                    {
                        "timestamp": _now_iso(),
                        "type": det["label"],
                        "confidence": det["confidence"],
                        "reason": det.get("reason", det["label"]),
                    }
                )
        for al in alerts:
            self._last_alerts.append(al)

        vision = {
            "timestamp": _now_iso(),
            "frame_size": {"width": FRAME_WIDTH, "height": FRAME_HEIGHT},
            "source_id": self._active_source_id,
            "source_name": self._active_source_name,
            "source_kind": self._active_source_kind,
            "mode": wifi_mode,
            "privacy_mode": privacy_mode,
            "sensor": {"x": sx, "y": sy},
            "entities": entities[:48],
            "links": links,
            "channels": channels,
            "waveform": list(self._waveform),
            "occupancy": {
                "estimate": occ_count,
                "density": density_level,
                "active_clients": active_clients,
                "active_aps": active_aps,
            },
            "metrics": {
                "total_packets": self._total_packets,
                "recent_packets_45s": len(self._recent_frames),
                "deauth_12s": deauth_count_12s,
                "disturbance": avg_disturbance,
                "max_z_score": round(max_z, 2),
                "tripwire_triggered": tripwire_triggered,
                "peak_congestion": round(peak_congestion, 3),
                "recommended_channel": best_channel,
                "slow_legacy_frames": slow_frames,
            },
            "alerts": list(self._last_alerts)[-10:],
            "alert_banner": alerts[0]["reason"] if alerts else "",
            "replay": self._replay_meta,
        }

        return {
            "vision": vision,
            "detections": detections,
        }

    def _build_detections(
        self,
        *,
        entities: list[dict[str, Any]],
        tripwire_triggered: bool,
        avg_disturbance: float,
        max_z: float,
        deauth_count: int,
        deauth_thresh: int,
        batch_canary: int,
        evil_twins: list[dict[str, Any]],
        beacon_spam: bool,
        peak_congestion: float,
        occ_count: int,
        probe_bursts: int,
        slow_frames: int,
        wifi_mode: str,
    ) -> list[dict[str, Any]]:
        detections: list[dict[str, Any]] = []

        def to_box(cx_norm: float, cy_norm: float, radius_px: int = 36) -> list[int]:
            cx = int(cx_norm * FRAME_WIDTH)
            cy = int(cy_norm * FRAME_HEIGHT)
            return [
                max(0, cx - radius_px),
                max(0, cy - radius_px),
                min(FRAME_WIDTH, cx + radius_px),
                min(FRAME_HEIGHT, cy + radius_px),
            ]

        if deauth_count >= deauth_thresh:
            conf = round(min(0.99, 0.72 + (deauth_count - deauth_thresh) * 0.04), 3)
            detections.append(
                {
                    "label": "deauth_flood",
                    "confidence": conf,
                    "box": to_box(0.5, 0.5, 90),
                    "model": "wifi_wids_engine",
                    "track_id": 9001,
                    "reason": f"Deauth/Disassoc flood detected ({deauth_count} frames in 12s)",
                }
            )

        for twin in evil_twins:
            detections.append(
                {
                    "label": "evil_twin",
                    "confidence": 0.94,
                    "box": to_box(0.5, 0.35, 70),
                    "model": "wifi_wids_engine",
                    "track_id": 9002,
                    "reason": f"Possible Evil Twin AP for SSID '{twin['ssid']}' ({twin['bssid']})",
                }
            )

        if batch_canary > 0:
            detections.append(
                {
                    "label": "canary_hit",
                    "confidence": 0.96,
                    "box": to_box(0.5, 0.65, 60),
                    "model": "wifi_wids_engine",
                    "track_id": 9003,
                    "reason": "Device probed or associated with Canary decoy AP",
                }
            )

        if beacon_spam:
            detections.append(
                {
                    "label": "beacon_spam",
                    "confidence": 0.88,
                    "box": to_box(0.5, 0.25, 110),
                    "model": "wifi_wids_engine",
                    "track_id": 9004,
                    "reason": "Abnormal surge in unique SSIDs (possible beacon spam)",
                }
            )

        if tripwire_triggered:
            conf = round(min(0.97, 0.58 + avg_disturbance * 0.38), 3)
            detections.append(
                {
                    "label": "rssi_tripwire_motion",
                    "confidence": conf,
                    "box": to_box(0.5, 0.52, 85),
                    "model": "wifi_rssi_tripwire",
                    "track_id": 9010,
                    "reason": f"RF link disturbance / motion crossing (z={max_z:.2f}, energy={avg_disturbance:.2f})",
                }
            )

        if occ_count > 0:
            detections.append(
                {
                    "label": "occupancy_present",
                    "confidence": round(min(0.95, 0.55 + occ_count * 0.08), 3),
                    "box": to_box(0.5, 0.62, 65),
                    "model": "wifi_occupancy_estimator",
                    "track_id": 9020,
                    "reason": f"Estimated room RF occupancy: {occ_count} active device(s)/signatures",
                }
            )

        if probe_bursts > 0:
            detections.append(
                {
                    "label": "probe_burst",
                    "confidence": round(min(0.9, 0.6 + probe_bursts * 0.08), 3),
                    "box": to_box(0.45, 0.45, 55),
                    "model": "wifi_probe_tracker",
                    "track_id": 9025,
                    "reason": f"{probe_bursts} active client probe bursts detected",
                }
            )

        if peak_congestion >= 0.72:
            detections.append(
                {
                    "label": "channel_congestion",
                    "confidence": round(min(0.96, peak_congestion), 3),
                    "box": to_box(0.5, 0.2, 100),
                    "model": "wifi_spectrum_analyzer",
                    "track_id": 9030,
                    "reason": f"2.4 GHz channel congestion high ({int(peak_congestion * 100)}%, legacy frames={slow_frames})",
                }
            )

        # Include top tracked emitters as standard bounding boxes for night-vision overlays
        for idx, ent in enumerate(entities[:6]):
            label = "rogue_ap" if ent.get("threat") else ("wifi_ap" if ent["category"] == "ap" else "wifi_client")
            conf = round(max(0.4, min(0.99, (100 + int(ent["rssi"])) / 70.0)), 3)
            detections.append(
                {
                    "label": label,
                    "confidence": conf,
                    "box": to_box(float(ent["x"]), float(ent["y"]), 26),
                    "model": f"wifi_{wifi_mode}",
                    "track_id": idx + 1,
                    "reason": f"{ent['label']} Ch{ent['channel']} {ent['rssi']}dBm",
                }
            )

        return detections

    def get_vision_state(self, policy: dict[str, Any]) -> dict[str, Any]:
        wifi_cfg = policy.get("wifi", {})
        with self._lock:
            return self._build_snapshot_locked(
                now=_now_ts(),
                wifi_mode=str(wifi_cfg.get("mode", "multi")).lower(),
                privacy_mode=bool(wifi_cfg.get("privacy_mode", False)),
                tripwire_z_thresh=float(wifi_cfg.get("tripwire_z_threshold", 2.1)),
                deauth_thresh=int(wifi_cfg.get("deauth_rate_threshold", 5)),
                batch_deauths=0,
                batch_canary=0,
                evil_twins=[],
            )["vision"]

    def generate_sim_observations(self, *, scenario: str, tick: int) -> list[dict[str, Any]]:
        rng = random.Random(tick * 7919 + hash(scenario))
        motion_wave = 0.0
        if scenario == "motion" or (scenario == "mixed" and (tick % 16 in (5, 6, 7, 8, 9))):
            motion_wave = -15.0 * abs(math.sin(tick * 0.85)) - rng.uniform(2, 6)

        obs: list[dict[str, Any]] = [
            {
                "node_id": "nodemcu-sim",
                "source": "simulator",
                "channel": 6,
                "rssi": int(round(-43 + motion_wave + rng.uniform(-1, 1))),
                "frame_type": "mgmt",
                "subtype": "beacon",
                "sa": "50:14:c1:e3:76:1c",
                "bssid": "50:14:c1:e3:76:1c",
                "ssid": "Home_Core_AP",
                "security": "WPA2",
                "rate": 130.0,
                "in_use": True,
            },
            {
                "node_id": "nodemcu-sim",
                "source": "simulator",
                "channel": 11,
                "rssi": int(round(-62 + rng.uniform(-2, 2))),
                "frame_type": "mgmt",
                "subtype": "beacon",
                "sa": "8a:74:77:60:13:d4",
                "bssid": "8a:74:77:60:13:d4",
                "ssid": "Studio_Mesh",
                "security": "WPA2",
                "rate": 72.0,
            },
        ]

        if scenario != "quiet":
            obs.append(
                {
                    "node_id": "nodemcu-sim",
                    "source": "simulator",
                    "channel": 6,
                    "rssi": int(round(-54 + motion_wave * 0.5 + rng.uniform(-3, 3))),
                    "frame_type": "mgmt",
                    "subtype": "probe_req",
                    "sa": "da:a1:19:11:22:33",
                    "bssid": "ff:ff:ff:ff:ff:ff",
                    "ssid": "Home_Core_AP",
                    "randomized": True,
                    "rate": 24.0,
                }
            )

        if scenario in ("crowd", "mixed"):
            client_count = 6 if scenario == "crowd" else 3
            for i in range(client_count):
                obs.append(
                    {
                        "node_id": "nodemcu-sim",
                        "source": "simulator",
                        "channel": [1, 6, 11][i % 3],
                        "rssi": int(-58 - i * 4 + rng.uniform(-3, 3)),
                        "frame_type": "mgmt",
                        "subtype": "probe_req",
                        "sa": f"f2:8b:40:0{i}:12:{20 + i:02x}",
                        "bssid": "ff:ff:ff:ff:ff:ff",
                        "randomized": True,
                        "rate": 12.0,
                    }
                )

        if scenario == "congestion":
            for i in range(12):
                obs.append(
                    {
                        "node_id": "nodemcu-sim",
                        "source": "simulator",
                        "channel": 6 if i < 9 else 7,
                        "rssi": int(-52 - (i % 4) * 5),
                        "frame_type": "data",
                        "subtype": "data",
                        "sa": f"00:11:22:33:44:{10 + i:02x}",
                        "bssid": "50:14:c1:e3:76:1c",
                        "rate": 2.0,
                    }
                )

        if scenario == "deauth" or (scenario == "mixed" and tick % 20 in (15, 16)):
            for _ in range(7):
                obs.append(
                    {
                        "node_id": "nodemcu-sim",
                        "source": "simulator",
                        "channel": 6,
                        "rssi": int(-46 + rng.uniform(-2, 2)),
                        "frame_type": "mgmt",
                        "subtype": "deauth",
                        "sa": "de:ad:be:ef:00:99",
                        "bssid": "50:14:c1:e3:76:1c",
                        "ssid": "Home_Core_AP",
                    }
                )

        if scenario == "evil_twin" or (scenario == "mixed" and tick % 24 == 21):
            obs.append(
                {
                    "node_id": "nodemcu-sim",
                    "source": "simulator",
                    "channel": 6,
                    "rssi": -38,
                    "frame_type": "mgmt",
                    "subtype": "beacon",
                    "sa": "66:77:88:99:aa:bb",
                    "bssid": "66:77:88:99:aa:bb",
                    "ssid": "Home_Core_AP",
                    "security": "OPEN",
                    "rate": 54.0,
                }
            )

        return obs

