package main

import (
	"gocv.io/x/gocv"
)

type MotionDetector struct {
	bgSubtractor gocv.BackgroundSubtractorMOG2
	threshold    int
}

func NewMotionDetector(threshold int) *MotionDetector {
	return &MotionDetector{
		bgSubtractor: gocv.NewBackgroundSubtractorMOG2(),
		threshold:    threshold,
	}
}

func (m *MotionDetector) Detect(frame gocv.Mat) bool {
	mask := gocv.NewMat()
	defer mask.Close()

	m.bgSubtractor.Apply(frame, &mask)
	movement := gocv.CountNonZero(mask)
	return movement > m.threshold
}

func (m *MotionDetector) Close() {
	m.bgSubtractor.Close()
}
