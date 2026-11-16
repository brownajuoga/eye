package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type RfObservation struct {
	NodeID     string  `json:"node_id"`
	Source     string  `json:"source"`
	Timestamp  string  `json:"timestamp,omitempty"`
	TsMs       int64   `json:"ts_ms,omitempty"`
	Channel    int     `json:"channel"`
	RSSI       int     `json:"rssi"`
	FrameType  string  `json:"frame_type"`
	Subtype    string  `json:"subtype"`
	SA         string  `json:"sa"`
	BSSID      string  `json:"bssid"`
	SSID       string  `json:"ssid"`
	Security   string  `json:"security,omitempty"`
	RateMbps   float64 `json:"rate,omitempty"`
	PktLen     int     `json:"pkt_len,omitempty"`
	Randomized bool    `json:"randomized,omitempty"`
	Privacy    bool    `json:"privacy,omitempty"`
	InUse      bool    `json:"in_use,omitempty"`
}

type IngestBatch struct {
	SourceID     string          `json:"source_id"`
	SourceName   string          `json:"source_name"`
	SourceKind   string          `json:"source_kind"`
	LiveSource   bool            `json:"live_source"`
	ModeHint     string          `json:"mode_hint,omitempty"`
	Observations []RfObservation `json:"observations"`
}

type DiscoveredSources struct {
	SerialPorts    []string `json:"serial_ports"`
	WifiInterfaces []string `json:"wifi_interfaces"`
	Recommended    string   `json:"recommended"`
}

func discoverSources() DiscoveredSources {
	serialPorts := findSerialPorts()
	wifiIfaces := findWifiInterfaces()
	recommended := "sim"
	if len(serialPorts) > 0 {
		recommended = "nodemcu:" + serialPorts[0]
	} else if len(wifiIfaces) > 0 {
		recommended = "host-wifi:" + wifiIfaces[0]
	}
	return DiscoveredSources{
		SerialPorts:    serialPorts,
		WifiInterfaces: wifiIfaces,
		Recommended:    recommended,
	}
}

func findSerialPorts() []string {
	var ports []string
	for _, pattern := range []string{"/dev/ttyUSB*", "/dev/ttyACM*", "/dev/cu.usbserial*", "/dev/cu.SLAB*"} {
		matches, _ := filepath.Glob(pattern)
		ports = append(ports, matches...)
	}
	sort.Strings(ports)
	return ports
}

func findWifiInterfaces() []string {
	var ifaces []string
	entries, err := os.ReadDir("/sys/class/net")
	if err != nil {
		return ifaces
	}
	for _, entry := range entries {
		name := entry.Name()
		wirelessPath := filepath.Join("/sys/class/net", name, "wireless")
		if info, statErr := os.Stat(wirelessPath); statErr == nil && info.IsDir() {
			ifaces = append(ifaces, name)
		}
	}
	sort.Strings(ifaces)
	return ifaces
}

// splitEscapedColon splits nmcli `-t` fields where literal colons are escaped as `\:`.
func splitEscapedColon(line string) []string {
	var parts []string
	var cur strings.Builder
	escaped := false
	for i := 0; i < len(line); i++ {
		ch := line[i]
		if escaped {
			cur.WriteByte(ch)
			escaped = false
			continue
		}
		if ch == '\\' {
			escaped = true
			continue
		}
		if ch == ':' {
			parts = append(parts, cur.String())
			cur.Reset()
			continue
		}
		cur.WriteByte(ch)
	}
	parts = append(parts, cur.String())
	return parts
}

