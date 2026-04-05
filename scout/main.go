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
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"gocv.io/x/gocv"
)

type Box struct {
	Label      string  `json:"label"`
	Box        []int   `json:"box"`
	Confidence float64 `json:"confidence"`
	Model      string  `json:"model"`
}

type AnalyzeResponse struct {
	Event struct {
		Important bool     `json:"important"`
		Reason    string   `json:"reason"`
		Objects   []string `json:"objects"`
	} `json:"event"`
	Detections   []Box           `json:"detections"`
	Expert       map[string]any  `json:"expert"`
	PolicyUpdate map[string]any  `json:"policy_update"`
	Runtime      map[string]any  `json:"runtime"`
	Frame        map[string]int  `json:"frame"`
}

type SessionConfig struct {
	Command         string        `json:"command"`
	Source          string        `json:"source"`
	Sources         string        `json:"sources"`
	APIURL          string        `json:"api_url"`
	TriggerInterval time.Duration `json:"trigger_interval"`
	JSONOutput      bool          `json:"json_output"`
	Headless        bool          `json:"headless"`
	Overlay         bool          `json:"overlay"`
	RecordOutput    string        `json:"record_output"`
	MaxFrames       int           `json:"max_frames"`
	ConfigPath      string        `json:"config"`
}

type SessionEvent struct {
	Timestamp   string         `json:"timestamp"`
	Source      string         `json:"source"`
	Motion      bool           `json:"motion"`
	Detections  []Box          `json:"detections"`
	Event       map[string]any `json:"event"`
	Expert      map[string]any `json:"expert"`
	Policy      map[string]any `json:"policy_update,omitempty"`
	Runtime     map[string]any `json:"runtime,omitempty"`
	FramesSeen  int            `json:"frames_seen"`
	Recorded    bool           `json:"recorded"`
	Command     string         `json:"command"`
}

type sessionState struct {
	boxes []Box
	mu    sync.RWMutex
}

