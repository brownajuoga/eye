/*
 * eye - NodeMCU (ESP8266) Dual-Mode Wi-Fi RF Sensor Firmware
 *
 * Supports both:
 *  1) PLUGGED MODE (USB Serial): Continuous 802.11 promiscuous sniffing or
 *     link telemetry streamed as NDJSON over Serial to `scout` or `ai_server`.
 *  2) UNPLUGGED MODE (Standalone Wi-Fi):
 *     - LINK:   Stays connected to target Wi-Fi AP, sampling RSSI at ~10 Hz
 *               (ideal for real-time RSSI doorway/motion tripwire) + periodic scans.
 *     - HYBRID: Time-sliced promiscuous sniffing (sniff window -> Wi-Fi upload
 *               batch to POST /wifi/ingest -> repeat).
 *     - CANARY: Runs a decoy SoftAP alongside STA uplink and alerts immediately
 *               when a device connects or probes it.
 *
 * Interactive setup when unplugged:
 *  - Hold FLASH button (GPIO0 / D3) for 2 seconds (or boot with blank Wi-Fi)
 *    to start setup portal AP "EYE-NODE-SETUP" at http://192.168.4.1.
 */

#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <ESP8266WebServer.h>
#include <WiFiClient.h>
#include <EEPROM.h>

extern "C" {
  #include "user_interface.h"
}

// ---------- Default Compile-Time Settings (overridable via Serial or Portal) ----------
static const char* DEFAULT_WIFI_SSID = "";
static const char* DEFAULT_WIFI_PASS = "";
static const char* DEFAULT_SERVER_URL = "http://192.168.1.100:8080/wifi/ingest";
static const char* DEFAULT_CANARY_SSID = "EYE_CANARY_AP";

static const uint8_t PIN_ALERT_LED = LED_BUILTIN; // GPIO2 / D4 (active LOW on NodeMCU)
static const uint8_t PIN_FLASH_BTN = 0;           // GPIO0 / D3
static const uint32_t EEPROM_MAGIC = 0x45594538;  // "EYE8"

enum SensorMode : uint8_t {
  MODE_SERIAL_PROMISC = 0, // Plugged: continuous USB Serial 802.11 sniffer
  MODE_WIFI_LINK = 1,      // Unplugged: continuous AP link RSSI + scan telemetry
  MODE_WIFI_HYBRID = 2,    // Unplugged: sniff window -> Wi-Fi batch HTTP POST
  MODE_WIFI_CANARY = 3     // Unplugged/Plugged: STA + decoy Canary SoftAP alerts
};

struct EyeConfig {
  uint32_t magic;
  char node_id[24];
  char wifi_ssid[33];
  char wifi_pass[65];
  char server_url[96];
  char canary_ssid[33];
  uint8_t mode;
  uint8_t channel_hop;
  uint8_t locked_channel;
  uint8_t privacy_mode;
  uint16_t dwell_ms;
  uint16_t sniff_window_ms;
};

struct RxControl {
  signed rssi : 8;
  unsigned rate : 4;
  unsigned is_group : 1;
  unsigned : 1;
  unsigned sig_mode : 2;
  unsigned legacy_length : 12;
  unsigned damatch0 : 1;
  unsigned damatch1 : 1;
  unsigned bssidmatch0 : 1;
  unsigned bssidmatch1 : 1;
  unsigned MCS : 7;
  unsigned CWB : 1;
  unsigned HT_length : 16;
  unsigned Smoothing : 1;
  unsigned Not_Sounding : 1;
  unsigned : 1;
  unsigned Aggregation : 1;
  unsigned STBC : 2;
  unsigned FEC_CODING : 1;
  unsigned SGI : 1;
  unsigned rxend_state : 8;
  unsigned ampdu_cnt : 8;
  unsigned channel : 4;
  unsigned : 12;
};

struct sniffer_buf2 {
  struct RxControl rx_ctrl;
  uint8_t buf[112];
  uint16_t cnt;
  uint16_t len;
};

struct sniffer_buf_data {
  struct RxControl rx_ctrl;
  uint8_t buf[36];
  uint16_t cnt;
  uint16_t lenseq[1];
};

