package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type SessionConfig struct {
	Command       string        `json:"command"`
	Source        string        `json:"source"`
	APIURL        string        `json:"api_url"`
	Interface     string        `json:"interface"`
	Device        string        `json:"device"`
	Baud          int           `json:"baud"`
	Interval      time.Duration `json:"interval"`
	ListenAddr    string        `json:"listen"`
	Scenario      string        `json:"scenario"`
	JSONOutput    bool          `json:"json_output"`
	Headless      bool          `json:"headless"`
	MaxBatches    int           `json:"max_batches"`
	Channel       int           `json:"channel"`
	PrivacyMode   bool          `json:"privacy"`
}

func main() {
	command, args := splitCommand(os.Args[1:])
	switch command {
	case "sources":
		runSourcesCommand(args)
	case "nodemcu-cmd":
		runNodeMcuCommand(args)
	case "detect", "stream", "track", "bridge", "sim":
		cfg := parseSessionConfig(command, args)
		if err := runCollector(cfg); err != nil {
			fmt.Fprintf(os.Stderr, "scout %s: %v\n", command, err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q (valid: sources, detect, bridge, sim, nodemcu-cmd)\n", command)
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
		Command:    command,
		Source:     "auto",
		APIURL:     envOrDefault("SCOUT_AI_URL", "http://127.0.0.1:8080"),
		Baud:       115200,
		Interval:   800 * time.Millisecond,
		ListenAddr: ":8090",
		Scenario:   "mixed",
	}
	if command == "sim" {
		cfg.Source = "sim"
	} else if command == "bridge" {
		cfg.Source = "bridge"
	}

	fs.StringVar(&cfg.Source, "source", cfg.Source, "auto, nodemcu, host-wifi, bridge, sim, or path (.pcap/.jsonl)")
	fs.StringVar(&cfg.APIURL, "api-url", cfg.APIURL, "AI server base URL")
	fs.StringVar(&cfg.Interface, "iface", "", "Linux Wi-Fi interface name (e.g. wlp13s0)")
	fs.StringVar(&cfg.Device, "device", "", "NodeMCU USB serial port (e.g. /dev/ttyUSB0)")
	fs.IntVar(&cfg.Baud, "baud", cfg.Baud, "Serial baud rate for NodeMCU")
	fs.DurationVar(&cfg.Interval, "interval", cfg.Interval, "Polling/batching interval")
	fs.StringVar(&cfg.ListenAddr, "listen", cfg.ListenAddr, "Listen address for unplugged NodeMCU bridge mode")
	fs.StringVar(&cfg.Scenario, "scenario", cfg.Scenario, "Simulator scenario: mixed, motion, deauth, evil_twin, crowd")
	fs.BoolVar(&cfg.JSONOutput, "json", false, "Emit NDJSON event logs")
	fs.BoolVar(&cfg.Headless, "headless", false, "Headless terminal mode")
	fs.IntVar(&cfg.MaxBatches, "max-batches", 0, "Stop after N transmitted batches (0 = run continuously)")
	fs.IntVar(&cfg.Channel, "channel", 0, "Optional 2.4 GHz channel lock (1-13) for NodeMCU")
	fs.BoolVar(&cfg.PrivacyMode, "privacy", false, "Enable privacy MAC hashing on NodeMCU")
	_ = fs.Parse(args)
	return cfg
}

func envOrDefault(key string, fallback string) string {
	if val := strings.TrimSpace(os.Getenv(key)); val != "" {
		return val
	}
	return fallback
}

func runSourcesCommand(args []string) {
	fs := flag.NewFlagSet("sources", flag.ExitOnError)
	jsonFlag := fs.Bool("json", false, "Emit JSON")
	_ = fs.Parse(args)

	discovered := discoverSources()
	if *jsonFlag {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(discovered)
		return
	}
	fmt.Printf("Recommended source: %s\n", discovered.Recommended)
	fmt.Printf("NodeMCU serial ports: %v\n", discovered.SerialPorts)
	fmt.Printf("Host Wi-Fi interfaces: %v\n", discovered.WifiInterfaces)
}

func runNodeMcuCommand(args []string) {
	fs := flag.NewFlagSet("nodemcu-cmd", flag.ExitOnError)
	device := fs.String("device", "", "Serial port (e.g. /dev/ttyUSB0)")
	baud := fs.Int("baud", 115200, "Baud rate")
	cmdText := fs.String("cmd", "PING", "Serial command to send (e.g. CHANNEL:6, HOP:1, MODE:LINK)")
	_ = fs.Parse(args)

	portPath := *device
	if portPath == "" {
		ports := findSerialPorts()
		if len(ports) == 0 {
			fmt.Fprintln(os.Stderr, "no NodeMCU USB serial device found (/dev/ttyUSB* or /dev/ttyACM*)")
			os.Exit(1)
		}
		portPath = ports[0]
	}
	if err := configureSerialPort(portPath, *baud); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	f, err := os.OpenFile(portPath, os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open %s: %v\n", portPath, err)
		os.Exit(1)
	}
	defer f.Close()
	_, _ = fmt.Fprintf(f, "%s\n", strings.TrimSpace(*cmdText))
	fmt.Printf("Sent %q to %s\n", *cmdText, portPath)
}

func runCollector(cfg SessionConfig) error {
	resolved := resolveSourceTarget(cfg)
	client := &http.Client{Timeout: 5 * time.Second}

	switch {
	case strings.HasPrefix(resolved, "nodemcu:"):
		port := strings.TrimPrefix(resolved, "nodemcu:")
		return runNodeMcuSerialLoop(cfg, client, port)
	case strings.HasPrefix(resolved, "host-wifi:"):
		iface := strings.TrimPrefix(resolved, "host-wifi:")
		return runHostWifiLoop(cfg, client, iface)
	case resolved == "bridge":
		return runBridgeServer(cfg, client)
	case resolved == "sim":
		return runSimulatorLoop(cfg, client)
	default:
		return runFileSource(cfg, client, resolved)
	}
}

func resolveSourceTarget(cfg SessionConfig) string {
	src := strings.TrimSpace(cfg.Source)
	if cfg.Device != "" && (src == "auto" || src == "nodemcu" || src == "nodemcu-serial") {
		return "nodemcu:" + cfg.Device
	}
	if src == "" || src == "auto" {
		return discoverSources().Recommended
	}
	if src == "nodemcu" || src == "nodemcu-serial" {
		ports := findSerialPorts()
		if len(ports) > 0 {
			return "nodemcu:" + ports[0]
		}
		return "nodemcu:/dev/ttyUSB0"
	}
	if src == "host-wifi" || src == "wifi" {
		if cfg.Interface != "" {
			return "host-wifi:" + cfg.Interface
		}
		ifaces := findWifiInterfaces()
		if len(ifaces) > 0 {
			return "host-wifi:" + ifaces[0]
		}
		return "host-wifi:wlan0"
	}
	return src
}

func runNodeMcuSerialLoop(cfg SessionConfig, client *http.Client, port string) error {
	if err := configureSerialPort(port, cfg.Baud); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "permission denied") {
			return fmt.Errorf("%w\nHint: grant USB serial access once with: sudo usermod -aG dialout $USER && newgrp dialout", err)
		}
		return err
	}
	f, err := os.OpenFile(port, os.O_RDWR, 0)
	if err != nil {
		if os.IsPermission(err) {
			return fmt.Errorf("open NodeMCU port %s: %w\nHint: run 'sudo usermod -aG dialout $USER && newgrp dialout'", port, err)
		}
		return fmt.Errorf("open NodeMCU port %s: %w", port, err)
	}
	defer func() {
		_, _ = fmt.Fprintln(f, "ACTIVE:0")
		_ = f.Close()
	}()

	_, _ = fmt.Fprintln(f, "ACTIVE:1")
	if cfg.Channel >= 1 && cfg.Channel <= 13 {
		_, _ = fmt.Fprintf(f, "CHANNEL:%d\n", cfg.Channel)
	}
	if cfg.PrivacyMode {
		_, _ = fmt.Fprintln(f, "PRIVACY:1")
	}

	logMsg(cfg.JSONOutput, "nodemcu_serial", fmt.Sprintf("streaming 802.11 RF telemetry from %s -> %s", port, cfg.APIURL))

	lineCh := make(chan RfObservation, 128)
	errCh := make(chan error, 1)
	go func() {
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			if obs, ok := parseNodeMcuLine(scanner.Text()); ok {
				lineCh <- *obs
			}
		}
		if scanErr := scanner.Err(); scanErr != nil {
			errCh <- scanErr
		} else {
			errCh <- io.EOF
		}
	}()

	flushTicker := time.NewTicker(250 * time.Millisecond)
	cmdTicker := time.NewTicker(1 * time.Second)
	defer flushTicker.Stop()
	defer cmdTicker.Stop()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	var buffer []RfObservation
	batchesSent := 0

	for {
		select {
		case <-sigCh:
			return nil
		case readErr := <-errCh:
			return readErr
		case obs := <-lineCh:
			buffer = append(buffer, obs)
			if len(buffer) >= 24 || obs.Subtype == "deauth" || obs.Subtype == "disassoc" {
				if err := flushSerialBatch(client, cfg, port, &buffer); err == nil {
					batchesSent++
					if cfg.MaxBatches > 0 && batchesSent >= cfg.MaxBatches {
						return nil
					}
				}
			}
		case <-flushTicker.C:
			if len(buffer) > 0 {
				if err := flushSerialBatch(client, cfg, port, &buffer); err == nil {
					batchesSent++
					if cfg.MaxBatches > 0 && batchesSent >= cfg.MaxBatches {
						return nil
					}
				}
			}
		case <-cmdTicker.C:
			pollNodeMcuCommands(client, cfg.APIURL, f)
		}
	}
}

