from __future__ import annotations

import unittest
from pathlib import Path

from fastapi.testclient import TestClient
from PIL import Image

import io
import sys


TESTS_DIR = Path(__file__).resolve().parent
AI_SERVER_DIR = TESTS_DIR.parent / "ai_server"

if str(AI_SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVER_DIR))

import main as ai_main


class ApiTests(unittest.TestCase):
    def test_state_endpoint_returns_runtime(self) -> None:
        with TestClient(ai_main.app) as client:
            response = client.get("/state")
            self.assertEqual(response.status_code, 200)
            payload = response.json()
            self.assertIn("policy", payload)
            self.assertIn("runtime", payload)

    def test_analyze_endpoint_works_with_stubbed_detector(self) -> None:
        with TestClient(ai_main.app) as client:
            app_state = client.app.state
            app_state.detector.detect_objects = lambda *_args, **_kwargs: [
                {"label": "person", "confidence": 0.95, "box": [0, 0, 10, 10]}
            ]
            app_state.expert_system.analyze = lambda **_kwargs: {
                "action": "alert",
                "reason": "stubbed expert",
                "update_watch_for": ["bag"],
                "confidence": 0.9,
            }
            app_state.agent_loop.process = lambda *_args, **_kwargs: {
                "watch_for": ["person", "bag"],
                "mode": "balanced",
                "rules": {"min_confidence": 0.35},
            }

            image = Image.new("RGB", (16, 16), color="white")
            buffer = io.BytesIO()
            image.save(buffer, format="JPEG")
            buffer.seek(0)

            response = client.post(
                "/analyze",
                files={"file": ("frame.jpg", buffer.getvalue(), "image/jpeg")},
            )

            self.assertEqual(response.status_code, 200)
            payload = response.json()
            self.assertEqual(payload["expert"]["action"], "alert")
            self.assertEqual(payload["event"]["important"], True)
            self.assertIn("runtime", payload)


if __name__ == "__main__":
    unittest.main()