// Fixed-size lock-safe ring slot written inside promisc_cb (no String/heap!)
struct PacketSlot {
  int8_t rssi;
  uint8_t channel;
  uint8_t frame_type;    // 0=mgmt, 1=ctrl, 2=data
  uint8_t frame_subtype; // 8=beacon, 4=probe_req, 5=probe_resp, 12=deauth, 10=disassoc
  uint8_t rate;
  uint8_t mcs;
  uint8_t sig_mode;
  uint8_t cwb;
  uint16_t pkt_len;
  uint8_t sa[6];
  uint8_t bssid[6];
  char ssid[33];
  uint8_t has_ssid;
  uint8_t valid;
};

static const uint8_t RING_SIZE = 64;
static volatile PacketSlot g_ring[RING_SIZE];
static volatile uint8_t g_ring_head = 0;
static volatile uint8_t g_ring_tail = 0;
static volatile uint32_t g_dropped_packets = 0;

static EyeConfig g_cfg;
static ESP8266WebServer g_portal(80);
static bool g_portal_active = false;
static uint8_t g_current_channel = 1;
static unsigned long g_last_hop_ms = 0;
static unsigned long g_last_link_sample_ms = 0;
static unsigned long g_last_scan_ms = 0;
static unsigned long g_window_start_ms = 0;
static unsigned long g_btn_down_ms = 0;
static unsigned long g_led_off_ms = 0;

// Hybrid batch accumulator
static const uint8_t BATCH_MAX = 28;
static PacketSlot g_batch[BATCH_MAX];
static uint8_t g_batch_len = 0;

static String g_serial_line;
static String g_pending_canary_json;
static bool g_has_pending_canary = false;
static unsigned long g_last_http_post_ms = 0;
static WiFiEventHandler g_probe_handler;
static WiFiEventHandler g_sta_conn_handler;

