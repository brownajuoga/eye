from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml


TESTS_DIR = Path(__file__).resolve().parent
EYE_ROOT = TESTS_DIR.parent
AI_SERVER_DIR = EYE_ROOT / "ai_server"

import sys

if str(AI_SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVER_DIR))

from agent import AgentLoop
from memory import MemoryStore
from policy import PolicyEngine


class PolicyMemoryAgentTests(unittest.TestCase):
    def test_policy_engine_reload_and_analysis(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "prompts.yaml"
            config_path.write_text(
                yaml.safe_dump(
                    {
                        "watch_for": ["person", "bottle"],
                        "ignore": ["chair"],
                        "rules": {"require_person": True, "min_confidence": 0.3},
                    }
                ),
                encoding="utf-8",
            )

            engine = PolicyEngine(config_path)
            event = engine.analyze_event(
                [
                    {"label": "person", "confidence": 0.91},
                    {"label": "bottle", "confidence": 0.88},
                    {"label": "chair", "confidence": 0.95},
                ]
            )

            self.assertTrue(event["important"])
            self.assertEqual(event["watch_matches"], ["bottle", "person"])
            self.assertEqual(event["ignored_objects"], ["chair"])

            config_path.write_text(
                yaml.safe_dump(
                    {
                        "watch_for": ["laptop"],
                        "ignore": ["chair"],
                        "rules": {"require_person": False, "min_confidence": 0.3},
                    }
                ),
                encoding="utf-8",
            )

            updated_event = engine.analyze_event([{"label": "laptop", "confidence": 0.9}])
            self.assertTrue(updated_event["important"])
            self.assertEqual(updated_event["watch_matches"], ["laptop"])

    def test_memory_filtering_and_agent_updates(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "prompts.yaml"
            config_path.write_text(
                yaml.safe_dump(
                    {
                        "watch_for": ["person"],
                        "rules": {
                            "require_person": False,
                            "min_confidence": 0.35,
                            "alert_on_repeated_labels": 3,
                            "repeated_label_window": 5,
                        },
                    }
                ),
                encoding="utf-8",
            )

            engine = PolicyEngine(config_path)
            memory = MemoryStore(max_events=20)
            agent = AgentLoop(engine, memory)

            for _ in range(3):
                record = memory.store_event(
                    detections=[{"label": "bottle", "confidence": 0.88}],
                    event={"important": True, "reason": "Matched watch list"},
                    expert_decision={"action": "alert", "reason": "test", "update_watch_for": [], "confidence": 0.8},
                    source="unit-test",
                )

            filtered = memory.filter(labels=["bottle"], actions=["alert"])
            self.assertEqual(len(filtered), 3)

            update = agent.process(
                record,
                {"action": "alert", "reason": "pattern", "update_watch_for": ["bag"], "confidence": 0.8},
            )
            self.assertIsNotNone(update)
            self.assertIn("bag", update["watch_for"])
            self.assertIn("hand", update["watch_for"])
            self.assertIn("bottle", update["watch_for"])
            self.assertLessEqual(update["rules"]["min_confidence"], 0.35)


if __name__ == "__main__":
    unittest.main()
