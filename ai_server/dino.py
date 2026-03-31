import torch
import cv2
import numpy as np
from PIL import Image
import groundingdino.datasets.transforms as T
from groundingdino.util.inference import load_model, predict

MODEL_CONFIG = "GroundingDINO_SwinT_OGC.py"
MODEL_WEIGHTS = "groundingdino_swint_ogc.pth"

device = "cuda" if torch.cuda.is_available() else "cpu"
model = load_model(MODEL_CONFIG, MODEL_WEIGHTS, device=device)

if not hasattr(model.bert, 'get_head_mask'):
    model.bert.get_head_mask = lambda *args, **kwargs: [None] * 12

def detect(image_bytes, prompt):
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    h, w, _ = img.shape
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    
    transform = T.Compose([
        T.RandomResize([800], max_size=1333),
        T.ToTensor(),
        T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    image_tensor, _ = transform(Image.fromarray(img_rgb), None)

    boxes, logits, phrases = predict(
        model=model,
        image=image_tensor,
        caption=prompt,
        box_threshold=0.35,
        text_threshold=0.25,
        device=device
    )

    results = []
    for box, label in zip(boxes, phrases):
        cx, cy, bw, bh = box.tolist()
        x1 = int((cx - bw/2) * w)
        y1 = int((cy - bh/2) * h)
        x2 = int((cx + bw/2) * w)
        y2 = int((cy + bh/2) * h)
        results.append({"label": label, "box": [x1, y1, x2, y2]})

    return results
