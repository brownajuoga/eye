from fastapi import FastAPI, File, UploadFile
import uvicorn

from yolo import detect_objects

app = FastAPI()


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

    contents = await file.read()

    objects = detect_objects(contents)

    print("Detected:", objects)

    return {
        "objects": objects
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)