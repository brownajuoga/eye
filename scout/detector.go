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

func (m *MotionDetector) Detect(frame gocv.Mat) (bool, gocv.Mat) {
	mask := gocv.NewMat()
	m.bgSubtractor.Apply(frame, &mask)
	movement := gocv.CountNonZero(mask)
	return movement > m.threshold, mask
}
