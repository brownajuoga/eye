package main

import (
	"gocv.io/x/gocv"
)

type MotionDetector struct {
	prevFrame gocv.Mat
	threshold float32
}

func NewMotionDetector(threshold float32) *MotionDetector {
	return &MotionDetector{
		prevFrame: gocv.NewMat(),
		threshold: threshold,
	}
}

func (md *MotionDetector) Detect(frame gocv.Mat) bool {
	gray := gocv.NewMat()
	defer gray.Close()

	gocv.CvtColor(frame, &gray, gocv.ColorBGRToGray)

	if md.prevFrame.Empty() {
		md.prevFrame = gray.Clone()
		return false
	}

	diff := gocv.NewMat()
	defer diff.Close()

	gocv.AbsDiff(md.prevFrame, gray, &diff)
	gocv.Threshold(diff, &diff, 25, 255, gocv.ThresholdBinary)

	nonZero := gocv.CountNonZero(diff)

	md.prevFrame.Close()
	md.prevFrame = gray.Clone()

	return float32(nonZero) > md.threshold
}

func (md *MotionDetector) Close() {
	if !md.prevFrame.Empty() {
		md.prevFrame.Close()
	}
}