func parseNmcliOutput(raw string, nodeID string) []RfObservation {
	lines := strings.Split(strings.TrimSpace(raw), "\n")
	var out []RfObservation
	now := time.Now().UTC().Format(time.RFC3339Nano)
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		cols := splitEscapedColon(line)
		if len(cols) < 7 {
			continue
		}
		inUse := strings.TrimSpace(cols[0]) == "*"
		bssid := strings.ToLower(strings.TrimSpace(cols[1]))
		ssid := strings.TrimSpace(cols[2])
		channel, _ := strconv.Atoi(strings.TrimSpace(cols[3]))
		freqMHz := parseLeadingInt(cols[4])
		if channel == 0 && freqMHz > 0 {
			channel = freqToChannel(freqMHz)
		}
		rateMbps := float64(parseLeadingInt(cols[5]))
		sigPct, err := strconv.Atoi(strings.TrimSpace(cols[6]))
		if err != nil {
			sigPct = 30
		}
		rssi := signalPctToRSSI(sigPct)
		security := ""
		if len(cols) >= 8 {
			security = strings.TrimSpace(cols[7])
		}
		out = append(out, RfObservation{
			NodeID:    nodeID,
			Source:    "host_wifi_nmcli",
			Timestamp: now,
			Channel:   channel,
			RSSI:      rssi,
			FrameType: "mgmt",
			Subtype:   "beacon",
			SA:        bssid,
			BSSID:     bssid,
			SSID:      ssid,
			Security:  security,
			RateMbps:  rateMbps,
			InUse:     inUse,
		})
	}
	return out
}

func parseIwLinkOutput(raw string, iface string) *RfObservation {
	if strings.Contains(raw, "Not connected") {
		return nil
	}
	var bssid, ssid string
	var freqMHz, rssi int
	hasSignal := false
	for _, line := range strings.Split(raw, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Connected to ") {
			fields := strings.Fields(trimmed)
			if len(fields) >= 3 {
				bssid = strings.ToLower(fields[2])
			}
		} else if strings.HasPrefix(trimmed, "SSID:") {
			ssid = strings.TrimSpace(strings.TrimPrefix(trimmed, "SSID:"))
		} else if strings.HasPrefix(trimmed, "freq:") {
			freqMHz = parseLeadingInt(strings.TrimPrefix(trimmed, "freq:"))
		} else if strings.HasPrefix(trimmed, "signal:") {
			rssi = parseLeadingInt(strings.TrimPrefix(trimmed, "signal:"))
			hasSignal = true
		}
	}
	if bssid == "" {
		return nil
	}
	if !hasSignal {
		rssi = -52
	}
	return &RfObservation{
		NodeID:    "host-" + iface,
		Source:    "host_wifi_iw",
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Channel:   freqToChannel(freqMHz),
		RSSI:      rssi,
		FrameType: "data",
		Subtype:   "link_sample",
		SA:        bssid,
		BSSID:     bssid,
		SSID:      ssid,
		InUse:     true,
	}
}

func parseLeadingInt(s string) int {
	s = strings.TrimSpace(s)
	var num strings.Builder
	for i, r := range s {
		if (r >= '0' && r <= '9') || (i == 0 && r == '-') {
			num.WriteRune(r)
		} else if num.Len() > 0 {
			break
		}
	}
	if num.Len() == 0 {
		return 0
	}
	v, _ := strconv.Atoi(num.String())
	return v
}

func signalPctToRSSI(pct int) int {
	if pct <= 0 {
		return -98
	}
	if pct >= 100 {
		return -35
	}
	return (pct / 2) - 100
}

func freqToChannel(freqMHz int) int {
	if freqMHz == 2484 {
		return 14
	}
	if freqMHz >= 2412 && freqMHz <= 2472 {
		return (freqMHz-2412)/5 + 1
	}
	if freqMHz >= 5180 && freqMHz <= 5825 {
		return (freqMHz-5000)/5
	}
	return 0
}

func collectHostWifiOnce(iface string) ([]RfObservation, error) {
	var obs []RfObservation
	if _, err := exec.LookPath("nmcli"); err == nil {
		out, cmdErr := exec.Command(
			"nmcli", "-t", "-f", "IN-USE,BSSID,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY", "dev", "wifi", "list",
		).Output()
		if cmdErr == nil {
			obs = append(obs, parseNmcliOutput(string(out), "host-"+iface)...)
		}
	}
	if _, err := exec.LookPath("iw"); err == nil && iface != "" {
		out, cmdErr := exec.Command("iw", "dev", iface, "link").Output()
		if cmdErr == nil {
			if linkObs := parseIwLinkOutput(string(out), iface); linkObs != nil {
				// Avoid resetting RSSI if nmcli already captured accurate percentage, unless signal came from iw
				alreadyHasInUse := false
				for _, item := range obs {
					if item.InUse {
						alreadyHasInUse = true
						break
					}
				}
				if !alreadyHasInUse {
					obs = append(obs, *linkObs)
				}
			}
		}
	}
	if len(obs) == 0 {
		return nil, errors.New("no Wi-Fi observations returned by nmcli/iw")
	}
	return obs, nil
}

