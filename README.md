# eye

**Modular Wi-Fi Surveillance & RF Intelligence Platform (ESP8266 NodeMCU + Go Scout + FastAPI + Flutter Night-Vision Cam)**

`eye` turns commodity Wi-Fi hardware (an **ESP8266 NodeMCU** board — both plugged via USB and unplugged over Wi-Fi — plus your host Linux Wi-Fi interface or `.pcap`/`.csv`/`.jsonl` capture files) into a dynamic, real-time RF surveillance **and** privacy-preserving spatial intelligence platform.

Instead of camera pixels and heavy GPU models, `eye` sees through walls and dark rooms via **2.4 GHz RF telemetry**, rendering a live **Night-Vision / Thermal / Tactical Radar / 2.4 GHz Spectrum** video view.

---

## Core Capabilities

### 1. Night-Vision Wi-Fi Cam (`ui`)
* **Night Vision (Phosphor Green)**, **Thermal RF**, **Tactical Radar**, and **2.4 GHz Channel Spectrum (Ch 1–13)** live views.
* **Spatial RF Field & Fresnel Motion Waves:** Animated disturbance ripples across AP-to-NodeMCU links whenever human movement perturbs RSSI stability.
* **Interactive Floorplan & Target Inspector:** Drag NodeMCU/AP anchors to match your room layout and tap emitters to inspect live dBm, Z-score, channel, security, and threat tags.
* **Live RSSI Oscilloscope & Replay Player:** Scrub or play back uploaded `.pcap`/`.pcapng`/`.csv`/`.jsonl` captures slice-by-slice inside the cam viewport.

### 2. Multi-Mode RF Intelligence (`ai_server`)
* **WIDS Security (Blue-Team):** Deauth/Disassoc flood detection, Evil Twin / Rogue BSSID detection against trusted APs, Beacon Spam alerts, and Canary decoy AP traps.
* **Device-Free Motion Tripwire:** Sliding-window EWMA baseline + Z-score RSSI disturbance detection across links (no camera or wearable tags needed).
* **Privacy-Preserving Occupancy:** Anonymizes MAC addresses with SHA-256 ephemeral tags (`ANON ON`) while estimating room occupancy density (`empty / low / moderate / crowded`).
* **2.4 GHz Spectrum & Site Survey:** Channel congestion, overlap interference analysis, legacy slow-rate detection, and cleanest non-overlapping channel recommendation (`1 / 6 / 11`).
* **Pure-Python Capture Parser:** Parses standard IEEE 802.11 + Radiotap `.pcap` / `.pcapng`, `.csv`, and `.jsonl` RF captures with zero external C dependencies.

### 3. Dynamic Collectors & Hardware (`firmware/nodemcu_eye` + `scout`)
* **ESP8266 NodeMCU Dual-Mode Firmware:**
  * **Plugged (USB Serial):** Continuous 802.11 promiscuous sniffing across channels 1–13 streamed as NDJSON to `scout`.
  * **Unplugged (Standalone Wi-Fi):** Continuous AP Link RSSI tripwire (`MODE_WIFI_LINK`), Hybrid sniff-and-upload (`MODE_WIFI_HYBRID`), Canary AP (`MODE_WIFI_CANARY`), and captive setup portal (`EYE-NODE-SETUP`).
* **Pure-Go Edge Collector (`scout`):** Zero C++/OpenCV dependencies. Auto-discovers NodeMCU USB serial (`/dev/ttyUSB*`), Linux host Wi-Fi (`nmcli`/`iw`), unplugged bridge HTTP relay, capture file replay, and built-in RF physics simulator.

---

## Architecture

| Tier | Component | Responsibility |
| --- | --- | --- |
| Tier 1 | **NodeMCU Firmware / Go `scout`** | Collects 802.11 frames, link RSSI, and channel telemetry (USB Serial, Wi-Fi HTTP, Host NIC, Simulator, or PCAP) |
| Tier 2 | **Wi-Fi Engine (`ai_server`)** | Computes EWMA RSSI baselines, Z-score disturbance, WIDS alerts, occupancy, and 2.4 GHz spectrum metrics |
| Tier 3 | **Rule Engine & Policy** | Hot-reloadable watchlist, Trusted APs, privacy toggles, and temporal automation rules |
| Tier 4 | **Night-Vision Console (`ui`)** | Live 30fps Night-Vision Cam canvas, NodeMCU remote controls, Capture replay, and Expert Chat |

---

## Quick Start

### 1. Start the Python RF Server
```bash
cd /home/brown/me/eye
ai_server/venv/bin/python ai_server/main.py
```

### 2. Start Edge Collector (`scout`) or Use In-App Controls
You can start **Host Wi-Fi Scan** or **RF Simulator** with one click inside the Flutter **Night-Vision Cam** panel, or run `scout` from a terminal:
```bash
cd /home/brown/me/eye/scout
./scout sources
./scout detect -source auto -api-url http://127.0.0.1:8080
```

### 3. Launch the Flutter Control Center
```bash
cd /home/brown/me/eye/ui
flutter run -d chrome --dart-define=EYE_API_BASE_URL=http://127.0.0.1:8080
```
