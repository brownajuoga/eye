package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
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
	sourceFlag := flag.String("source", "0", "video source: webcam index, video file path, or folder of recorded videos")
	triggerIntervalFlag := flag.Duration("trigger-interval", 0, "minimum time between AI analyses; defaults to 1s for live input and 250ms for recorded video")
	flag.Parse()

	source, err := openSource(*sourceFlag)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open source: %v\n", err)
		os.Exit(1)
	}
	defer source.Close()

	window := gocv.NewWindow(source.WindowTitle())
	defer window.Close()

	frame := gocv.NewMat()
	defer frame.Close()

	detector := NewMotionDetector(1000)
	triggerInterval := *triggerIntervalFlag
	if triggerInterval <= 0 {
		triggerInterval = source.DefaultTriggerInterval()
	}
	lastTrigger := time.Now().Add(-triggerInterval)
	var analysisInFlight atomic.Bool

	for {
		if ok := source.Read(&frame); !ok {
			if source.IsLive() {
				continue
			}
			break
		}
		if frame.Empty() {
			continue
		}

		motion := detector.Detect(frame)
		if motion && time.Since(lastTrigger) >= triggerInterval && analysisInFlight.CompareAndSwap(false, true) {
			tempFrame := frame.Clone()
			go func(img gocv.Mat) {
				defer img.Close()
				defer analysisInFlight.Store(false)

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
	part, err := writer.CreateFormFile("file", "frame.jpg")
	if err != nil {
		return "[]"
	}
	if _, err := part.Write(imgBytes); err != nil {
		return "[]"
	}
	if err := writer.Close(); err != nil {
		return "[]"
	}

	resp, err := http.Post("http://localhost:8080/analyze", writer.FormDataContentType(), body)
	if err != nil {
		return "[]"
	}
	defer resp.Body.Close()
	content, _ := io.ReadAll(resp.Body)
	return string(content)
}
