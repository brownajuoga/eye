package main

import (
	"fmt"
	"time"
	"bytes"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"gocv.io/x/gocv"
)

func main() {

	webcam, err := gocv.OpenVideoCapture(0)
	if err != nil {
		panic(err)
	}
	defer webcam.Close()
	frame := gocv.NewMat()
	defer frame.Close()
	detector := NewMotionDetector(5000)
	lastTrigger := time.Now()
	fmt.Println("Scout running...")
	for {
		if ok := webcam.Read(&frame); !ok {
			continue
		}
		if frame.Empty() {
			continue
		}
		motion, _ := detector.Detect(frame)
		if motion && time.Since(lastTrigger) > 2*time.Second {
			fmt.Println("Motion detected")
			imagePath := "frame.jpg"
			gocv.IMWrite(imagePath, frame)
			sendToAi(imagePath)
			lastTrigger = time.Now()
		}
	}
}

func sendToAi(imagePath string) {

	fmt.Println("Sending frame to AI server...")

	file, err := os.Open(imagePath)
	if err != nil {
		fmt.Println("Error opening image:", err)
		return
	}
	defer file.Close()

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", imagePath)
	if err != nil {
		fmt.Println("Error creating form:", err)
		return
	}

	_, err = io.Copy(part, file)
	if err != nil {
		fmt.Println("Error copying file:", err)
		return
	}

	writer.Close()

	resp, err := http.Post(
		"http://localhost:8080/analyze",
		writer.FormDataContentType(),
		body,
	)

	if err != nil {
		fmt.Println("Error sending to AI:", err)
		return
	}

	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Println("Error reading response:", err)
		return
	}

	fmt.Println("AI Response:", string(respBody))
}