// ---------- Helpers ----------
static void format_mac(const uint8_t* mac, bool privacy_hash, char* out, size_t out_len) {
  if (privacy_hash) {
    // Lightweight FNV-1a anonymized 24-bit tag (keeps local correlation, drops PII)
    uint32_t h = 2166136261u;
    for (int i = 0; i < 6; i++) {
      h ^= mac[i];
      h *= 16777619u;
    }
    snprintf(out, out_len, "anon:%02x:%02x:%02x", (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF);
    return;
  }
  snprintf(out, out_len, "%02x:%02x:%02x:%02x:%02x:%02x",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

static bool is_randomized_mac(const uint8_t* mac) {
  // Locally administered bit (bit 1 of first byte) and non-multicast
  return (mac[0] & 0x02) != 0 && (mac[0] & 0x01) == 0;
}

static const char* subtype_name(uint8_t ftype, uint8_t fsub) {
  if (ftype == 0) {
    switch (fsub) {
      case 0: return "assoc_req";
      case 4: return "probe_req";
      case 5: return "probe_resp";
      case 8: return "beacon";
      case 10: return "disassoc";
      case 11: return "auth";
      case 12: return "deauth";
      default: return "mgmt";
    }
  }
  if (ftype == 1) return "ctrl";
  if (ftype == 2) return "data";
  return "other";
}

static void json_escape(const char* in, char* out, size_t out_len) {
  size_t j = 0;
  for (size_t i = 0; in[i] != '\0' && j + 2 < out_len; i++) {
    char c = in[i];
    if (c == '"' || c == '\\') {
      if (j + 3 >= out_len) break;
      out[j++] = '\\';
      out[j++] = c;
    } else if ((uint8_t)c >= 0x20 && (uint8_t)c < 0x7F) {
      out[j++] = c;
    }
  }
  out[j] = '\0';
}

static void pulse_alert_led(uint16_t ms = 120) {
  digitalWrite(PIN_ALERT_LED, LOW);
  g_led_off_ms = millis() + ms;
}

// ---------- Promiscuous RX Callback (kept fast & heap-free!) ----------
static void ICACHE_FLASH_ATTR promisc_cb(uint8_t* buf, uint16_t len) {
  if (len == 12 || buf == nullptr) {
    return;
  }

  uint8_t next_head = (g_ring_head + 1) % RING_SIZE;
  if (next_head == g_ring_tail) {
    g_dropped_packets++;
    return;
  }

  const struct RxControl* rx = (const struct RxControl*)buf;
  const uint8_t* payload = nullptr;
  uint16_t payload_cap = 0;
  uint16_t actual_len = 0;

  if (len == sizeof(struct sniffer_buf2)) {
    const struct sniffer_buf2* s2 = (const struct sniffer_buf2*)buf;
    payload = s2->buf;
    payload_cap = sizeof(s2->buf);
    actual_len = s2->len;
  } else if (len >= sizeof(struct RxControl) + 24) {
    const struct sniffer_buf_data* sd = (const struct sniffer_buf_data*)buf;
    payload = sd->buf;
    payload_cap = sizeof(sd->buf);
    actual_len = rx->sig_mode ? rx->HT_length : rx->legacy_length;
  } else {
    return;
  }

  if (payload_cap < 24) return;

  uint8_t fc0 = payload[0];
  uint8_t fc1 = payload[1];
  uint8_t ftype = (fc0 >> 2) & 0x03;
  uint8_t fsub = (fc0 >> 4) & 0x0F;

  volatile PacketSlot& slot = g_ring[g_ring_head];
  slot.rssi = rx->rssi;
  slot.channel = g_current_channel;
  slot.frame_type = ftype;
  slot.frame_subtype = fsub;
  slot.rate = rx->rate;
  slot.mcs = rx->MCS;
  slot.sig_mode = rx->sig_mode;
  slot.cwb = rx->CWB;
  slot.pkt_len = actual_len;
  slot.has_ssid = 0;
  slot.ssid[0] = '\0';

  // Address extraction based on IEEE 802.11 ToDS / FromDS flags
  uint8_t to_ds = fc1 & 0x01;
  uint8_t from_ds = (fc1 >> 1) & 0x01;
  const uint8_t* addr1 = payload + 4;
  const uint8_t* addr2 = payload + 10;
  const uint8_t* addr3 = payload + 16;

  for (int i = 0; i < 6; i++) {
    slot.sa[i] = addr2[i];
    if (ftype == 0) {
      slot.bssid[i] = addr3[i];
    } else if (to_ds == 0 && from_ds == 1) {
      slot.bssid[i] = addr2[i];
    } else if (to_ds == 1 && from_ds == 0) {
      slot.bssid[i] = addr1[i];
    } else {
      slot.bssid[i] = addr3[i];
    }
  }

  // Extract SSID Information Element (tag 0) on Beacon (8), ProbeReq (4), ProbeResp (5)
  if (ftype == 0 && (fsub == 8 || fsub == 4 || fsub == 5)) {
    uint16_t ie_offset = (fsub == 4) ? 24 : 36; // Beacon/ProbeResp have 12-byte fixed params
    if (ie_offset + 2 < payload_cap) {
      uint16_t pos = ie_offset;
      while (pos + 2 <= payload_cap) {
        uint8_t tag = payload[pos];
        uint8_t tag_len = payload[pos + 1];
        if (tag == 0) {
          uint8_t copy_len = tag_len;
          if (copy_len > 32) copy_len = 32;
          if (pos + 2 + copy_len <= payload_cap) {
            for (uint8_t k = 0; k < copy_len; k++) {
              slot.ssid[k] = (char)payload[pos + 2 + k];
            }
            slot.ssid[copy_len] = '\0';
            slot.has_ssid = 1;
          }
          break;
        }
        if (pos + 2 + tag_len > payload_cap) break;
        pos += 2 + tag_len;
      }
    }
  }

  slot.valid = 1;
  g_ring_head = next_head;
}

// ---------- Persistence ----------
static void load_default_config() {
  memset(&g_cfg, 0, sizeof(g_cfg));
  g_cfg.magic = EEPROM_MAGIC;
  snprintf(g_cfg.node_id, sizeof(g_cfg.node_id), "nodemcu-%06x", ESP.getChipId());
  strncpy(g_cfg.wifi_ssid, DEFAULT_WIFI_SSID, sizeof(g_cfg.wifi_ssid) - 1);
  strncpy(g_cfg.wifi_pass, DEFAULT_WIFI_PASS, sizeof(g_cfg.wifi_pass) - 1);
  strncpy(g_cfg.server_url, DEFAULT_SERVER_URL, sizeof(g_cfg.server_url) - 1);
  strncpy(g_cfg.canary_ssid, DEFAULT_CANARY_SSID, sizeof(g_cfg.canary_ssid) - 1);
  g_cfg.mode = (strlen(DEFAULT_WIFI_SSID) > 0) ? MODE_WIFI_HYBRID : MODE_SERIAL_PROMISC;
  g_cfg.channel_hop = 1;
  g_cfg.locked_channel = 6;
  g_cfg.privacy_mode = 0;
  g_cfg.dwell_ms = 250;
  g_cfg.sniff_window_ms = 3000;
}

static void save_config() {
  EEPROM.put(0, g_cfg);
  EEPROM.commit();
}

static void load_config() {
  EEPROM.begin(sizeof(EyeConfig) + 16);
  EEPROM.get(0, g_cfg);
  if (g_cfg.magic != EEPROM_MAGIC) {
    load_default_config();
    save_config();
  }
  if (g_cfg.dwell_ms < 80) g_cfg.dwell_ms = 250;
  if (g_cfg.sniff_window_ms < 1000) g_cfg.sniff_window_ms = 3000;
  if (g_cfg.locked_channel < 1 || g_cfg.locked_channel > 13) g_cfg.locked_channel = 6;
}

// ---------- Telemetry Formatting ----------
static String format_slot_json(const PacketSlot& s) {
  char sa_str[24];
  char bssid_str[24];
  char ssid_esc[72];
  format_mac(s.sa, g_cfg.privacy_mode != 0, sa_str, sizeof(sa_str));
  format_mac(s.bssid, g_cfg.privacy_mode != 0, bssid_str, sizeof(bssid_str));
  json_escape(s.ssid, ssid_esc, sizeof(ssid_esc));

  String out;
  out.reserve(240);
  out += "{\"node_id\":\"";
  out += g_cfg.node_id;
  out += "\",\"source\":\"nodemcu_esp8266\",\"ts_ms\":";
  out += String(millis());
  out += ",\"channel\":";
  out += String(s.channel);
  out += ",\"rssi\":";
  out += String(s.rssi);
  out += ",\"frame_type\":\"";
  out += (s.frame_type == 0 ? "mgmt" : (s.frame_type == 1 ? "ctrl" : "data"));
  out += "\",\"subtype\":\"";
  out += subtype_name(s.frame_type, s.frame_subtype);
  out += "\",\"sa\":\"";
  out += sa_str;
  out += "\",\"bssid\":\"";
  out += bssid_str;
  out += "\",\"ssid\":\"";
  out += ssid_esc;
  out += "\",\"randomized\":";
  out += (is_randomized_mac(s.sa) ? "true" : "false");
  out += ",\"rate\":";
  out += String(s.sig_mode ? s.mcs : s.rate);
  out += ",\"pkt_len\":";
  out += String(s.pkt_len);
  out += ",\"privacy\":";
  out += (g_cfg.privacy_mode ? "true" : "false");
  out += "}";
  return out;
}

static void emit_serial_status(const char* event_name) {
  Serial.print("{\"type\":\"status\",\"node_id\":\"");
  Serial.print(g_cfg.node_id);
  Serial.print("\",\"event\":\"");
  Serial.print(event_name);
  Serial.print("\",\"mode\":");
  Serial.print(g_cfg.mode);
  Serial.print(",\"channel\":");
  Serial.print(g_current_channel);
  Serial.print(",\"hop\":");
  Serial.print(g_cfg.channel_hop ? "true" : "false");
  Serial.print(",\"privacy\":");
  Serial.print(g_cfg.privacy_mode ? "true" : "false");
  Serial.print(",\"dropped\":");
  Serial.print(g_dropped_packets);
  Serial.println("}");
}

// ---------- Mode Switching & Wi-Fi Helpers ----------
static void start_promiscuous() {
  WiFi.disconnect(false);
  WiFi.mode(WIFI_STA);
  wifi_set_opmode(STATION_MODE);
  wifi_promiscuous_enable(0);
  g_current_channel = g_cfg.channel_hop ? 1 : g_cfg.locked_channel;
  wifi_set_channel(g_current_channel);
  wifi_set_promiscuous_rx_cb(promisc_cb);
  wifi_promiscuous_enable(1);
  g_window_start_ms = millis();
  g_last_hop_ms = millis();
}

static void stop_promiscuous() {
  wifi_promiscuous_enable(0);
}

static bool connect_sta(uint16_t timeout_ms = 10000) {
  if (strlen(g_cfg.wifi_ssid) == 0) return false;
  if (WiFi.status() == WL_CONNECTED) return true;

  stop_promiscuous();
  WiFi.mode(g_cfg.mode == MODE_WIFI_CANARY ? WIFI_AP_STA : WIFI_STA);
  WiFi.begin(g_cfg.wifi_ssid, g_cfg.wifi_pass);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < timeout_ms) {
    delay(150);
  }
  return WiFi.status() == WL_CONNECTED;
}

static bool post_json_to_server(const String& payload) {
  if (!connect_sta()) return false;
  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, g_cfg.server_url)) {
    return false;
  }
  http.setTimeout(3500);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(payload);
  http.end();
  return code >= 200 && code < 300;
}

