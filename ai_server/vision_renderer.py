from __future__ import annotations

from io import BytesIO
from typing import Any

from PIL import Image, ImageDraw


PALETTES = {
    "night_vision": {
        "bg": (5, 18, 10),
        "grid": (15, 58, 32),
        "primary": (40, 255, 120),
        "secondary": (150, 255, 180),
        "human": (110, 255, 210),
        "warn": (255, 196, 56),
        "alert": (255, 72, 72),
        "scanline": (0, 28, 12),
    },
    "thermal": {
        "bg": (12, 10, 32),
        "grid": (40, 28, 86),
        "primary": (255, 126, 38),
        "secondary": (255, 224, 96),
        "human": (255, 250, 180),
        "warn": (255, 72, 118),
        "alert": (255, 255, 255),
        "scanline": (22, 14, 48),
    },
    "radar": {
        "bg": (4, 16, 22),
        "grid": (16, 72, 88),
        "primary": (36, 224, 240),
        "secondary": (140, 255, 232),
        "human": (120, 255, 160),
        "warn": (255, 200, 64),
        "alert": (255, 84, 84),
        "scanline": (6, 26, 36),
    },
}


def render_vision_jpeg(
    vision: dict[str, Any],
    *,
    palette_name: str = "night_vision",
    quality: int = 84,
) -> bytes:
    width = int(vision.get("frame_size", {}).get("width", 640))
    height = int(vision.get("frame_size", {}).get("height", 420))
    pal = PALETTES.get(palette_name, PALETTES["night_vision"])

    img = Image.new("RGB", (width, height), pal["bg"])
    draw = ImageDraw.Draw(img, "RGBA")

    # Tactical subtle grid + scanline texture
    for x in range(0, width, 40):
        draw.line([(x, 0), (x, height)], fill=pal["grid"] + (90,), width=1)
    for y in range(0, height, 40):
        draw.line([(0, y), (width, y)], fill=pal["grid"] + (90,), width=1)
    for y in range(0, height, 4):
        draw.line([(0, y), (width, y)], fill=pal["scanline"] + (75,), width=1)

    sensor = vision.get("sensor", {"x": 0.5, "y": 0.68})
    sx = int(float(sensor.get("x", 0.5)) * width)
    sy = int(float(sensor.get("y", 0.68)) * height)

    # Concentric distance rings around ESP8266 sensor
    for r, dist_label in ((60, "1.5m"), (120, "4m"), (180, "8m"), (250, "15m")):
        draw.ellipse([sx - r, sy - r, sx + r, sy + r], outline=pal["grid"] + (160,), width=1)
        draw.text((sx + int(r * 0.7), sy - int(r * 0.7)), dist_label, fill=pal["grid"] + (210,))

    # RF links & Fresnel motion disturbance waves
    for link in vision.get("links", []):
        tx = int(float(link.get("to_x", 0.5)) * width)
        ty = int(float(link.get("to_y", 0.3)) * height)
        dist = float(link.get("disturbance", 0.0))
        crossing = bool(link.get("crossing", False))
        line_color = pal["alert"] if crossing else (pal["warn"] if dist > 0.35 else pal["primary"])
        alpha = 210 if crossing else int(110 + dist * 110)
        draw.line([(sx, sy), (tx, ty)], fill=line_color + (alpha,), width=3 if crossing else 2)

        if dist > 0.2:
            mx, my = (sx + tx) // 2, (sy + ty) // 2
            wave_r = int(18 + dist * 46)
            draw.ellipse([mx - wave_r, my - wave_r, mx + wave_r, my + wave_r], fill=line_color + (55,), outline=line_color + (200,), width=2)

    # Emitter spatial heat blobs, Human Silhouettes & classified Object tags
    for ent in vision.get("entities", []):
        ex = int(float(ent.get("x", 0.5)) * width)
        ey = int(float(ent.get("y", 0.5)) * height)
        rssi = int(ent.get("rssi", -75))
        dist = float(ent.get("disturbance", 0.0))
        fade = float(ent.get("fade", 1.0))
        threat = ent.get("threat")
        cat = str(ent.get("category", "client"))
        obj_cls = str(ent.get("object_class", ""))
        dist_m = ent.get("distance_m")

        if cat == "human" or obj_cls.startswith("human_"):
            # Render glowing Night-Vision Human Silhouette (Head + Torso + Target Box)
            h_col = pal["alert"] if obj_cls == "human_rapid_motion" else (pal["warn"] if obj_cls == "human_moving" else pal["human"])
            for r_glow, a_glow in ((34, 48), (22, 95)):
                draw.ellipse([ex - r_glow, ey - r_glow, ex + r_glow, ey + r_glow], fill=h_col + (a_glow,))
            # Head
            draw.ellipse([ex - 5, ey - 14, ex + 5, ey - 4], fill=h_col + (240,))
            # Shoulders / Torso
            draw.rounded_rectangle([ex - 9, ey - 3, ex + 9, ey + 12], radius=4, fill=h_col + (215,))
            # Target brackets
            draw.rectangle([ex - 16, ey - 19, ex + 16, ey + 17], outline=h_col + (245,), width=2)
            tag = f"[{ent.get('object_label', 'HUMAN').upper()}] ~{dist_m or '?'}m"
            draw.text((ex + 19, ey - 12), tag, fill=h_col + (255,))
            continue

        if cat == "obstruction" or obj_cls == "physical_obstruction":
            draw.rectangle([ex - 14, ey - 8, ex + 14, ey + 8], fill=pal["warn"] + (95,), outline=pal["warn"] + (240,), width=2)
            draw.text((ex + 17, ey - 8), f"[OBSTRUCTION] {ent.get('label', '')}", fill=pal["warn"] + (250,))
            continue

        is_distant = float(ent.get("ewma_rssi", rssi)) < -74.0 and not bool(ent.get("in_use"))
        strength = max(0.15, min(1.0, (100 + rssi) / 65.0))
        blob_r = int((10 + strength * 12) if is_distant else (14 + strength * 22 + dist * 14))
        base_col = (
            pal["alert"]
            if threat
            else (
                pal["warn"]
                if (not is_distant and dist > 0.58)
                else (pal["primary"] if cat == "ap" else pal["secondary"])
            )
        )
        eff_fade = fade * (0.45 if is_distant else 1.0)
        for scale, alpha_scale in ((1.0, 38), (0.62, 82), (0.28, 195)):
            rr = max(3, int(blob_r * scale))
            draw.ellipse([ex - rr, ey - rr, ex + rr, ey + rr], fill=base_col + (int(alpha_scale * eff_fade),))

        short_cls = {
            "smartphone": "PHONE",
            "laptop_pc": "PC",
            "wifi_ap": "AP",
            "iot_device": "IOT",
            "smart_tv_media": "TV",
            "vehicle_drone": "DRONE/VEH",
        }.get(obj_cls, "DEV")
        dist_str = f" ~{dist_m}m" if dist_m is not None else ""
        label = f"[{short_cls}] {ent.get('label', '?')}{dist_str} ({int(round(float(ent.get('ewma_rssi', rssi))))}dBm)"
        draw.text((ex + 10, ey - 10), label, fill=base_col + (int(235 * (0.65 if is_distant else 1.0)),))

    # Draw ESP8266 NodeMCU sensor marker
    draw.rectangle([sx - 8, sy - 8, sx + 8, sy + 8], fill=pal["secondary"] + (230,), outline=pal["primary"] + (255,), width=2)
    draw.text((sx + 12, sy - 6), "ESP8266 SENSOR", fill=pal["secondary"] + (245,))

    # Live bottom oscilloscope bar
    waveform = vision.get("waveform", [])
    if len(waveform) >= 2:
        pts = []
        base_y = height - 26
        for idx, sample in enumerate(waveform[-60:]):
            wx = int(16 + (idx / 59.0) * (width - 32))
            val = float(sample.get("rssi", -65))
            norm_h = max(0.0, min(1.0, (val + 95.0) / 65.0))
            wy = int(base_y - norm_h * 34)
            pts.append((wx, wy))
        if len(pts) >= 2:
            draw.line(pts, fill=pal["primary"] + (210,), width=2)

    # Top Night-Vision Camera HUD header with Human & Object counts
    metrics = vision.get("metrics", {})
    counts = vision.get("object_counts", {})
    hud = (
        f"CAM-RF LIVE | HUMANS:{counts.get('humans', 0)} | PHONES:{counts.get('smartphones', 0)} "
        f"| PCS:{counts.get('laptops', 0)} | APS:{counts.get('routers', 0)} | IOT:{counts.get('iot_devices', 0)} "
        f"| DIST:{metrics.get('disturbance', 0):.2f}"
    )
    draw.rectangle([0, 0, width, 24], fill=(0, 0, 0, 165))
    draw.text((8, 6), hud, fill=pal["primary"] + (250,))

    banner = str(vision.get("alert_banner") or "")
    if banner:
        draw.rectangle([10, 28, width - 10, 50], fill=pal["alert"] + (180,))
        draw.text((16, 33), f"DETECTED: {banner[:78]}", fill=(255, 255, 255, 255))

    buf = BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()
