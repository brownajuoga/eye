from __future__ import annotations

import asyncio
from io import BytesIO
from pathlib import Path
import struct
import sys
import unittest

from PIL import Image


TESTS_DIR = Path(__file__).resolve().parent
AI_SERVER_DIR = TESTS_DIR.parent / "ai_server"

if str(AI_SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVER_DIR))

import main as ai_main
from vision_renderer import render_vision_jpeg
from wifi_capture import parse_capture_bytes, slice_capture_into_frames
from wifi_engine import WifiEngine


class FakeUploadFile:
    def __init__(self, filename: str, contents: bytes, content_type: str = "application/octet-stream"):
        self.filename = filename
        self.content_type = content_type
        self._contents = contents

    async def read(self) -> bytes:
        return self._contents


def build_synthetic_radiotap_pcap() -> bytes:
    """Build a valid little-endian IEEE 802.11 + Radiotap PCAP with Beacon, ProbeReq, and Deauth frames."""
    # Global header: magic, major(2), minor(4), thiszone(0), sigfigs(0), snaplen(65535), linktype(127=Radiotap)
    pcap = bytearray(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 127))

    def add_pkt(ts_sec: int, rssi: int, freq_mhz: int, mac_frame: bytes) -> None:
        # Radiotap present flags: Channel(bit 3) + dBm Signal(bit 5) = 0x28
        rt_hdr = struct.pack("<BBHIHHb", 0, 0, 13, 0x00000028, freq_mhz, 0x00A0, rssi)
        full = rt_hdr + mac_frame
        pcap.extend(struct.pack("<IIII", ts_sec, 0, len(full), len(full)))
        pcap.extend(full)

    # Beacon on Ch 6 (2437 MHz), SSID "LabAP"
    bssid = b"\x50\x14\xc1\xe3\x76\x1c"
    beacon_hdr = struct.pack("<BBH", 0x80, 0x00, 0) + (b"\xff" * 6) + bssid + bssid + struct.pack("<H", 0)
    fixed_params = (b"\x00" * 10) + struct.pack("<H", 0x0011)  # privacy bit set
    ie_ssid = b"\x00\x05LabAP"
    add_pkt(1700000001, -44, 2437, beacon_hdr + fixed_params + ie_ssid)

    # Probe Request from randomized MAC
    client_mac = b"\xda\xa1\x19\x01\x02\x03"
    probe_hdr = struct.pack("<BBH", 0x40, 0x00, 0) + (b"\xff" * 6) + client_mac + (b"\xff" * 6) + struct.pack("<H", 16)
    add_pkt(1700000002, -59, 2437, probe_hdr + ie_ssid)

    # Deauth frame
    deauth_hdr = struct.pack("<BBH", 0xC0, 0x00, 0) + (b"\xff" * 6) + b"\xde\xad\xbe\xef\x00\x99" + bssid + struct.pack("<H", 32)
    add_pkt(1700000003, -49, 2437, deauth_hdr + b"\x07\x00")
    return bytes(pcap)