func main() {
	command, args := splitCommand(os.Args[1:])
	switch command {
	case "sources":
		runSourcesCommand(args)
	case "detect", "stream", "track", "calibrate":
		cfg := parseSessionConfig(command, args)
		if err := runCommand(cfg); err != nil {
			fmt.Fprintf(os.Stderr, "scout %s: %v\n", command, err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n", command)
		os.Exit(1)
	}
}

func splitCommand(args []string) (string, []string) {
	if len(args) == 0 {
		return "detect", nil
	}
	if strings.HasPrefix(args[0], "-") {
		return "detect", args
	}
	return args[0], args[1:]
}

func parseSessionConfig(command string, args []string) SessionConfig {
	fs := flag.NewFlagSet(command, flag.ExitOnError)
	cfg := SessionConfig{
		Command:      command,
		Source:       "auto",
		APIURL:       envOrDefault("SCOUT_AI_URL", "http://localhost:8080"),
		Overlay:      true,
		TriggerInterval: 0,
	}
	if configPath := extractConfigPath(args); configPath != "" {
		loaded := loadConfigFile(configPath)
		cfg = mergeConfig(cfg, loaded)
		cfg.ConfigPath = configPath
	}
	fs.StringVar(&cfg.Source, "source", cfg.Source, "single source: auto, camera index, video file, RTSP URL, or folder")
	fs.StringVar(&cfg.Sources, "sources", "", "comma-separated list of sources for multicamera/concurrent processing")
	fs.StringVar(&cfg.APIURL, "api-url", cfg.APIURL, "AI server base URL")
	fs.DurationVar(&cfg.TriggerInterval, "trigger-interval", 0, "minimum time between AI analyses")
	fs.BoolVar(&cfg.JSONOutput, "json", false, "emit JSON logs instead of human-readable output")
	fs.BoolVar(&cfg.Headless, "headless", false, "run without preview windows")
	fs.BoolVar(&cfg.Overlay, "overlay", true, "draw detection overlays in preview window")
	fs.StringVar(&cfg.RecordOutput, "record", "", "optional path prefix for saving processed video")
	fs.IntVar(&cfg.MaxFrames, "max-frames", 0, "optional frame limit for testing or batch runs")
	fs.StringVar(&cfg.ConfigPath, "config", "", "optional JSON config file to load before flags")
	fs.Parse(args)
	if cfg.Command == "calibrate" {
		if !cfg.JSONOutput {
			fmt.Println("Calibration pipeline groundwork is ready; using detect flow for source inspection in this build.")
		}
		cfg.Command = "detect"
	}
	return cfg
}

func loadConfigFile(path string) SessionConfig {
	var cfg SessionConfig
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg
	}
	_ = json.Unmarshal(data, &cfg)
	return cfg
}

func mergeConfig(base SessionConfig, override SessionConfig) SessionConfig {
	if override.Source != "" {
		base.Source = override.Source
	}
	if override.Sources != "" {
		base.Sources = override.Sources
	}
	if override.APIURL != "" {
		base.APIURL = override.APIURL
	}
	if override.TriggerInterval != 0 {
		base.TriggerInterval = override.TriggerInterval
	}
	if override.JSONOutput {
		base.JSONOutput = true
	}
	if override.Headless {
		base.Headless = true
	}
	base.Overlay = override.Overlay
	if override.RecordOutput != "" {
		base.RecordOutput = override.RecordOutput
	}
	if override.MaxFrames > 0 {
		base.MaxFrames = override.MaxFrames
	}
	if override.ConfigPath != "" {
		base.ConfigPath = override.ConfigPath
	}
	return base
}

func extractConfigPath(args []string) string {
	for i := 0; i < len(args); i++ {
		if args[i] == "-config" && i+1 < len(args) {
			return args[i+1]
		}
		if strings.HasPrefix(args[i], "-config=") {
			return strings.TrimPrefix(args[i], "-config=")
		}
	}
	return ""
}

func runSourcesCommand(args []string) {
	fs := flag.NewFlagSet("sources", flag.ExitOnError)
	start := fs.Int("start", 0, "first camera index to probe")
	end := fs.Int("end", 4, "last camera index to probe")
	jsonOutput := fs.Bool("json", false, "emit JSON output")
	fs.Parse(args)

	available := listAvailableCameraIndexes(*start, *end)
	if *jsonOutput {
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
			"command":   "sources",
			"available": available,
		})
		return
	}
	if len(available) == 0 {
		fmt.Println("No cameras detected in the requested index range.")
		return
	}
	fmt.Printf("Available cameras: %v\n", available)
}

func runCommand(cfg SessionConfig) error {
	sources := parseSourceList(cfg)
	if len(sources) == 0 {
		sources = []string{cfg.Source}
	}

	if !aiServerReachable(cfg.APIURL) {
		logLine(cfg, "system", "", map[string]any{
			"message": "AI server is not reachable",
			"api_url": cfg.APIURL,
		})
	}

	var wg sync.WaitGroup
	errCh := make(chan error, len(sources))
	for index, sourceInput := range sources {
		wg.Add(1)
		go func(sessionIndex int, input string) {
			defer wg.Done()
			sessionCfg := cfg
			if err := runSession(sessionCfg, input, sessionIndex); err != nil {
				errCh <- err
			}
		}(index, sourceInput)
	}
	wg.Wait()
	close(errCh)

	for err := range errCh {
		if err != nil {
			return err
		}
	}
	return nil
}

