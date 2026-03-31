package main

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"io"
	"mime/multipart"
	"net/http"
	"sync"
	"time"

	"gocv.io/x/gocv"
)

type Box struct {
	Label string `json:"label"`
	Box   []int  `json:"box"`
}

var (
	currentBoxes []Box
	mutex        sync.Mutex
)

func main() {
	webcam, err := gocv.OpenVideoCapture(0)
	if err != nil {
		panic(err)
	}
	defer webcam.Close()

	window := gocv.NewWindow("Scout Live Feed")
	defer window.Close()

	frame := gocv.NewMat()
	defer frame.Close()

	detector := NewMotionDetector(1000)
	lastTrigger := time.Now()

	for {
		if ok := webcam.Read(&frame); !ok || frame.Empty() {
			continue
		}

		motion, _ := detector.Detect(frame)
		if motion && time.Since(lastTrigger) > 1*time.Second {
			tempFrame := frame.Clone()
			go func(img gocv.Mat) {
				defer img.Close()
				buf, err := gocv.IMEncode(".jpg", img)
				if err != nil {
					return
				}
				defer buf.Close()
				
				res := sendBytesToAi(buf.GetBytes())
				var boxes []Box
				if err := json.Unmarshal([]byte(res), &boxes); err == nil {
					mutex.Lock()
					currentBoxes = boxes
					mutex.Unlock()
				}
			}(tempFrame)
			lastTrigger = time.Now()
		}

		mutex.Lock()
		for _, b := range currentBoxes {
			if len(b.Box) == 4 {
				rect := image.Rect(b.Box[0], b.Box[1], b.Box[2], b.Box[3])
				gocv.Rectangle(&frame, rect, color.RGBA{0, 255, 0, 0}, 3)
				gocv.PutText(&frame, b.Label, image.Pt(b.Box[0], b.Box[1]-10),
					gocv.FontHersheyPlain, 2.0, color.RGBA{0, 255, 0, 0}, 2)
			}
		}
		mutex.Unlock()

		window.IMShow(frame)
		if window.WaitKey(1) >= 0 {
			break
		}
	}
}

func sendBytesToAi(imgBytes []byte) string {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, _ := writer.CreateFormFile("file", "frame.jpg")
	part.Write(imgBytes)
	writer.Close()

	resp, err := http.Post("http://localhost:8080/analyze", writer.FormDataContentType(), body)
	if err != nil {
		return "[]"
	}
	defer resp.Body.Close()
	content, _ := io.ReadAll(resp.Body)
	return string(content)
}
