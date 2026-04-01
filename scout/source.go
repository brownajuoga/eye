package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"gocv.io/x/gocv"
)

var supportedVideoExtensions = map[string]struct{}{
	".avi":  {},
	".m4v":  {},
	".mkv":  {},
	".mov":  {},
	".mp4":  {},
	".mpeg": {},
	".mpg":  {},
	".webm": {},
}

type source struct {
	capture     *gocv.VideoCapture
	isLive      bool
	paths       []string
	currentPath string
	nextIndex   int
}

func openSource(input string) (*source, error) {
	if cameraIndex, err := strconv.Atoi(input); err == nil {
		capture, err := gocv.OpenVideoCapture(cameraIndex)
		if err != nil {
			return nil, fmt.Errorf("open camera %d: %w", cameraIndex, err)
		}
		return &source{capture: capture, isLive: true}, nil
	}

	info, err := os.Stat(input)
	if err != nil {
		return nil, fmt.Errorf("inspect %q: %w", input, err)
	}

	if info.IsDir() {
		paths, err := collectVideoFiles(input)
		if err != nil {
			return nil, err
		}
		src := &source{paths: paths}
		if err := src.advance(); err != nil {
			return nil, err
		}
		return src, nil
	}

	capture, err := gocv.VideoCaptureFile(input)
	if err != nil {
		return nil, fmt.Errorf("open video file %q: %w", input, err)
	}
	return &source{capture: capture, currentPath: input}, nil
}

func (s *source) Close() {
	if s.capture != nil {
		s.capture.Close()
	}
}

func (s *source) Read(frame *gocv.Mat) bool {
	for {
		if s.capture == nil {
			return false
		}

		if ok := s.capture.Read(frame); ok && !frame.Empty() {
			return true
		}

		if s.isLive {
			return false
		}

		if err := s.advance(); err != nil {
			return false
		}
	}
}

func (s *source) IsLive() bool {
	return s.isLive
}

func (s *source) DefaultTriggerInterval() time.Duration {
	if s.isLive {
		return time.Second
	}
	return 250 * time.Millisecond
}

func (s *source) WindowTitle() string {
	if s.isLive {
		return "Scout Live Feed"
	}
	if s.currentPath == "" {
		return "Scout Recorded Feed"
	}
	return "Scout Recorded Feed: " + filepath.Base(s.currentPath)
}

func (s *source) advance() error {
	if s.capture != nil {
		s.capture.Close()
		s.capture = nil
	}

	for s.nextIndex < len(s.paths) {
		path := s.paths[s.nextIndex]
		s.nextIndex++

		capture, err := gocv.VideoCaptureFile(path)
		if err != nil {
			continue
		}

		s.capture = capture
		s.currentPath = path
		return nil
	}

	return fmt.Errorf("no more recorded videos")
}

func collectVideoFiles(root string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}
		if _, ok := supportedVideoExtensions[strings.ToLower(filepath.Ext(path))]; ok {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("scan video folder %q: %w", root, err)
	}
	slices.Sort(paths)
	if len(paths) == 0 {
		return nil, fmt.Errorf("no supported video files found in %q", root)
	}
	return paths, nil
}
