# NodeMCU (ESP8266) Firmware for `eye`

`nodemcu_eye.ino` turns an ESP8266 NodeMCU board into a dynamic 2.4 GHz RF sensor supporting **both plugged and unplugged** deployment.

## Modes Supported
1. **Plugged via USB Serial (`MODE_SERIAL_PROMISC` - default when Wi-Fi SSID is blank):**
   - Runs continuous IEEE 802.11 promiscuous mode across channels 1–13 (or locked channel).
   - Captures Beacon, Probe Request/Response, Deauth, Disassoc, and Data frame headers with `rssi`, `channel`, `rate`/`MCS`, randomized-MAC flag, and SSID.
   - Streams NDJSON lines at `115200` baud to `scout detect -source nodemcu`.
2. **Unplugged Continuous Tripwire (`MODE_WIFI_LINK`):**
   - Connects directly to your router/hotspot and streams continuous AP RSSI link samples (~6–10 Hz) plus periodic neighborhood scans to `POST http://<PC_IP>:8080/wifi/ingest`.
   - Ideal for doorway/hallway human-motion tripwire sensing without a USB cable attached to your PC.
3. **Unplugged Hybrid WIDS Sniffer (`MODE_WIFI_HYBRID`):**
   - Time-slices between promiscuous sniffing (3 seconds default) and Wi-Fi HTTP batch uploads (`/wifi/ingest`).
4. **Canary / Decoy AP (`MODE_WIFI_CANARY`):**
   - Broadcasts an optional decoy SoftAP while staying linked to report probe/association events and flash the onboard LED (`D4`).

## Flashing Instructions
### Option A: Arduino IDE
1. Install the **esp8266** board package in Arduino Boards Manager (`http://arduino.esp8266.com/stable/package_esp8266com_index.json`).
2. Select **Board: NodeMCU 1.0 (ESP-12E Module)**.
3. Open `firmware/nodemcu_eye/nodemcu_eye.ino` and click **Upload**.

### Option B: PlatformIO CLI
```bash
cd firmware/nodemcu_eye
pio run -t upload
```

## Unplugged Configuration Portal
1. Power the NodeMCU from any USB power bank or wall adapter.
2. Hold the **FLASH** button (`D3` / `GPIO0`) for 2 seconds (or boot with blank credentials if put into portal mode via serial command `PORTAL`).
3. Connect a phone/laptop to Wi-Fi `EYE-NODE-SETUP` and open `http://192.168.4.1` to enter your Wi-Fi SSID, password, `ai_server` URL (`http://<your-pc-ip>:8080/wifi/ingest`), mode, and privacy preference.

## Status LED Blink Patterns (`GPIO2` / `D4`)
* **Active (Live RF Scanning / Connected to Server):** Fast double-blink heartbeat every 1.0s (`65ms ON / 105ms OFF / 65ms ON`).
* **Not Active / Standby (Disconnected or Paused):** Slow single blink every 2.5s (`180ms ON / 2320ms OFF`).
* **Threat Alert (Deauth / Disassoc / Canary Hit):** Rapid alarm strobe (`60ms` toggle).
* **Setup Portal (`EYE-NODE-SETUP`):** Steady `300ms` toggle.

## USB Serial Control Commands (`115200` baud)
* `ACTIVE:1` / `ACTIVE:0` (switch between active heartbeat blink & slow standby blink)
* `MODE:PROMISC` / `MODE:LINK` / `MODE:HYBRID` / `MODE:CANARY`
* `CHANNEL:6` (locks channel 6 and disables hopping)
* `HOP:1` / `HOP:0`
* `PRIVACY:1` / `PRIVACY:0` (on-chip FNV-1a MAC anonymization)
* `SSID:<name>`, `PASS:<password>`, `URL:<http://host:8080/wifi/ingest>`
* `PORTAL` / `PING`

