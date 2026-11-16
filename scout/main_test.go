package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestParseNmcliOutput(t *testing.T) {
	sample := "*:50\\:14\\:C1\\:E3\\:76\\:1C:pinnacle:7:2442 MHz:130 Mbit/s:100:WPA2\n" +
		" :8A\\:74\\:77\\:60\\:13\\:D4:Fredrick:11:2462 MHz:1170 Mbit/s:64:WPA2\n"
	obs := parseNmcliOutput(sample, "host-wlp13s0")
	if len(obs) != 2 {
		t.Fatalf("expected 2 observations, got %d", len(obs))
	}
	if obs[0].BSSID != "50:14:c1:e3:76:1c" || !obs[0].InUse || obs[0].Channel != 7 || obs[0].RSSI != -35 {
		t.Fatalf("unexpected first observation: %+v", obs[0])
	}
	if obs[1].SSID != "Fredrick" || obs[1].Channel != 11 || obs[1].RSSI != -68 {
		t.Fatalf("unexpected second observation: %+v", obs[1])
	}
}

func TestParseNodeMcuLineAndSimulatorIngest(t *testing.T) {
	line := `{"node_id":"nodemcu-1","channel":6,"rssi":-58,"frame_type":"mgmt","subtype":"probe_req","sa":"da:a1:19:01:02:03","bssid":"ff:ff:ff:ff:ff:ff","ssid":"CafeNet","randomized":true}`
	obs, ok := parseNodeMcuLine(line)
	if !ok {
		t.Fatalf("expected valid observation")
	}
	if obs.Channel != 6 || obs.RSSI != -58 || !obs.Randomized || obs.Subtype != "probe_req" {
		t.Fatalf("unexpected parsed obs: %+v", obs)
	}

	var received IngestBatch
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/wifi/ingest" {
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
		if err := json.NewDecoder(r.Body).Decode(&received); err != nil {
			t.Fatalf("decode failed: %v", err)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	sim := newSimulatorState("deauth")
	batch := sim.nextBatch()
	if err := postIngestBatch(srv.Client(), srv.URL, batch); err != nil {
		t.Fatalf("postIngestBatch failed: %v", err)
	}
	if len(received.Observations) == 0 {
		t.Fatalf("expected observations in ingest batch")
	}
}