static void setup_canary_handlers() {
  g_probe_handler = WiFi.onSoftAPModeProbeRequestReceived([](const WiFiEventSoftAPModeProbeRequestReceived& evt) {
    pulse_alert_led(250);
    char mac_str[24];
    format_mac(evt.mac, g_cfg.privacy_mode != 0, mac_str, sizeof(mac_str));
    String line = "{\"node_id\":\"" + String(g_cfg.node_id) +
                  "\",\"source\":\"nodemcu_canary\",\"channel\":" + String(WiFi.channel()) +
                  ",\"rssi\":" + String(evt.rssi) +
                  ",\"frame_type\":\"mgmt\",\"subtype\":\"canary_probe\",\"sa\":\"" +
                  String(mac_str) + "\",\"ssid\":\"" + String(g_cfg.canary_ssid) + "\"}";
    Serial.println(line);
  });

  g_sta_conn_handler = WiFi.onSoftAPModeStationConnected([](const WiFiEventSoftAPModeStationConnected& evt) {
    pulse_alert_led(600);
    char mac_str[24];
    format_mac(evt.mac, g_cfg.privacy_mode != 0, mac_str, sizeof(mac_str));
    String msg = "{\"source_id\":\"" + String(g_cfg.node_id) +
                 "\",\"source_name\":\"NodeMCU Canary AP\",\"observations\":[{\"node_id\":\"" +
                 String(g_cfg.node_id) + "\",\"source\":\"nodemcu_canary\",\"channel\":" +
                 String(WiFi.channel()) + ",\"rssi\":-45,\"frame_type\":\"mgmt\",\"subtype\":\"canary_assoc\",\"sa\":\"" +
                 String(mac_str) + "\",\"ssid\":\"" + String(g_cfg.canary_ssid) + "\"}]}";
    Serial.println(msg);
    g_pending_canary_json = msg;
    g_has_pending_canary = true;
  });
}

