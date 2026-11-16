from __future__ import annotations

import asyncio
import io
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

from PIL import Image


TESTS_DIR = Path(__file__).resolve().parent
AI_SERVER_DIR = TESTS_DIR.parent / "ai_server"

if str(AI_SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVER_DIR))

import main as ai_main


class FakeUploadFile:
    def __init__(self, filename: str, contents: bytes, content_type: str = "image/jpeg"):
        self.filename = filename
        self.content_type = content_type
        self._contents = contents

    async def read(self) -> bytes:
        return self._contents


class ApiTests(unittest.TestCase):
    def test_state_endpoint_returns_runtime(self) -> None:
        async def run_test() -> None:
            async with ai_main.lifespan(ai_main.app):
                payload = await ai_main.state()
                self.assertIn("policy", payload)
                self.assertIn("runtime", payload)

        asyncio.run(run_test())

    def test_analyze_endpoint_works_with_stubbed_detector(self) -> None:
        async def run_test() -> None:
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp_cfg = Path(tmpdir) / "prompts.yaml"
                shutil.copy2(ai_main.CONFIG_PATH, tmp_cfg)
                orig_cfg = ai_main.CONFIG_PATH
                ai_main.CONFIG_PATH = tmp_cfg
                try:
                    async with ai_main.lifespan(ai_main.app):
                        app_state = ai_main.app.state
                        app_state.policy_engine.patch_policy(
                            {
                                "watch_for": ["deauth_flood", "person"],
                                "expert": {"realtime_enabled": True},
                            }
                        )
                        app_state.detector.detect_objects = lambda *_args, **_kwargs: [
                            {"label": "person", "confidence": 0.95, "box": [0, 0, 10, 10]}
                        ]
                        app_state.expert_system.analyze = lambda **_kwargs: {
                            "action": "alert",
                            "reason": "stubbed expert",
                            "update_watch_for": ["evil_twin"],
                            "confidence": 0.9,
                        }
                        app_state.agent_loop.process = lambda *_args, **_kwargs: {
                            "watch_for": ["person", "evil_twin"],
                            "mode": "balanced",
                            "rules": {"min_confidence": 0.35},
                        }

                        image = Image.new("RGB", (16, 16), color="white")
                        buffer = io.BytesIO()
                        image.save(buffer, format="JPEG")
                        buffer.seek(0)

                        payload = await ai_main.analyze(
                            file=FakeUploadFile("frame.jpg", buffer.getvalue()),
                            source_id="default",
                            source_name="default",
                            live_source=True,
                        )

                        self.assertEqual(payload["expert"]["action"], "alert")
                        self.assertEqual(payload["event"]["important"], True)
                        self.assertIn("runtime", payload)
                finally:
                    ai_main.CONFIG_PATH = orig_cfg

        asyncio.run(run_test())


if __name__ == "__main__":
    unittest.main()