func flushSerialBatch(client *http.Client, cfg SessionConfig, port string, buf *[]RfObservation) error {
	batch := IngestBatch{
		SourceID:     "nodemcu_usb",
		SourceName:   "NodeMCU USB (" + filepath.Base(port) + ")",
		SourceKind:   "nodemcu_serial",
		LiveSource:   true,
		Observations: *buf,
	}
	err := postIngestBatch(client, cfg.APIURL, batch)
	if err != nil {
		logMsg(cfg.JSONOutput, "warn", fmt.Sprintf("ingest failed: %v", err))
		return err
	}
	logMsg(cfg.JSONOutput, "nodemcu_serial", fmt.Sprintf("sent %d RF frames", len(*buf)))
	*buf = nil
	return nil
}

func runHostWifiLoop(cfg SessionConfig, client *http.Client, iface string) error {
	logMsg(cfg.JSONOutput, "host_wifi", fmt.Sprintf("monitoring interface %s -> %s", iface, cfg.APIURL))
	ticker := time.NewTicker(cfg.Interval)
	defer ticker.Stop()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	batches := 0
	for {
		obs, err := collectHostWifiOnce(iface)
		if err != nil {
			logMsg(cfg.JSONOutput, "warn", err.Error())
		} else {
			batch := IngestBatch{
				SourceID:     "host_" + iface,
				SourceName:   "Host Wi-Fi (" + iface + ")",
				SourceKind:   "host_wifi",
				LiveSource:   true,
				Observations: obs,
			}
			if postErr := postIngestBatch(client, cfg.APIURL, batch); postErr != nil {
				logMsg(cfg.JSONOutput, "warn", fmt.Sprintf("ingest error: %v", postErr))
			} else {
				logMsg(cfg.JSONOutput, "host_wifi", fmt.Sprintf("sent %d observations from %s", len(obs), iface))
			}
			batches++
			if cfg.MaxBatches > 0 && batches >= cfg.MaxBatches {
				return nil
			}
		}

		select {
		case <-sigCh:
			return nil
		case <-ticker.C:
		}
	}
}

