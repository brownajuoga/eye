from __future__ import annotations

import unittest
from pathlib import Path

import sys


TESTS_DIR = Path(__file__).resolve().parent
AI_SERVER_DIR = TESTS_DIR.parent / "ai_server"

if str(AI_SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVER_DIR))

from expert import ExpertSystem, build_fallback_decision, normalize_expert_output


class ExpertTests(unittest.TestCase):
    def test_normalize_expert_output_from_jsonish_text(self) -> None:
        raw = 'noise before {"action":"alert","reason":"suspicious","update_watch_for":["bag","bag"],"confidence":1.2} noise'
        normalized = normalize_expert_output(raw, fallback_reason="fallback")

        self.assertEqual(normalized["action"], "alert")
        self.assertEqual(normalized["reason"], "suspicious")
        self.assertEqual(normalized["update_watch_for"], ["bag"])
        self.assertEqual(normalized["confidence"], 1.0)

    def test_expert_system_falls_back_after_backend_failure(self) -> None:
        expert = ExpertSystem()
        expert._run_backend = lambda **_: (_ for _ in ()).throw(RuntimeError("boom"))

        decision = expert.analyze(
            image_bytes=b"fake",
            detections=[{"label": "person", "confidence": 0.9}],
            memory=[],
            policy={"expert": {"backend": "mock", "max_retries": 1, "timeout_seconds": 1}},
            event={"important": True},
        )

        self.assertEqual(decision["action"], "alert")
        self.assertIn("failed", decision["reason"])

    def test_build_fallback_decision_ignore_without_person(self) -> None:
        decision = build_fallback_decision(
            detections=[{"label": "bottle", "confidence": 0.8}],
            event={"important": True},
            reason="bad json",
        )
        self.assertEqual(decision["action"], "ignore")
        self.assertEqual(decision["reason"], "bad json")


if __name__ == "__main__":
    unittest.main()
