from __future__ import annotations

from pathlib import Path
import os
import threading
from typing import Any


YOLO = None
YOLO_IMPORT_ATTEMPTED = False


BASE_DIR = Path(__file__).resolve().parent


class YoloDetector:
    def __init__(self):
        self._lock = threading.RLock()
        self._loaded_model = None
        self._loaded_model_path: str | None = None
        self._loaded_mode: str | None = None
        self._ram_gb = detect_available_ram_gb()
        self._fallback_detector = None

    def detect_objects(self, image_bytes: bytes, policy: dict[str, Any]) -> list[dict[str, Any]]:
        image = decode_image(image_bytes)
        confidence_threshold = float(policy["model"].get("confidence_threshold", 0.35))
        min_confidence = float(policy["rules"].get("min_confidence", confidence_threshold))
        threshold = max(confidence_threshold, min_confidence)

        model = self._get_model(policy)
        if model is None:
            return self._detect_with_fallback(image, threshold)

        results = model(image, verbose=False)
        detections: list[dict[str, Any]] = []

        for result in results:
            for box in result.boxes:
                confidence = float(box.conf[0])
                if confidence < threshold:
                    continue

                cls = int(box.cls[0])
                x1, y1, x2, y2 = (int(value) for value in box.xyxy[0].tolist())
                label = str(model.names.get(cls, str(cls)))
                detections.append(
                    {
                        "label": label,
                        "confidence": round(confidence, 3),
                        "box": [x1, y1, x2, y2],
                        "model": self._loaded_model_path,
                    }
                )

        return detections

    def describe_runtime(self, policy: dict[str, Any]) -> dict[str, Any]:
        selected_mode = select_runtime_mode(policy.get("mode", "balanced"), self._ram_gb)
        selected_model = resolve_model_path(policy, selected_mode)
        active_backend = "ultralytics" if YOLO is not None else "opencv_hog_fallback"
        return {
            "ram_gb": self._ram_gb,
            "cpu_count": os.cpu_count() or 0,
            "requested_mode": policy.get("mode", "balanced"),
            "effective_mode": selected_mode,
            "model_path": selected_model,
            "loaded_model_path": self._loaded_model_path,
            "backend": active_backend,
            "resources": detect_resource_snapshot(),
        }

    def describe_capabilities(self, policy: dict[str, Any]) -> dict[str, Any]:
        active_mode = select_runtime_mode(policy.get("mode", "balanced"), self._ram_gb)
        return {
            "input_sources": [
                "webcam",
                "video_file",
                "video_folder",
                "rtsp_stream",
                "image_sequence",
                "multicamera",
            ],
            "detection_modules": [
                "motion_trigger",
                "yolo_generic",
                "opencv_hog_fallback",
                "rule_engine",
            ],
            "expert_backends": ["mock", "ollama", "transformers"],
            "supports_live_feed": True,
            "supports_video_upload": True,
            "supports_runtime_model_switching": True,
            "supports_policy_hot_reload": True,
            "supports_multicamera_sync": True,
            "tracking_status": "groundwork_ready",
            "calibration_status": "planned",
            "active_mode": active_mode,
            "configured_model": resolve_model_path(policy, active_mode),
        }

    def list_models(self, policy: dict[str, Any]) -> list[dict[str, Any]]:
        active_path = resolve_model_path(policy, select_runtime_mode(policy.get("mode", "balanced"), self._ram_gb))
        candidates = discover_model_files()
        models: list[dict[str, Any]] = []
        for path in candidates:
            file_path = Path(path)
            models.append(
                {
                    "id": str(file_path),
                    "name": file_path.name,
                    "path": str(file_path),
                    "size_bytes": file_path.stat().st_size if file_path.exists() else None,
                    "format": file_path.suffix.lstrip("."),
                    "active": str(file_path) == active_path or file_path.name == Path(active_path).name,
                }
            )
        return models

    def _get_model(self, policy: dict[str, Any]):
        yolo_class = load_yolo_class()
        if yolo_class is None:
            return None

        selected_mode = select_runtime_mode(policy.get("mode", "balanced"), self._ram_gb)
        selected_model = resolve_model_path(policy, selected_mode)

        with self._lock:
            if self._loaded_model is None or self._loaded_model_path != selected_model:
                try:
                    self._loaded_model = yolo_class(selected_model)
                    self._loaded_model_path = selected_model
                    self._loaded_mode = selected_mode
                except Exception:
                    self._loaded_model = None
                    self._loaded_model_path = None
                    self._loaded_mode = None
            return self._loaded_model

    def _detect_with_fallback(self, image, threshold: float) -> list[dict[str, Any]]:
        cv2 = load_cv2()

        with self._lock:
            if self._fallback_detector is None:
                hog = cv2.HOGDescriptor()
                hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
                face = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
                self._fallback_detector = {
                    "hog": hog,
                    "face": face,
                }

            hog = self._fallback_detector["hog"]
            face = self._fallback_detector["face"]

        detections: list[dict[str, Any]] = []
        image_height, image_width = image.shape[:2]

        for target_width in (640, 1280):
            scale = min(1.0, target_width / float(image_width))
            resized = image if scale == 1.0 else cv2.resize(image, (int(image_width * scale), int(image_height * scale)))
            rects, weights = hog.detectMultiScale(
                resized,
                winStride=(4, 4),
                padding=(8, 8),
                scale=1.03,
            )

            for (x, y, w, h), weight in zip(rects, weights):
                confidence = min(1.0, max(0.0, float(weight)))
                if confidence < threshold:
                    continue
                inv_scale = 1.0 / scale
                detections.append(
                    {
                        "label": "person",
                        "confidence": round(confidence, 3),
                        "box": [
                            int(x * inv_scale),
                            int(y * inv_scale),
                            int((x + w) * inv_scale),
                            int((y + h) * inv_scale),
                        ],
                        "model": "opencv-hog-person",
                    }
                )

            if detections:
                break

        if detections:
            return dedupe_detections(detections)

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        faces = face.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4)
        for (x, y, w, h) in faces:
            detections.append(
                {
                    "label": "person",
                    "confidence": round(max(threshold, 0.45), 3),
                    "box": [int(x), int(y), int(x + w), int(y + h)],
                    "model": "opencv-face-person",
                }
            )

        return detections