class WifiEngineAndApiTests(unittest.TestCase):
    def test_tripwire_disturbance_deauth_and_privacy_mode(self) -> None:
        engine = WifiEngine()
        policy = {
            "wifi": {
                "mode": "multi",
                "privacy_mode": True,
                "tripwire_z_threshold": 2.0,
                "deauth_rate_threshold": 4,
                "known_aps": {"LabAP": ["50:14:c1:e3:76:1c"]},
            }
        }

        # Establish quiet baseline
        for _ in range(5):
            engine.ingest_batch(
                [
                    {
                        "channel": 6,
                        "rssi": -45,
                        "frame_type": "mgmt",
                        "subtype": "beacon",
                        "sa": "50:14:c1:e3:76:1c",
                        "bssid": "50:14:c1:e3:76:1c",
                        "ssid": "LabAP",
                        "in_use": True,
                    }
                ],
                policy=policy,
            )

        # Inject sharp body crossing dip + deauth burst + rogue twin + client
        res = engine.ingest_batch(
            [
                {
                    "channel": 6,
                    "rssi": -66,
                    "frame_type": "mgmt",
                    "subtype": "beacon",
                    "sa": "50:14:c1:e3:76:1c",
                    "bssid": "50:14:c1:e3:76:1c",
                    "ssid": "LabAP",
                    "in_use": True,
                },
                {
                    "channel": 6,
                    "rssi": -58,
                    "frame_type": "mgmt",
                    "subtype": "probe_req",
                    "sa": "aa:bb:cc:11:22:33",
                    "bssid": "ff:ff:ff:ff:ff:ff",
                    "ssid": "SecretHome",
                },
                *[
                    {
                        "channel": 6,
                        "rssi": -49,
                        "frame_type": "mgmt",
                        "subtype": "deauth",
                        "sa": "de:ad:be:ef:00:99",
                        "bssid": "50:14:c1:e3:76:1c",
                        "ssid": "LabAP",
                    }
                    for _ in range(5)
                ],
                {
                    "channel": 6,
                    "rssi": -39,
                    "frame_type": "mgmt",
                    "subtype": "beacon",
                    "sa": "66:77:88:99:aa:bb",
                    "bssid": "66:77:88:99:aa:bb",
                    "ssid": "LabAP",
                    "security": "OPEN",
                },
            ],
            policy=policy,
        )

        labels = {d["label"] for d in res["detections"]}
        self.assertIn("rssi_tripwire_motion", labels)
        self.assertIn("deauth_flood", labels)
        self.assertIn("evil_twin", labels)
        self.assertIn("occupancy_present", labels)

        vision = res["vision"]
        self.assertTrue(vision["privacy_mode"])
        client_entities = [e for e in vision["entities"] if e["category"] == "client"]
        self.assertTrue(client_entities)
        self.assertTrue(client_entities[0]["bssid"].startswith("anon:"))
        self.assertEqual(client_entities[0]["ssid"], "")

        # Verify server-side Night-Vision JPEG rendering
        for palette in ("night_vision", "thermal", "radar"):
            jpeg = render_vision_jpeg(vision, palette_name=palette)
            im = Image.open(BytesIO(jpeg))
            self.assertEqual(im.size, (640, 420))

    def test_pcap_parser_and_slicing(self) -> None:
        pcap_bytes = build_synthetic_radiotap_pcap()
        obs = parse_capture_bytes(pcap_bytes, filename="test_capture.pcap")
        self.assertEqual(len(obs), 3)
        self.assertEqual(obs[0]["subtype"], "beacon")
        self.assertEqual(obs[0]["ssid"], "LabAP")
        self.assertEqual(obs[0]["channel"], 6)
        self.assertEqual(obs[0]["rssi"], -44)
        self.assertEqual(obs[1]["subtype"], "probe_req")
        self.assertTrue(obs[1]["randomized"])
        self.assertEqual(obs[2]["subtype"], "deauth")

        slices = slice_capture_into_frames(obs, bucket_seconds=1.0, max_frames=10)
        self.assertEqual(len(slices), 3)

    def test_fastapi_wifi_endpoints(self) -> None:
        import tempfile
        import shutil
        from policy import PolicyEngine

        async def run_test() -> None:
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp_cfg = Path(tmpdir) / "prompts.yaml"
                shutil.copy2(ai_main.CONFIG_PATH, tmp_cfg)
                orig_cfg_path = ai_main.CONFIG_PATH
                ai_main.CONFIG_PATH = tmp_cfg
                try:
                    async with ai_main.lifespan(ai_main.app):
                        # 1. Simulator step
                        sim_res = await ai_main.wifi_simulator({"action": "step", "scenario": "motion"})
                        self.assertIn("result", sim_res)
                        self.assertIn("vision", sim_res["result"])

                        # 2. PCAP upload & replay
                        pcap_bytes = build_synthetic_radiotap_pcap()
                        upload_summary = await ai_main.analyze_capture_or_video(
                            FakeUploadFile("demo.pcap", pcap_bytes)
                        )
                        self.assertEqual(upload_summary["frames_processed"], 3)
                        capture_id = upload_summary["capture_id"]

                        replay_res = await ai_main.wifi_replay({"action": "load_frame", "capture_id": capture_id, "frame_index": 0})
                        self.assertEqual(replay_res["frame_index"], 0)
                        self.assertEqual(replay_res["total_frames"], 3)

                        # 3. NodeMCU config & command queue
                        cfg_res = await ai_main.update_nodemcu_config(
                            {"mode": "link", "channel_hop": False, "locked_channel": 11, "privacy_mode": True}
                        )
                        self.assertIn("MODE:LINK", cfg_res["queued_commands"])
                        self.assertIn("CHANNEL:11", cfg_res["queued_commands"])
                        self.assertIn("PRIVACY:1", cfg_res["queued_commands"])
                        cmds = await ai_main.get_nodemcu_commands(consume=True)
                        self.assertTrue(len(cmds["commands"]) >= 3)

                        # 4. Vision & dashboard snapshot
                        vis = await ai_main.wifi_vision()
                        self.assertIn("vision", vis)
                        dash = await ai_main.dashboard()
                        self.assertIn("wifi_vision", dash)
                        self.assertIn("nodemcu", dash)
                finally:
                    ai_main.CONFIG_PATH = orig_cfg_path

        asyncio.run(run_test())


if __name__ == "__main__":
    unittest.main()
