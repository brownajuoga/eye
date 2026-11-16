from __future__ import annotations

import math
from typing import Any


# Curated 3-byte OUI prefix lookup for common router, phone, laptop, IoT, media, and drone vendors
OUI_VENDORS: dict[str, tuple[str, str]] = {
    # Routers / AP Infrastructure
    "50:14:c1": ("Huawei / ISP Router", "wifi_ap"),
    "8a:74:77": ("Mesh / ISP AP", "wifi_ap"),
    "5c:7d:ae": ("Huawei / AP", "wifi_ap"),
    "ec:fa:bc": ("Espressif IoT / NodeMCU", "iot_device"),
    "24:6f:28": ("Espressif IoT", "iot_device"),
    "30:ae:a4": ("Espressif IoT", "iot_device"),
    "84:f3:eb": ("Espressif IoT", "iot_device"),
    "a4:cf:12": ("Espressif IoT", "iot_device"),
    "b4:e6:2d": ("Espressif IoT", "iot_device"),
    "c4:4f:33": ("Espressif IoT", "iot_device"),
    "dc:4f:22": ("Espressif IoT", "iot_device"),
    "14:cc:20": ("TP-Link", "wifi_ap"),
    "50:c7:bf": ("TP-Link", "wifi_ap"),
    "c0:25:e9": ("TP-Link", "wifi_ap"),
    "e8:de:27": ("TP-Link", "wifi_ap"),
    "f4:f2:6d": ("TP-Link", "wifi_ap"),
    "c8:3a:35": ("Tenda", "wifi_ap"),
    "d8:32:14": ("Tenda", "wifi_ap"),
    "04:95:e6": ("Tenda", "wifi_ap"),
    "24:a4:3c": ("Ubiquiti", "wifi_ap"),
    "78:8a:20": ("Ubiquiti", "wifi_ap"),
    "fc:ec:da": ("Ubiquiti", "wifi_ap"),
    "4c:5e:0c": ("MikroTik", "wifi_ap"),
    "64:d1:54": ("MikroTik", "wifi_ap"),
    "dc:2c:6e": ("MikroTik", "wifi_ap"),
    # Smartphones & Mobile
    "da:a1:19": ("Android Mobile", "smartphone"),
    "f2:8b:40": ("Mobile Handset", "smartphone"),
    "00:1c:b3": ("Apple", "smartphone"),
    "3c:15:c2": ("Apple", "smartphone"),
    "40:cb:c0": ("Apple", "smartphone"),
    "ac:bc:32": ("Apple", "laptop_pc"),
    "f0:18:98": ("Apple", "laptop_pc"),
    "28:6a:b8": ("Samsung", "smartphone"),
    "50:01:d9": ("Samsung", "smartphone"),
    "78:47:1d": ("Samsung", "smartphone"),
    "dc:71:96": ("Samsung", "smartphone"),
    "64:a2:f9": ("OnePlus / Oppo", "smartphone"),
    "94:65:2d": ("OnePlus", "smartphone"),
    "2c:d0:66": ("Xiaomi", "smartphone"),
    "64:cc:2e": ("Xiaomi", "smartphone"),
    "7c:1d:d9": ("Xiaomi", "smartphone"),
    # PCs / Laptops
    "44:1c:a8": ("Laptop Wi-Fi NIC", "laptop_pc"),
    "00:1b:21": ("Intel PC NIC", "laptop_pc"),
    "3c:97:0e": ("Intel PC NIC", "laptop_pc"),
    "68:05:ca": ("Intel PC NIC", "laptop_pc"),
    "8c:8d:28": ("Intel PC NIC", "laptop_pc"),
    "a4:34:d9": ("Intel PC NIC", "laptop_pc"),
    "f8:63:3f": ("Intel PC NIC", "laptop_pc"),
    "00:e0:4c": ("Realtek PC NIC", "laptop_pc"),
    "48:5d:60": ("AzureWave PC NIC", "laptop_pc"),
    "f0:d5:bf": ("Intel Laptop", "laptop_pc"),
    # Drones & Vehicles
    "60:60:1f": ("DJI Drone", "vehicle_drone"),
    "34:d2:62": ("DJI Drone", "vehicle_drone"),
    "48:1c:b9": ("DJI Drone", "vehicle_drone"),
    "90:03:b7": ("Parrot Drone", "vehicle_drone"),
}

