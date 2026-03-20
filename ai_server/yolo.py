from ultralytics import YOLO
import cv2
import numpy as np

model = YOLO("yolo11n.pt")

def detect_objects(image_bytes):
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    results = model(img)

    objects = []

    for r in results:
        for box in r.boxes:
            cls = int(box.cls[0])
            label = model.names[cls]
            objects.append(label)
        
    return list(set(objects))