from fastapi import FastAPI, File, UploadFile
import uvicorn

app=FastAPI()

@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

	contents = await file.read()
	print("Received image:", file.filename)
	return{
		"status": "received",
		"filename": file.filename
	}

if __name__ == "__main__":
	uvicorn.run(app, host="0.0.0.0", port=8080)