static void apply_runtime_mode() {
  g_portal_active = false;
  g_portal.stop();
  g_batch_len = 0;

  if (g_cfg.mode == MODE_SERIAL_PROMISC || g_cfg.mode == MODE_WIFI_HYBRID) {
    start_promiscuous();
    emit_serial_status("mode_promiscuous");
  } else if (g_cfg.mode == MODE_WIFI_LINK) {
    connect_sta();
    emit_serial_status("mode_link_tripwire");
  } else if (g_cfg.mode == MODE_WIFI_CANARY) {
    stop_promiscuous();
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(g_cfg.canary_ssid);
    connect_sta(6000);
    setup_canary_handlers();
    emit_serial_status("mode_canary_ap");
  }
}

// ---------- Captive Setup Portal (for Unplugged Configuration) ----------
static void start_setup_portal() {
  stop_promiscuous();
  WiFi.disconnect(true);
  WiFi.mode(WIFI_AP);
  WiFi.softAP("EYE-NODE-SETUP");
  g_portal_active = true;

  g_portal.on("/", HTTP_GET, []() {
    String html = "<html><head><title>eye NodeMCU Setup</title></head><body style='font-family:sans-serif;max-width:480px;margin:24px auto;background:#0a1812;color:#b8f5c8'>"
                  "<h2>eye NodeMCU RF Sensor</h2>"
                  "<form method='POST' action='/save'>"
                  "<p>Wi-Fi SSID:<br><input name='ssid' value='" + String(g_cfg.wifi_ssid) + "' style='width:100%'></p>"
                  "<p>Wi-Fi Password:<br><input name='pass' type='password' value='" + String(g_cfg.wifi_pass) + "' style='width:100%'></p>"
                  "<p>Server Ingest URL:<br><input name='url' value='" + String(g_cfg.server_url) + "' style='width:100%'></p>"
                  "<p>Mode (0=USB Serial, 1=Unplugged Link, 2=Unplugged Hybrid WIDS, 3=Canary AP):<br><input name='mode' value='" + String(g_cfg.mode) + "'></p>"
                  "<p>Privacy Mode (0/1):<br><input name='priv' value='" + String(g_cfg.privacy_mode) + "'></p>"
                  "<button type='submit' style='padding:10px 18px;background:#00cc66;border:none;font-weight:bold'>Save & Start</button>"
                  "</form></body></html>";
    g_portal.send(200, "text/html", html);
  });

  g_portal.on("/save", HTTP_POST, []() {
    if (g_portal.hasArg("ssid")) strncpy(g_cfg.wifi_ssid, g_portal.arg("ssid").c_str(), sizeof(g_cfg.wifi_ssid) - 1);
    if (g_portal.hasArg("pass")) strncpy(g_cfg.wifi_pass, g_portal.arg("pass").c_str(), sizeof(g_cfg.wifi_pass) - 1);
    if (g_portal.hasArg("url")) strncpy(g_cfg.server_url, g_portal.arg("url").c_str(), sizeof(g_cfg.server_url) - 1);
    if (g_portal.hasArg("mode")) g_cfg.mode = (uint8_t)g_portal.arg("mode").toInt();
    if (g_portal.hasArg("priv")) g_cfg.privacy_mode = (uint8_t)g_portal.arg("priv").toInt();
    save_config();
    g_portal.send(200, "text/html", "<html><body><h3>Saved! Sensor switching to active mode...</h3></body></html>");
    delay(400);
    apply_runtime_mode();
  });

  g_portal.begin();
  emit_serial_status("portal_started");
}