func runSession(cfg SessionConfig, sourceInput string, sessionIndex int) error {
	src, err := openSource(sourceInput)
	if err != nil {
		return fmt.Errorf("open source %q: %w", sourceInput, err)
	}
	defer src.Close()

	windowTitle := src.WindowTitle()
	if len(parseSourceList(cfg)) > 1 {
		windowTitle = fmt.Sprintf("%s [%d]", windowTitle, sessionIndex)
	}

	logLine(cfg, "system", sourceInput, map[string]any{
		"message":          "Scout session started",
		"command":          cfg.Command,
		"source":           sourceInput,
		"live":             src.IsLive(),
		"trigger_interval": effectiveTriggerInterval(cfg, src).String(),
		"api_url":          cfg.APIURL,
	})

	var window *gocv.Window
	if !cfg.Headless {
		window = gocv.NewWindow(windowTitle)
		defer window.Close()
	}

	frame := gocv.NewMat()
	defer frame.Close()

	detector := NewMotionDetector(1000)
	defer detector.Close()

	var writer *gocv.VideoWriter
	var writerPath string
	state := &sessionState{}
	triggerInterval := effectiveTriggerInterval(cfg, src)
	lastTrigger := time.Now().Add(-triggerInterval)
	var analysisInFlight atomic.Bool
	framesSeen := 0

	for {
		if ok := src.Read(&frame); !ok {
			if src.IsLive() {
				continue
			}
			break
		}
		if frame.Empty() {
			continue
		}
		framesSeen++
		if cfg.MaxFrames > 0 && framesSeen > cfg.MaxFrames {
			break
		}

		if writer == nil && cfg.RecordOutput != "" {
			writerPath = recordOutputPath(cfg.RecordOutput, sourceInput, sessionIndex)
			_ = os.MkdirAll(filepath.Dir(writerPath), 0o755)
			writer, err = gocv.VideoWriterFile(writerPath, "MJPG", 20, frame.Cols(), frame.Rows(), true)
			if err == nil {
				defer writer.Close()
			}
		}

		motion := detector.Detect(frame)
		shouldAnalyze := (!src.IsLive() || motion) && time.Since(lastTrigger) >= triggerInterval
		if shouldAnalyze && analysisInFlight.CompareAndSwap(false, true) {
			tempFrame := frame.Clone()
			go func(img gocv.Mat, currentFrame int) {
				defer img.Close()
				defer analysisInFlight.Store(false)

				buf, err := gocv.IMEncode(".jpg", img)
				if err != nil {
					logLine(cfg, "error", sourceInput, map[string]any{"message": "encode frame failed", "error": err.Error()})
					return
				}
				defer buf.Close()

				result, err := sendBytesToAI(cfg.APIURL, buf.GetBytes())
				if err != nil {
					logLine(cfg, "error", sourceInput, map[string]any{"message": "AI analyze failed", "error": err.Error()})
					return
				}

				state.mu.Lock()
				state.boxes = result.Detections
				state.mu.Unlock()

				event := SessionEvent{
					Timestamp:  time.Now().UTC().Format(time.RFC3339),
					Source:     sourceInput,
					Motion:     motion,
					Detections: result.Detections,
					Event: map[string]any{
						"important": result.Event.Important,
						"reason":    result.Event.Reason,
						"objects":   result.Event.Objects,
					},
					Expert:     result.Expert,
					Policy:     result.PolicyUpdate,
					Runtime:    result.Runtime,
					FramesSeen: currentFrame,
					Recorded:   !src.IsLive(),
					Command:    cfg.Command,
				}
				logEvent(cfg, event)
			}(tempFrame, framesSeen)
			lastTrigger = time.Now()
		}

		if cfg.Overlay {
			drawOverlays(&frame, state.currentBoxes())
		}

		if writer != nil {
			writer.Write(frame)
		}

		if window != nil {
			window.IMShow(frame)
			if window.WaitKey(1) >= 0 {
				break
			}
		}
	}

	if writerPath != "" {
		logLine(cfg, "system", sourceInput, map[string]any{
			"message": "Saved processed output",
			"path":    writerPath,
		})
	}
	return nil
}

func (s *sessionState) currentBoxes() []Box {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Box, len(s.boxes))
	copy(out, s.boxes)
	return out
}

func effectiveTriggerInterval(cfg SessionConfig, src *source) time.Duration {
	if cfg.TriggerInterval > 0 {
		return cfg.TriggerInterval
	}
	return src.DefaultTriggerInterval()
}

func parseSourceList(cfg SessionConfig) []string {
	raw := cfg.Sources
	if raw == "" {
		return nil
	}
	var out []string
	for _, item := range strings.Split(raw, ",") {
		item = strings.TrimSpace(item)
		if item != "" {
			out = append(out, item)
		}
	}
	return out
}

