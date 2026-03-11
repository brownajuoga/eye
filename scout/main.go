package main

import (
	"fmt"
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
	fmt.Println("Scout running...")
	for {
		if ok := webcam.Read(&frame); !ok {
			continue
		}
		if frame.Empty() {
			continue
		}
		motion, _ := detector.Detect(frame)
		if motion {
			fmt.Println("Motion detected")
			gocv.IMWrite("frame.jpg", frame)
		}
	}
}