CLASS_LABELS: dict[str, str] = {
    "human_moving": "Human (Moving)",
    "human_stationary": "Human (Present)",
    "human_rapid_motion": "Human (Rapid Motion)",
    "smartphone": "Smartphone",
    "laptop_pc": "Laptop / PC",
    "smart_tv_media": "Smart TV / Media",
    "iot_device": "IoT / Smart Device",
    "wifi_ap": "Wi-Fi Router / AP",
    "vehicle_drone": "Vehicle / Drone RF",
    "physical_obstruction": "Door / Object Obstruction",
    "threat": "WIDS Threat Emitter",
    "unknown_device": "Wireless Device",
}


def rssi_to_meters(rssi: float, *, tx_power_1m: float = -41.0, path_loss_n: float = 2.55) -> float:
    """Estimate radial distance in meters from 2.4 GHz RSSI using log-distance path loss."""
    clamped = max(-96.0, min(-22.0, float(rssi)))
    meters = 10.0 ** ((tx_power_1m - clamped) / (10.0 * path_loss_n))
    return round(max(0.3, min(35.0, meters)), 1)


def classify_rf_emitter(state: dict[str, Any]) -> dict[str, Any]:
    """Classify a tracked Wi-Fi emitter into a physical object/device category with distance & mobility."""
    raw_mac = str(state.get("raw_mac") or state.get("bssid") or "").lower()
    oui = raw_mac[:8]
    ssid = str(state.get("ssid") or "").strip()
    ssid_low = ssid.lower()
    is_ap = state.get("category") == "ap"
    randomized = bool(state.get("randomized", False))
    rate = float(state.get("rate") or 0.0)
    rssi = float(state.get("rssi", -70))
    ewma_rssi = float(state.get("ewma_rssi", rssi))
    disturbance = float(state.get("disturbance", 0.0))
    z_score = float(state.get("z_score", 0.0))
    threat = state.get("threat")
    subtypes = state.get("subtypes") or set()

    vendor_name, oui_class = OUI_VENDORS.get(oui, ("", ""))

    # 1. Determine object class from OUI, SSID keywords, frame subtypes, and MAC randomization
    if threat:
        obj_class = "threat"
    elif any(k in ssid_low for k in ("dji", "tello", "mavic", "gopro", "70mai", "dashcam", "carplay", "tesla", "uconnect")):
        obj_class = "vehicle_drone"
        if not vendor_name:
            vendor_name = "Vehicle / Drone RF"
    elif any(k in ssid_low for k in ("bravia", "chromecast", "roku", "webos", "firetv", "samsung_tv", "direct-")):
        obj_class = "smart_tv_media"
        if not vendor_name:
            vendor_name = "Smart Display / Direct"
    elif any(k in ssid_low for k in ("ipc", "cam", "esp_", "tuya", "sonoff", "shelly", "wyze", "hikvision", "printer", "hp-")):
        obj_class = "iot_device"
        if not vendor_name:
            vendor_name = "IoT / Embedded"
    elif any(k in ssid_low for k in ("iphone", "galaxy", "pixel", "android", "oneplus", "redmi", "tecno", "infinix")):
        obj_class = "smartphone"
        if not vendor_name:
            vendor_name = "Mobile Hotspot"
    elif is_ap:
        obj_class = oui_class if oui_class in {"iot_device", "vehicle_drone", "smart_tv_media"} else "wifi_ap"
        if not vendor_name:
            vendor_name = "2.4 GHz AP" if not randomized else "SoftAP / Hotspot"
    elif oui_class:
        obj_class = oui_class
    elif randomized:
        obj_class = "smartphone"
        vendor_name = "Mobile (Randomized MAC)"
    elif rate >= 54.0 or "qos_data" in subtypes:
        obj_class = "laptop_pc"
        vendor_name = vendor_name or "High-Rate Client"
    elif "probe_req" in subtypes or "null_data" in subtypes:
        obj_class = "smartphone"
        vendor_name = vendor_name or "Mobile Client"
    else:
        obj_class = "unknown_device"
        vendor_name = vendor_name or "Wi-Fi Transceiver"

    distance_m = rssi_to_meters(ewma_rssi)
    delta_db = abs(rssi - ewma_rssi)
    if z_score >= 2.6 or delta_db >= 9.0:
        mobility = "fast_moving"
    elif z_score >= 1.4 or disturbance >= 0.35 or delta_db >= 4.0:
        mobility = "moving"
    else:
        mobility = "stationary"

    return {
        "object_class": obj_class,
        "object_label": CLASS_LABELS.get(obj_class, "Wireless Device"),
        "vendor": vendor_name,
        "distance_m": distance_m,
        "mobility": mobility,
    }


