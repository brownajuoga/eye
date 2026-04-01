from transformers import AutoModelForCausalLM, AutoTokenizer
from PIL import Image
import torch
import io

MODEL_ID = "vikhyatk/moondream2"

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    trust_remote_code=True
)

def analyze_image(image_bytes, detections):

    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")

    labels = [d["label"] for d in detections]

    prompt = f"""
You are a security AI.

Objects detected: {labels}

Is this situation suspicious? Is the person stealing, hiding, or acting abnormally?

Answer in JSON:
{{"action": "alert" or "ignore", "reason": "short explanation"}}
"""

    response = model.chat(
        image=image,
        msgs=[{"role": "user", "content": prompt}],
        tokenizer=tokenizer
    )

    return response