func parseNodeMcuLine(line string) (*RfObservation, bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || !strings.HasPrefix(trimmed, "{") {
		return nil, false
	}
	var raw map[string]any
	if err := json.Unmarshal([]byte(trimmed), &raw); err != nil {
		return nil, false
	}
	if t, ok := raw["type"].(string); ok && t == "status" {
		return nil, false
	}
	var obs RfObservation
	if err := json.Unmarshal([]byte(trimmed), &obs); err != nil {
		return nil, false
	}
	if obs.Source == "" {
		obs.Source = "nodemcu_esp8266"
	}
	if obs.Timestamp == "" {
		obs.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	}
	return &obs, true
}

func configureSerialPort(port string, baud int) error {
	baudStr := strconv.Itoa(baud)
	cmd := exec.Command("stty", "-F", port, baudStr, "raw", "-echo", "-echoe", "-echok", "min", "1", "time", "2")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("configure serial %s (%s): %w (%s)", port, baudStr, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func postIngestBatch(client *http.Client, apiURL string, batch IngestBatch) error {
	payload, err := json.Marshal(batch)
	if err != nil {
		return err
	}
	endpoint := strings.TrimRight(apiURL, "/") + "/wifi/ingest"
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("ingest status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

func uploadCaptureFile(client *http.Client, apiURL string, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		return err
	}

	boundary := "----EyeCaptureBoundary7e3b9f"
	var body bytes.Buffer
	fmt.Fprintf(&body, "--%s\r\n", boundary)
	fmt.Fprintf(&body, "Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n", filepath.Base(path))
	body.WriteString("Content-Type: application/octet-stream\r\n\r\n")
	body.Write(data)
	fmt.Fprintf(&body, "\r\n--%s--\r\n", boundary)

	endpoint := strings.TrimRight(apiURL, "/") + "/wifi/upload"
	req, err := http.NewRequest(http.MethodPost, endpoint, &body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "multipart/form-data; boundary="+boundary)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("upload status %d: %s", resp.StatusCode, strings.TrimSpace(string(msg)))
	}
	return nil
}

type simulatorState struct {
	tick     int
	rng      *rand.Rand
	scenario string
}

func newSimulatorState(scenario string) *simulatorState {
	if scenario == "" {
		scenario = "mixed"
	}
	return &simulatorState{
		rng:      rand.New(rand.NewSource(time.Now().UnixNano())),
		scenario: scenario,
	}
}

func (s *simulatorState) nextBatch() IngestBatch {
	s.tick++
	now := time.Now().UTC().Format(time.RFC3339Nano)
	t := float64(s.tick)

	// Anchor router RSSI with natural multipath + doorway motion dip every ~14 ticks
	motionDip := 0.0
	if s.scenario == "motion" || (s.scenario == "mixed" && (s.tick%18 >= 6 && s.tick%18 <= 10)) {
		motionDip = -14.0*math.Abs(math.Sin(t*0.8)) - float64(s.rng.Intn(5))
	}

	obs := []RfObservation{
		{
			NodeID:    "sim-nodemcu-01",
			Source:    "simulator",
			Timestamp: now,
			Channel:   6,
			RSSI:      int(math.Round(-44 + motionDip + float64(s.rng.Intn(3)-1))),
			FrameType: "mgmt",
			Subtype:   "beacon",
			SA:        "50:14:c1:e3:76:1c",
			BSSID:     "50:14:c1:e3:76:1c",
			SSID:      "Home_Core_AP",
			Security:  "WPA2",
			RateMbps:  130,
			InUse:     true,
		},
		{
			NodeID:    "sim-nodemcu-01",
			Source:    "simulator",
			Timestamp: now,
			Channel:   11,
			RSSI:      -63 + s.rng.Intn(4) - 2,
			FrameType: "mgmt",
			Subtype:   "beacon",
			SA:        "8a:74:77:60:13:d4",
			BSSID:     "8a:74:77:60:13:d4",
			SSID:      "Neighbor_Mesh_5",
			Security:  "WPA2",
			RateMbps:  72,
		},
		{
			NodeID:     "sim-nodemcu-01",
			Source:     "simulator",
			Timestamp:  now,
			Channel:    6,
			RSSI:       int(math.Round(-56 + motionDip*0.6 + float64(s.rng.Intn(5)-2))),
			FrameType:  "mgmt",
			Subtype:    "probe_req",
			SA:         fmt.Sprintf("da:a1:19:%02x:%02x:0%d", 10+s.tick%4, 20, s.tick%3),
			BSSID:      "ff:ff:ff:ff:ff:ff",
			SSID:       "Home_Core_AP",
			Randomized: true,
			RateMbps:   24,
		},
	}

	if s.scenario == "crowd" || s.scenario == "mixed" {
		for i := 0; i < 3; i++ {
			obs = append(obs, RfObservation{
				NodeID:     "sim-nodemcu-01",
				Source:     "simulator",
				Timestamp:  now,
				Channel:    1 + (i*5)%11,
				RSSI:       -68 - i*4 + s.rng.Intn(5) - 2,
				FrameType:  "mgmt",
				Subtype:    "probe_req",
				SA:         fmt.Sprintf("f2:9c:44:%02x:%02x:%02x", i+1, (s.tick+i)%7, 11+i),
				BSSID:      "ff:ff:ff:ff:ff:ff",
				Randomized: true,
				RateMbps:   12,
			})
		}
	}

	if s.scenario == "deauth" || (s.scenario == "mixed" && s.tick%25 >= 19 && s.tick%25 <= 21) {
		for i := 0; i < 8; i++ {
			obs = append(obs, RfObservation{
				NodeID:    "sim-nodemcu-01",
				Source:    "simulator",
				Timestamp: now,
				Channel:   6,
				RSSI:      -48 + s.rng.Intn(4) - 2,
				FrameType: "mgmt",
				Subtype:   "deauth",
				SA:        "de:ad:be:ef:00:99",
				BSSID:     "50:14:c1:e3:76:1c",
				SSID:      "Home_Core_AP",
			})
		}
	}

	if s.scenario == "evil_twin" || (s.scenario == "mixed" && s.tick%32 == 27) {
		obs = append(obs, RfObservation{
			NodeID:    "sim-nodemcu-01",
			Source:    "simulator",
			Timestamp: now,
			Channel:   6,
			RSSI:      -39,
			FrameType: "mgmt",
			Subtype:   "beacon",
			SA:        "66:77:88:99:aa:bb",
			BSSID:     "66:77:88:99:aa:bb",
			SSID:      "Home_Core_AP",
			Security:  "OPEN",
		})
	}

	return IngestBatch{
		SourceID:     "sim_rf",
		SourceName:   "RF Simulator (" + s.scenario + ")",
		SourceKind:   "simulator",
		LiveSource:   true,
		ModeHint:     s.scenario,
		Observations: obs,
	}
}

func pollNodeMcuCommands(client *http.Client, apiURL string, nodePort *os.File) {
	endpoint := strings.TrimRight(apiURL, "/") + "/wifi/nodemcu/command?consume=true"
	resp, err := client.Get(endpoint)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return
	}
	var payload struct {
		Commands []string `json:"commands"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return
	}
	for _, cmd := range payload.Commands {
		if strings.TrimSpace(cmd) != "" {
			_, _ = fmt.Fprintf(nodePort, "%s\n", strings.TrimSpace(cmd))
		}
	}
}

func readJsonlBatchFile(path string) ([]RfObservation, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var obs []RfObservation
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if parsed, ok := parseNodeMcuLine(scanner.Text()); ok {
			obs = append(obs, *parsed)
		}
	}
	return obs, scanner.Err()
}