// ---------- Serial Command Interface (from `scout` or terminal) ----------
static void handle_serial_command(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;

  if (cmd.startsWith("CHANNEL:")) {
    int ch = cmd.substring(8).toInt();
    if (ch >= 1 && ch <= 13) {
      g_cfg.channel_hop = 0;
      g_cfg.locked_channel = (uint8_t)ch;
      g_current_channel = (uint8_t)ch;
      wifi_set_channel(g_current_channel);
      save_config();
      emit_serial_status("channel_locked");
    }
  } else if (cmd == "HOP:1" || cmd == "HOP:ON") {
    g_cfg.channel_hop = 1;
    save_config();
    emit_serial_status("hop_enabled");
  } else if (cmd == "HOP:0" || cmd == "HOP:OFF") {
    g_cfg.channel_hop = 0;
    wifi_set_channel(g_cfg.locked_channel);
    save_config();
    emit_serial_status("hop_disabled");
  } else if (cmd == "PRIVACY:1") {
    g_cfg.privacy_mode = 1;
    save_config();
    emit_serial_status("privacy_on");
  } else if (cmd == "PRIVACY:0") {
    g_cfg.privacy_mode = 0;
    save_config();
    emit_serial_status("privacy_off");
  } else if (cmd == "MODE:SERIAL" || cmd == "MODE:PROMISC") {
    g_cfg.mode = MODE_SERIAL_PROMISC;
    save_config();
    apply_runtime_mode();
  } else if (cmd == "MODE:LINK") {
    g_cfg.mode = MODE_WIFI_LINK;
    save_config();
    apply_runtime_mode();
  } else if (cmd == "MODE:HYBRID") {
    g_cfg.mode = MODE_WIFI_HYBRID;
    save_config();
    apply_runtime_mode();
  } else if (cmd == "MODE:CANARY") {
    g_cfg.mode = MODE_WIFI_CANARY;
    save_config();
    apply_runtime_mode();
  } else if (cmd.startsWith("SSID:")) {
    strncpy(g_cfg.wifi_ssid, cmd.substring(5).c_str(), sizeof(g_cfg.wifi_ssid) - 1);
    save_config();
    emit_serial_status("ssid_updated");
  } else if (cmd.startsWith("PASS:")) {
    strncpy(g_cfg.wifi_pass, cmd.substring(5).c_str(), sizeof(g_cfg.wifi_pass) - 1);
    save_config();
    emit_serial_status("pass_updated");
  } else if (cmd.startsWith("URL:")) {
    strncpy(g_cfg.server_url, cmd.substring(4).c_str(), sizeof(g_cfg.server_url) - 1);
    save_config();
    emit_serial_status("url_updated");
  } else if (cmd == "PORTAL") {
    start_setup_portal();
  } else if (cmd == "PING") {
    emit_serial_status("pong");
  }
}