def infer_humans_and_obstructions(
    *,
    entities: list[dict[str, Any]],
    links: list[dict[str, Any]],
    emitters_state: dict[str, dict[str, Any]],
    sensor_x: float,
    sensor_y: float,
    tripwire_z_thresh: float,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """
    Synthesizes spatial Human (`human_moving`, `human_stationary`, `human_rapid_motion`)
    and Physical Obstruction (`physical_obstruction`) entities + detections from RF field state.
    """
    inferred_entities: list[dict[str, Any]] = []
    inferred_detections: list[dict[str, Any]] = []

    # 1. Detect Moving Humans & Rapid Motion across disturbed Fresnel links
    for idx, link in enumerate(links):
        dist = float(link.get("disturbance", 0.0))
        crossing = bool(link.get("crossing", False))
        if not crossing and dist < 0.38:
            continue

        fx, fy = float(link.get("from_x", sensor_x)), float(link.get("from_y", sensor_y))
        tx, ty = float(link.get("to_x", 0.5)), float(link.get("to_y", 0.3))
        # Place inferred human along the Fresnel zone between sensor and anchor AP
        hx = round(fx * 0.54 + tx * 0.46, 4)
        hy = round(fy * 0.54 + ty * 0.46, 4)
        rssi = int(link.get("rssi", -60))
        human_dist_m = round(max(0.4, rssi_to_meters(rssi) * 0.52), 1)

        is_rapid = dist >= 0.85
        h_class = "human_rapid_motion" if is_rapid else "human_moving"
        h_label = "Human (Rapid Motion)" if is_rapid else "Human (Walking)"
        conf = round(min(0.96, 0.58 + dist * 0.38), 3)

        inferred_entities.append(
            {
                "id": f"human:link:{idx}",
                "raw_key": f"human:link:{idx}",
                "label": f"{h_label} ~{human_dist_m}m",
                "bssid": f"fresnel-zone-{idx + 1}",
                "ssid": link.get("label", ""),
                "security": "",
                "category": "human",
                "object_class": h_class,
                "object_label": h_label,
                "vendor": "RF Body Reflection / Shadow",
                "distance_m": human_dist_m,
                "mobility": "fast_moving" if is_rapid else "moving",
                "threat": None,
                "channel": 6,
                "rssi": rssi,
                "ewma_rssi": float(rssi),
                "z_score": round(dist * 3.0, 2),
                "disturbance": dist,
                "pps": 1.0,
                "randomized": False,
                "in_use": False,
                "fade": 1.0,
                "x": hx,
                "y": hy,
            }
        )
        inferred_detections.append(
            {
                "label": h_class,
                "confidence": conf,
                "box": _norm_to_box(hx, hy, radius_px=34),
                "model": "rf_human_sensing",
                "track_id": 8100 + idx,
                "reason": f"{h_label} detected across '{link.get('label', 'AP')}' link (~{human_dist_m}m, energy={dist:.2f})",
            }
        )

    # 2. Detect Stationary / Present Humans near mobile/personal devices or near-field micro-variance
    near_personal = [
        ent for ent in entities
        if ent.get("object_class") in {"smartphone", "laptop_pc"}
        and float(ent.get("distance_m", 99.0)) <= 10.0
    ]
    if near_personal and not inferred_entities:
        # Cluster around strongest personal device signature
        primary = max(near_personal, key=lambda e: int(e.get("rssi", -95)))
        px = min(0.92, max(0.08, float(primary["x"]) + 0.03))
        py = min(0.84, max(0.10, float(primary["y"]) + 0.02))
        dist_m = float(primary.get("distance_m", 2.5))
        conf = round(min(0.91, 0.62 + len(near_personal) * 0.07), 3)
        inferred_entities.append(
            {
                "id": "human:presence:0",
                "raw_key": "human:presence:0",
                "label": f"Human (Present) ~{dist_m}m",
                "bssid": "rf-presence-zone",
                "ssid": primary.get("label", ""),
                "security": "",
                "category": "human",
                "object_class": "human_stationary",
                "object_label": "Human (Present)",
                "vendor": "Near-Field Personal RF + Micro-Variance",
                "distance_m": dist_m,
                "mobility": "stationary",
                "threat": None,
                "channel": int(primary.get("channel", 6)),
                "rssi": int(primary.get("rssi", -60)),
                "ewma_rssi": float(primary.get("ewma_rssi", -60.0)),
                "z_score": float(primary.get("z_score", 0.4)),
                "disturbance": max(0.2, float(primary.get("disturbance", 0.2))),
                "pps": float(primary.get("pps", 0.5)),
                "randomized": False,
                "in_use": False,
                "fade": 0.95,
                "x": round(px, 4),
                "y": round(py, 4),
            }
        )
        inferred_detections.append(
            {
                "label": "human_stationary",
                "confidence": conf,
                "box": _norm_to_box(px, py, radius_px=30),
                "model": "rf_human_sensing",
                "track_id": 8200,
                "reason": f"Human presence inferred at ~{dist_m}m ({len(near_personal)} personal RF signature(s) in room)",
            }
        )

    # 3. Detect Physical Obstruction (Door Closed / Dense Object Shadowing)
    for idx, (key, st) in enumerate(emitters_state.items()):
        if st.get("category") != "ap":
            continue
        peak_rssi = float(st.get("peak_rssi", st.get("ewma_rssi", -60.0)))
        ewma_rssi = float(st.get("ewma_rssi", -60.0))
        z_score = float(st.get("z_score", 0.0))
        attenuation_db = peak_rssi - ewma_rssi
        if attenuation_db >= 7.5 and z_score < max(1.6, tripwire_z_thresh * 0.8) and int(st.get("packet_count", 0)) >= 6:
            # Find matching entity coordinates
            match_ent = next((e for e in entities if e.get("raw_key") == key), None)
            if not match_ent:
                continue
            ox = round((sensor_x + float(match_ent["x"])) * 0.5, 4)
            oy = round((sensor_y + float(match_ent["y"])) * 0.5, 4)
            dist_m = round(rssi_to_meters(ewma_rssi) * 0.5, 1)
            inferred_entities.append(
                {
                    "id": f"obstruction:{idx}",
                    "raw_key": f"obstruction:{idx}",
                    "label": f"Obstruction (-{attenuation_db:.0f}dB)",
                    "bssid": key,
                    "ssid": st.get("ssid", ""),
                    "security": "",
                    "category": "obstruction",
                    "object_class": "physical_obstruction",
                    "object_label": "Door / Object Obstruction",
                    "vendor": f"{attenuation_db:.1f} dB Sustained Shadowing",
                    "distance_m": dist_m,
                    "mobility": "stationary",
                    "threat": None,
                    "channel": int(st.get("channel", 6)),
                    "rssi": int(st.get("rssi", -75)),
                    "ewma_rssi": round(ewma_rssi, 1),
                    "z_score": round(z_score, 2),
                    "disturbance": 0.5,
                    "pps": 0.5,
                    "randomized": False,
                    "in_use": False,
                    "fade": 0.9,
                    "x": ox,
                    "y": oy,
                }
            )
            inferred_detections.append(
                {
                    "label": "physical_obstruction",
                    "confidence": round(min(0.92, 0.55 + attenuation_db * 0.03), 3),
                    "box": _norm_to_box(ox, oy, radius_px=28),
                    "model": "rf_obstruction_detector",
                    "track_id": 8300 + idx,
                    "reason": f"Sustained {attenuation_db:.1f} dB attenuation on '{st.get('ssid') or key}' (door or dense object obstruction)",
                }
            )

    return inferred_entities, inferred_detections


def _norm_to_box(cx_norm: float, cy_norm: float, radius_px: int = 32) -> list[int]:
    cx = int(cx_norm * 640)
    cy = int(cy_norm * 420)
    return [
        max(0, cx - radius_px),
        max(0, cy - radius_px),
        min(640, cx + radius_px),
        min(420, cy + radius_px),
    ]
