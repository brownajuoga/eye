from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import threading
import time
from typing import Any

import yaml


DEFAULT_POLICY = {
    "mode": "balanced",
    "model": {
        "default": "yolov8n.pt",
        "lightweight": "yolov8n.pt",
        "balanced": "yolov8n.pt",
        "performance": "yolov8n.pt",
        "custom": None,
        "confidence_threshold": 0.35,
    },
    "expert": {
        "backend": "mock",
        "ollama_model": "llava:7b",
        "transformers_model": "vikhyatk/moondream2",
        "max_retries": 2,
        "timeout_seconds": 20,
    },
    "memory": {
        "max_events": 500,
        "recent_limit": 10,
        "pattern_window": 25,
    },
    "watch_for": ["person", "bag", "backpack", "handbag", "cell phone", "bottle"],
    "ignore": ["chair", "couch", "bed"],
    "rules": {
        "require_person": False,
        "min_confidence": 0.35,
        "min_watch_matches": 1,
        "always_analyze": False,
        "alert_on_repeated_labels": 3,
        "repeated_label_window": 10,
    },
}


class PolicyEngine:
    def __init__(self, config_path: Path):
        self.config_path = Path(config_path)
        self._lock = threading.RLock()
        self._policy: dict[str, Any] = {}
        self._last_mtime = 0.0
        self._load(force=True)

    def get_policy(self) -> dict[str, Any]:
        self._load()
        with self._lock:
            return deepcopy(self._policy)

    def analyze_event(self, detections: list[dict[str, Any]]) -> dict[str, Any]:
        policy = self.get_policy()
        watch_for = set(policy.get("watch_for", []))
        ignore = set(policy.get("ignore", []))
        rules = policy.get("rules", {})
        min_confidence = float(rules.get("min_confidence", 0.0))

        relevant = [
            detection for detection in detections
            if float(detection.get("confidence", 0.0)) >= min_confidence
        ]
        labels = [str(item.get("label", "")) for item in relevant]
        filtered_labels = [label for label in labels if label not in ignore]

        matches = [label for label in filtered_labels if label in watch_for]
        unique_matches = sorted(set(matches))
        important = bool(matches)

        if rules.get("require_person") and "person" not in filtered_labels:
            important = False
            reason = "No person detected"
        elif len(matches) < int(rules.get("min_watch_matches", 1)):
            important = False
            reason = "No important objects detected"
        else:
            reason = f"Matched watch list: {', '.join(unique_matches)}" if unique_matches else "Policy requested expert review"

        if rules.get("always_analyze"):
            important = True
            if not unique_matches:
                reason = "Always analyze is enabled"

        return {
            "important": important,
            "reason": reason,
            "objects": labels,
            "filtered_objects": filtered_labels,
            "watch_matches": unique_matches,
            "ignored_objects": sorted({label for label in labels if label in ignore}),
        }

    def update_policy(
        self,
        *,
        add_watch_for: list[str] | None = None,
        remove_watch_for: list[str] | None = None,
        set_mode: str | None = None,
        rule_updates: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        self._load()
        with self._lock:
            policy = deepcopy(self._policy)
            changed = False

            if add_watch_for:
                current = set(policy.get("watch_for", []))
                additions = [item for item in add_watch_for if item and item not in current]
                if additions:
                    policy["watch_for"] = sorted(current.union(additions))
                    changed = True

            if remove_watch_for:
                current = set(policy.get("watch_for", []))
                removals = {item for item in remove_watch_for if item}
                updated = sorted(current.difference(removals))
                if updated != sorted(current):
                    policy["watch_for"] = updated
                    changed = True

            if set_mode and set_mode in {"lightweight", "balanced", "performance"}:
                if policy.get("mode") != set_mode:
                    policy["mode"] = set_mode
                    changed = True

            if rule_updates:
                merged_rules = dict(policy.get("rules", {}))
                for key, value in rule_updates.items():
                    if merged_rules.get(key) != value:
                        merged_rules[key] = value
                        changed = True
                policy["rules"] = merged_rules

            if not changed:
                return None

            self._write(policy)
            self._policy = policy
            return {
                "watch_for": policy.get("watch_for", []),
                "mode": policy.get("mode"),
                "rules": policy.get("rules", {}),
            }

    def _load(self, force: bool = False) -> None:
        with self._lock:
            current_mtime = self.config_path.stat().st_mtime if self.config_path.exists() else 0.0
            if not force and self._policy and current_mtime <= self._last_mtime:
                return

            raw = {}
            if self.config_path.exists():
                with self.config_path.open("r", encoding="utf-8") as handle:
                    raw = yaml.safe_load(handle) or {}

            merged = _deep_merge(deepcopy(DEFAULT_POLICY), raw)
            merged["watch_for"] = _normalize_string_list(merged.get("watch_for"))
            merged["ignore"] = _normalize_string_list(merged.get("ignore"))
            merged["mode"] = merged.get("mode", "balanced")
            self._policy = merged
            self._last_mtime = current_mtime or time.time()

    def _write(self, policy: dict[str, Any]) -> None:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with self.config_path.open("w", encoding="utf-8") as handle:
            yaml.safe_dump(policy, handle, sort_keys=False)
        self._last_mtime = self.config_path.stat().st_mtime


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            base[key] = _deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def _normalize_string_list(values: Any) -> list[str]:
    if not values:
        return []
    normalized = []
    for value in values:
        item = str(value).strip()
        if item and item not in normalized:
            normalized.append(item)
    return normalized