static void poll_serial_commands() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (g_serial_line.length() > 0) {
        handle_serial_command(g_serial_line);
        g_serial_line = "";
      }
    } else if (g_serial_line.length() < 160) {
      g_serial_line += c;
    }
  }
}

static void flush_hybrid_batch() {
  if (g_batch_len == 0 || strlen(g_cfg.wifi_ssid) == 0) {
    g_batch_len = 0;
    return;
  }
  String body;
  body.reserve(g_batch_len * 200 + 128);
  body += "{\"source_id\":\"";
  body += g_cfg.node_id;
  body += "\",\"source_name\":\"NodeMCU Unplugged\",\"live_source\":true,\"observations\":[";
  for (uint8_t i = 0; i < g_batch_len; i++) {
    if (i > 0) body += ",";
    body += format_slot_json(g_batch[i]);
  }
  body += "]}";
  post_json_to_server(body);
  g_batch_len = 0;
}

static void drain_ring_buffer() {
  uint8_t processed = 0;
  while (g_ring_tail != g_ring_head && processed < 16) {
    PacketSlot copy;
    memcpy((void*)&copy, (const void*)&g_ring[g_ring_tail], sizeof(PacketSlot));
    g_ring[g_ring_tail].valid = 0;
    g_ring_tail = (g_ring_tail + 1) % RING_SIZE;
    processed++;

    // Flash onboard LED immediately on deauth/disassoc threat frames
    if (copy.frame_type == 0 && (copy.frame_subtype == 12 || copy.frame_subtype == 10)) {
      pulse_alert_led(150);
    }

    if (g_cfg.mode == MODE_SERIAL_PROMISC) {
      Serial.println(format_slot_json(copy));
    } else if (g_cfg.mode == MODE_WIFI_HYBRID) {
      if (g_batch_len < BATCH_MAX) {
        g_batch[g_batch_len++] = copy;
      }
    }
  }
}

// ---------- Arduino Entrypoints ----------
void setup() {
  pinMode(PIN_ALERT_LED, OUTPUT);
  digitalWrite(PIN_ALERT_LED, HIGH);
  pinMode(PIN_FLASH_BTN, INPUT_PULLUP);

  Serial.begin(115200);
  delay(80);
  load_config();
  apply_runtime_mode();
}

