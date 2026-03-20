from fastapi import FastAPI, File, UploadFile
import uvicorn

from dino import detect
from prompts import load_prompt

app = FastAPI()


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

    contents = await file.read()

    prompt = load_prompt()

    objects = detect(contents, prompt)

    print("Prompt:", prompt)
    print("Detected:", objects)

    return {
        "detected": objects
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