func runSimulatorLoop(cfg SessionConfig, client *http.Client) error {
	sim := newSimulatorState(cfg.Scenario)
	logMsg(cfg.JSONOutput, "simulator", fmt.Sprintf("streaming RF simulation (%s) -> %s", cfg.Scenario, cfg.APIURL))
	ticker := time.NewTicker(cfg.Interval)
	defer ticker.Stop()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	batches := 0
	for {
		batch := sim.nextBatch()
		if err := postIngestBatch(client, cfg.APIURL, batch); err != nil {
			logMsg(cfg.JSONOutput, "warn", fmt.Sprintf("sim ingest error: %v", err))
		} else {
			logMsg(cfg.JSONOutput, "simulator", fmt.Sprintf("tick %d: %d observations", sim.tick, len(batch.Observations)))
		}
		batches++
		if cfg.MaxBatches > 0 && batches >= cfg.MaxBatches {
			return nil
		}
		select {
		case <-sigCh:
			return nil
		case <-ticker.C:
		}
	}
}

func runBridgeServer(cfg SessionConfig, client *http.Client) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/wifi/ingest", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		raw, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		var batch IngestBatch
		if err := json.Unmarshal(raw, &batch); err != nil {
			http.Error(w, "invalid ingest json", http.StatusBadRequest)
			return
		}
		if batch.SourceKind == "" {
			batch.SourceKind = "nodemcu_wifi"
		}
		batch.LiveSource = true
		if err := postIngestBatch(client, cfg.APIURL, batch); err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		logMsg(cfg.JSONOutput, "bridge", fmt.Sprintf("relayed %d frames from %s", len(batch.Observations), batch.SourceID))
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"relayed"}`))
	})

	logMsg(cfg.JSONOutput, "bridge", fmt.Sprintf("listening on %s for unplugged NodeMCU nodes -> %s", cfg.ListenAddr, cfg.APIURL))
	return http.ListenAndServe(cfg.ListenAddr, mux)
}

func runFileSource(cfg SessionConfig, client *http.Client, path string) error {
	ext := strings.ToLower(filepath.Ext(path))
	if ext == ".pcap" || ext == ".pcapng" || ext == ".csv" {
		if err := uploadCaptureFile(client, cfg.APIURL, path); err != nil {
			return err
		}
		logMsg(cfg.JSONOutput, "file", fmt.Sprintf("uploaded capture %s to %s/wifi/upload", path, cfg.APIURL))
		return nil
	}
	obs, err := readJsonlBatchFile(path)
	if err != nil {
		return err
	}
	chunkSize := 20
	for i := 0; i < len(obs); i += chunkSize {
		end := i + chunkSize
		if end > len(obs) {
			end = len(obs)
		}
		batch := IngestBatch{
			SourceID:     filepath.Base(path),
			SourceName:   "Replay (" + filepath.Base(path) + ")",
			SourceKind:   "file_replay",
			LiveSource:   false,
			Observations: obs[i:end],
		}
		if err := postIngestBatch(client, cfg.APIURL, batch); err != nil {
			return err
		}
		time.Sleep(cfg.Interval)
	}
	return nil
}

func logMsg(jsonOut bool, source string, msg string) {
	if jsonOut {
		payload, _ := json.Marshal(map[string]any{
			"timestamp": time.Now().UTC().Format(time.RFC3339),
			"source":    source,
			"message":   msg,
		})
		fmt.Println(string(payload))
		return
	}
	fmt.Printf("[%s] %s\n", source, msg)
}