void loop() {
  unsigned long now = millis();

  if (g_led_off_ms != 0 && now >= g_led_off_ms) {
    digitalWrite(PIN_ALERT_LED, HIGH);
    g_led_off_ms = 0;
  }

  // Hold FLASH button >= 2s to open captive portal when unplugged
  if (digitalRead(PIN_FLASH_BTN) == LOW) {
    if (g_btn_down_ms == 0) g_btn_down_ms = now;
    if (now - g_btn_down_ms >= 2000 && !g_portal_active) {
      start_setup_portal();
    }
  } else {
    g_btn_down_ms = 0;
  }

  poll_serial_commands();

  if (g_portal_active) {
    g_portal.handleClient();
    return;
  }

  if (g_has_pending_canary) {
    String canary_payload = g_pending_canary_json;
    g_has_pending_canary = false;
    post_json_to_server(canary_payload);
  }

  if (g_cfg.mode == MODE_SERIAL_PROMISC || g_cfg.mode == MODE_WIFI_HYBRID) {
    drain_ring_buffer();

    if (g_cfg.channel_hop && now - g_last_hop_ms >= g_cfg.dwell_ms) {
      g_current_channel = (g_current_channel % 13) + 1;
      wifi_set_channel(g_current_channel);
      g_last_hop_ms = now;
    }

    if (g_cfg.mode == MODE_WIFI_HYBRID && now - g_window_start_ms >= g_cfg.sniff_window_ms) {
      stop_promiscuous();
      flush_hybrid_batch();
      start_promiscuous();
    }
  } else if (g_cfg.mode == MODE_WIFI_LINK || g_cfg.mode == MODE_WIFI_CANARY) {
    static String link_batch;
    static uint8_t link_count = 0;

    if (now - g_last_link_sample_ms >= 150) {
      g_last_link_sample_ms = now;
      if (connect_sta(2000)) {
        String bssid = WiFi.BSSIDstr();
        String ssid = WiFi.SSID();
        int rssi = WiFi.RSSI();
        int ch = WiFi.channel();
        String obs = "{\"node_id\":\"" + String(g_cfg.node_id) +
                     "\",\"source\":\"nodemcu_link\",\"channel\":" + String(ch) +
                     ",\"rssi\":" + String(rssi) +
                     ",\"frame_type\":\"data\",\"subtype\":\"link_sample\",\"sa\":\"" +
                     WiFi.macAddress() + "\",\"bssid\":\"" + bssid +
                     "\",\"ssid\":\"" + ssid + "\",\"privacy\":" +
                     (g_cfg.privacy_mode ? "true" : "false") + "}";
        Serial.println(obs);

        if (link_count > 0) link_batch += ",";
        link_batch += obs;
        link_count++;

        if (now - g_last_http_post_ms >= 500 || link_count >= 4) {
          g_last_http_post_ms = now;
          String payload = "{\"source_id\":\"" + String(g_cfg.node_id) +
                           "\",\"source_name\":\"NodeMCU Link Tripwire\",\"live_source\":true,\"observations\":[" +
                           link_batch + "]}";
          post_json_to_server(payload);
          link_batch = "";
          link_count = 0;
        }
      }
    }

    if (now - g_last_scan_ms >= 6000) {
      g_last_scan_ms = now;
      int n = WiFi.scanNetworks(false, true);
      if (n > 0) {
        String arr = "[";
        int limit = n > 12 ? 12 : n;
        for (int i = 0; i < limit; i++) {
          if (i > 0) arr += ",";
          arr += "{\"node_id\":\"" + String(g_cfg.node_id) +
                 "\",\"source\":\"nodemcu_scan\",\"channel\":" + String(WiFi.channel(i)) +
                 ",\"rssi\":" + String(WiFi.RSSI(i)) +
                 ",\"frame_type\":\"mgmt\",\"subtype\":\"beacon\",\"sa\":\"" +
                 WiFi.BSSIDstr(i) + "\",\"bssid\":\"" + WiFi.BSSIDstr(i) +
                 "\",\"ssid\":\"" + WiFi.SSID(i) + "\"}";
        }
        arr += "]";
        post_json_to_server("{\"source_id\":\"" + String(g_cfg.node_id) +
                            "\",\"source_name\":\"NodeMCU Spectrum Scan\",\"live_source\":true,\"observations\":" +
                            arr + "}");
        WiFi.scanDelete();
      }
    }
  }
}
