from ultralytics import YOLO
import cv2
import numpy as np

# Default model (can be swapped later)
MODEL_PATH = "yolov8n.pt"

model = YOLO(MODEL_PATH)

CONF_THRESHOLD = 0.35


def detect_objects(image_bytes):

    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    results = model(img)

    detections = []

    for r in results:
        for box in r.boxes:

            conf = float(box.conf[0])
            if conf < CONF_THRESHOLD:
                continue

            cls = int(box.cls[0])
            label = model.names[cls]

            detections.append({
                "label": label,
                "confidence": round(conf, 2)
            })

    return detections