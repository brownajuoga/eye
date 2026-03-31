from fastapi import FastAPI, File, UploadFile
import uvicorn

from yolo import detect_objects
from policy import analyze_event

app = FastAPI()


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

    contents = await file.read()

    detections = detect_objects(contents)

    event = analyze_event(detections)

    print("Detections:", detections)
    print("Event:", event)

    return {
        "event": event,
        "detections": detections
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
