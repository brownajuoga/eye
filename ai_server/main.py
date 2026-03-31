from fastapi import FastAPI, File, UploadFile
import uvicorn

from yolo import detect_objects

app = FastAPI()


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

    contents = await file.read()

    detections = detect_objects(contents)

    print("Detections:", detections)

    return {
        "detections": detections
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)