func envOrDefault(key string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func aiServerReachable(apiURL string) bool {
	client := http.Client{Timeout: 750 * time.Millisecond}
	resp, err := client.Get(strings.TrimRight(apiURL, "/") + "/health")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}

func sendBytesToAI(apiURL string, imgBytes []byte) (AnalyzeResponse, error) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", "frame.jpg")
	if err != nil {
		return AnalyzeResponse{}, err
	}
	if _, err := part.Write(imgBytes); err != nil {
		return AnalyzeResponse{}, err
	}
	if err := writer.Close(); err != nil {
		return AnalyzeResponse{}, err
	}

	client := http.Client{Timeout: 30 * time.Second}
	resp, err := client.Post(strings.TrimRight(apiURL, "/")+"/analyze", writer.FormDataContentType(), body)
	if err != nil {
		return AnalyzeResponse{}, err
	}
	defer resp.Body.Close()
	content, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return AnalyzeResponse{}, fmt.Errorf("status %d: %s", resp.StatusCode, string(content))
	}

	var result AnalyzeResponse
	if err := json.Unmarshal(content, &result); err != nil {
		return AnalyzeResponse{}, fmt.Errorf("decode analyze response: %w", err)
	}
	return result, nil
}

func drawOverlays(frame *gocv.Mat, boxes []Box) {
	for _, b := range boxes {
		if len(b.Box) != 4 {
			continue
		}
		rect := image.Rect(b.Box[0], b.Box[1], b.Box[2], b.Box[3])
		gocv.Rectangle(frame, rect, color.RGBA{0, 255, 0, 0}, 3)
		label := b.Label
		if b.Confidence > 0 {
			label = fmt.Sprintf("%s %.0f%%", b.Label, b.Confidence*100)
		}
		gocv.PutText(frame, label, image.Pt(b.Box[0], maxInt(20, b.Box[1]-10)),
			gocv.FontHersheyPlain, 1.6, color.RGBA{0, 255, 0, 0}, 2)
	}
}

func recordOutputPath(prefix string, sourceInput string, sessionIndex int) string {
	if strings.HasSuffix(strings.ToLower(prefix), ".avi") || strings.HasSuffix(strings.ToLower(prefix), ".mp4") {
		return prefix
	}
	base := sanitizeFileToken(sourceInput)
	if base == "" {
		base = fmt.Sprintf("source_%d", sessionIndex)
	}
	return filepath.Join(prefix, base+".avi")
}

func sanitizeFileToken(input string) string {
	input = strings.TrimSpace(input)
	input = filepath.Base(input)
	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_", " ", "_")
	return replacer.Replace(input)
}

func logEvent(cfg SessionConfig, event SessionEvent) {
	if cfg.JSONOutput {
		_ = json.NewEncoder(os.Stdout).Encode(event)
		return
	}

	expertAction := fmt.Sprintf("%v", event.Expert["action"])
	fmt.Printf(
		"[%s] source=%s motion=%t detections=%d important=%t expert=%s reason=%v\n",
		event.Timestamp,
		event.Source,
		event.Motion,
		len(event.Detections),
		event.Event["important"],
		expertAction,
		event.Event["reason"],
	)
}

func logLine(cfg SessionConfig, level string, source string, payload map[string]any) {
	if cfg.JSONOutput {
		combined := map[string]any{
			"timestamp": time.Now().UTC().Format(time.RFC3339),
			"level":     level,
			"source":    source,
			"command":   cfg.Command,
		}
		for key, value := range payload {
			combined[key] = value
		}
		_ = json.NewEncoder(os.Stdout).Encode(combined)
		return
	}
	message := fmt.Sprintf("%v", payload["message"])
	delete(payload, "message")
	fmt.Printf("[%s] %s", strings.ToUpper(level), message)
	if source != "" {
		fmt.Printf(" source=%s", source)
	}
	if len(payload) > 0 {
		encoded, _ := json.Marshal(payload)
		fmt.Printf(" %s", string(encoded))
	}
	fmt.Println()
}

func maxInt(a int, b int) int {
	if a > b {
		return a
	}
	return b
}
