from fastapi import FastAPI, File, UploadFile
import uvicorn

from yolo import detect_objects
from policy import analyze_event
from expert import analyze_image

from memory import store_event, query_memory

app = FastAPI()


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

    contents = await file.read()

    detections = detect_objects(contents)

    event = analyze_event(detections)

    result = {
        "event": event,
        "detections": detections
    }

    #  Only call Expert if important
    if event["important"]:
        expert_decision = analyze_image(contents, detections)

        print("Expert:", expert_decision)

        result["expert"] = expert_decision

    return result


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
