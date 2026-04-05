from __future__ import annotations

from typing import Any

from memory import MemoryStore
from policy import PolicyEngine


class AgentLoop:
    def __init__(self, policy_engine: PolicyEngine, memory_store: MemoryStore):
        self.policy_engine = policy_engine
        self.memory_store = memory_store

    def process(
        self,
        record: dict[str, Any],
        expert_decision: dict[str, Any],
    ) -> dict[str, Any] | None:
        policy = self.policy_engine.get_policy()
        pattern_window = int(policy["rules"].get("repeated_label_window", policy["memory"].get("pattern_window", 25)))
        label_counts = self.memory_store.recent_label_counts(limit=pattern_window)
        repeated_threshold = int(policy["rules"].get("alert_on_repeated_labels", 3))

        add_watch_for = list(expert_decision.get("update_watch_for", []))
        rule_updates: dict[str, Any] = {}
        control_patch = expert_decision.get("control") if isinstance(expert_decision.get("control"), dict) else {}

        if label_counts.get("bottle", 0) >= repeated_threshold:
            for label in ("hand", "bag", "bottle"):
                if label not in add_watch_for:
                    add_watch_for.append(label)

        if expert_decision.get("action") == "alert" and record["event"].get("important"):
            current_threshold = float(policy["rules"].get("min_confidence", 0.35))
            if current_threshold > 0.2:
                rule_updates["min_confidence"] = round(max(0.2, current_threshold - 0.02), 2)

        if not add_watch_for and not rule_updates:
            return None

        return self.policy_engine.update_policy(
            add_watch_for=add_watch_for,
            set_mode=control_patch.get("mode") if isinstance(control_patch.get("mode"), str) else None,
            rule_updates=rule_updates or None,
        )