def decode_image(image_bytes: bytes):
    try:
        import numpy as np
    except Exception as exc:
        raise RuntimeError("opencv-python and numpy are required for image decoding") from exc
    cv2 = load_cv2()

    nparr = np.frombuffer(image_bytes, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Failed to decode image bytes")
    return image


def load_cv2():
    try:
        import cv2
    except Exception as exc:
        raise RuntimeError("opencv-python is required for image decoding and fallback detection") from exc
    return cv2


def load_yolo_class():
    global YOLO, YOLO_IMPORT_ATTEMPTED
    if YOLO_IMPORT_ATTEMPTED:
        return YOLO
    YOLO_IMPORT_ATTEMPTED = True
    try:
        from ultralytics import YOLO as yolo_class
    except Exception:  # pragma: no cover - optional dependency path
        YOLO = None
    else:
        YOLO = yolo_class
    return YOLO


def resolve_model_path(policy: dict[str, Any], mode: str) -> str:
    model_cfg = policy.get("model", {})
    requested = model_cfg.get("custom") or model_cfg.get(mode) or model_cfg.get("default") or "yolov8n.pt"
    candidate = Path(str(requested))
    if candidate.is_absolute():
        return str(candidate)

    direct_path = BASE_DIR / str(requested)
    if direct_path.exists():
        return str(direct_path)

    sibling_path = BASE_DIR.parent / str(requested)
    if sibling_path.exists():
        return str(sibling_path)

    return str(requested)


def select_runtime_mode(requested_mode: str, ram_gb: float) -> str:
    if requested_mode not in {"lightweight", "balanced", "performance"}:
        requested_mode = "balanced"

    if ram_gb < 4:
        return "lightweight"
    if ram_gb < 8 and requested_mode == "performance":
        return "balanced"
    return requested_mode


def detect_available_ram_gb() -> float:
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("MemTotal:"):
                    parts = line.split()
                    kb = int(parts[1])
                    return round(kb / (1024 * 1024), 2)
    except Exception:
        pass
    return 0.0


def detect_resource_snapshot() -> dict[str, Any]:
    resources = {
        "ram_gb": detect_available_ram_gb(),
        "cpu_count": os.cpu_count() or 0,
        "load_avg": None,
        "disk_free_gb": None,
    }
    try:
        load = os.getloadavg()
        resources["load_avg"] = [round(item, 2) for item in load]
    except Exception:
        pass
    try:
        stat = os.statvfs(str(BASE_DIR))
        free_bytes = stat.f_bavail * stat.f_frsize
        resources["disk_free_gb"] = round(free_bytes / (1024 * 1024 * 1024), 2)
    except Exception:
        pass
    return resources


def discover_model_files() -> list[str]:
    seen: set[str] = set()
    models: list[str] = []
    search_roots = [BASE_DIR, BASE_DIR.parent]
    for root in search_roots:
        if not root.exists():
            continue
        for candidate in root.rglob("*"):
            if not candidate.is_file():
                continue
            if candidate.suffix.lower() not in {".pt", ".onnx"}:
                continue
            candidate_str = str(candidate.resolve())
            if candidate_str in seen:
                continue
            seen.add(candidate_str)
            models.append(candidate_str)
    models.sort()
    return models


def dedupe_detections(detections: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    seen: set[tuple[int, int, int, int]] = set()
    for detection in detections:
        box = tuple(detection["box"])
        if box in seen:
            continue
        seen.add(box)
        output.append(detection)
    return output
