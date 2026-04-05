from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import threading
import time
from typing import Any

import yaml


DEFAULT_POLICY = {
    "mode": "balanced",
    "controls": {
        "detection_enabled": True,
        "auto_mode": True,
        "confidence_threshold": 0.35,
        "iou_threshold": 0.5,
    },
    "model": {
        "default": "yolov8n.pt",
        "lightweight": "yolov8n.pt",
        "balanced": "yolov8n.pt",
        "performance": "yolov8n.pt",
        "custom": None,
        "confidence_threshold": 0.35,
    },
    "expert": {
        "backend": "ollama",
        "ollama_model": "llava:7b-v1.6",
        "transformers_model": "vikhyatk/moondream2",
        "max_retries": 2,
        "timeout_seconds": 20,
        "task_profile": "general",
        "mission": "Monitor the scene, reason about meaningful activity, and adapt system behavior when patterns emerge.",
        "operator_instructions": "",
        "active_task": "Autonomously monitor the environment while staying controllable by the user.",
    },
    "memory": {
        "max_events": 500,
        "recent_limit": 10,
        "pattern_window": 25,
    },
    "watch_for": ["person", "bag", "backpack", "handbag", "cell phone", "bottle"],
    "ignore": ["chair", "couch", "bed"],
    "video_analysis": {
        "sample_interval_seconds": 1.0,
        "max_frames": 8,
    },
    "ui": {
        "refresh_interval_seconds": 2.0,
        "default_feed_id": "",
    },
    "task_routing": {
        "general_question": {
            "mode": "balanced",
            "expert_backend": "ollama",
            "preferred_model": "yolov8n.pt",
            "feed_strategy": "latest",
        },
        "object_search": {
            "mode": "performance",
            "expert_backend": "ollama",
            "preferred_model": "yolo11n.pt",
            "feed_strategy": "all_feeds",
        },
        "event_time_query": {
            "mode": "balanced",
            "expert_backend": "ollama",
            "preferred_model": "yolov8n.pt",
            "feed_strategy": "selected",
        },
        "resource_switch": {
            "mode": "balanced",
            "expert_backend": "ollama",
            "preferred_model": "yolo11n.pt",
            "feed_strategy": "latest",
        },
    },
    "automation_rules": [
        {
            "name": "Person Alert",
            "condition": "IF person detected with confidence > 0.60",
            "action": "Create alert and keep balanced mode active",
            "enabled": True,
        },
        {
            "name": "Idle Optimization",
            "condition": "IF no objects for 120 seconds",
            "action": "Reduce analysis frequency and mark system idle",
            "enabled": True,
        },
    ],
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

    def patch_policy(self, updates: dict[str, Any]) -> dict[str, Any]:
        self._load()
        with self._lock:
            next_policy = _deep_merge(deepcopy(self._policy), deepcopy(updates))
            next_policy = self._normalize_policy(next_policy)
            if next_policy == self._policy:
                return deepcopy(self._policy)
            self._write(next_policy)
            self._policy = next_policy
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

            merged = self._normalize_policy(_deep_merge(deepcopy(DEFAULT_POLICY), raw))
            self._policy = merged
            self._last_mtime = current_mtime or time.time()

    def _write(self, policy: dict[str, Any]) -> None:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with self.config_path.open("w", encoding="utf-8") as handle:
            yaml.safe_dump(policy, handle, sort_keys=False)
        self._last_mtime = self.config_path.stat().st_mtime

    def _normalize_policy(self, policy: dict[str, Any]) -> dict[str, Any]:
        policy["watch_for"] = _normalize_string_list(policy.get("watch_for"))
        policy["ignore"] = _normalize_string_list(policy.get("ignore"))
        policy["mode"] = policy.get("mode", "balanced")
        policy["automation_rules"] = _normalize_rules(policy.get("automation_rules"))

        controls = dict(policy.get("controls", {}))
        controls["detection_enabled"] = bool(controls.get("detection_enabled", True))
        controls["auto_mode"] = bool(controls.get("auto_mode", True))
        controls["confidence_threshold"] = float(controls.get("confidence_threshold", 0.35))
        controls["iou_threshold"] = float(controls.get("iou_threshold", 0.5))
        policy["controls"] = controls

        expert = dict(policy.get("expert", {}))
        expert["backend"] = str(expert.get("backend", "mock"))
        expert["ollama_model"] = str(expert.get("ollama_model", "llava:7b"))
        expert["transformers_model"] = str(expert.get("transformers_model", "vikhyatk/moondream2"))
        expert["max_retries"] = int(expert.get("max_retries", 2))
        expert["timeout_seconds"] = int(expert.get("timeout_seconds", 20))
        expert["task_profile"] = str(expert.get("task_profile", "general"))
        expert["mission"] = str(
            expert.get(
                "mission",
                "Monitor the scene, reason about meaningful activity, and adapt system behavior when patterns emerge.",
            )
        )
        expert["operator_instructions"] = str(expert.get("operator_instructions", ""))
        expert["active_task"] = str(
            expert.get(
                "active_task",
                "Autonomously monitor the environment while staying controllable by the user.",
            )
        )
        policy["expert"] = expert

        model = dict(policy.get("model", {}))
        model["confidence_threshold"] = float(model.get("confidence_threshold", controls["confidence_threshold"]))
        policy["model"] = model

        video = dict(policy.get("video_analysis", {}))
        video["sample_interval_seconds"] = float(video.get("sample_interval_seconds", 1.0))
        video["max_frames"] = int(video.get("max_frames", 8))
        policy["video_analysis"] = video

        ui = dict(policy.get("ui", {}))
        ui["refresh_interval_seconds"] = float(ui.get("refresh_interval_seconds", 2.0))
        ui["default_feed_id"] = str(ui.get("default_feed_id", ""))
        policy["ui"] = ui

        task_routing = dict(policy.get("task_routing", {}))
        policy["task_routing"] = _normalize_task_routing(task_routing)

        rules = dict(policy.get("rules", {}))
        rules["min_confidence"] = float(rules.get("min_confidence", controls["confidence_threshold"]))
        policy["rules"] = rules

        policy["controls"]["confidence_threshold"] = policy["rules"]["min_confidence"]
        policy["model"]["confidence_threshold"] = policy["rules"]["min_confidence"]
        return policy


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


def _normalize_rules(values: Any) -> list[dict[str, Any]]:
    if not isinstance(values, list):
        return []
    normalized: list[dict[str, Any]] = []
    for value in values:
        if not isinstance(value, dict):
            continue
        name = str(value.get("name", "")).strip()
        condition = str(value.get("condition", "")).strip()
        action = str(value.get("action", "")).strip()
        if not (name and condition and action):
            continue
        normalized.append(
            {
                "name": name,
                "condition": condition,
                "action": action,
                "enabled": bool(value.get("enabled", True)),
            }
        )
    return normalized


def _normalize_task_routing(values: Any) -> dict[str, dict[str, Any]]:
    defaults = deepcopy(DEFAULT_POLICY["task_routing"])
    if not isinstance(values, dict):
        return defaults
    normalized = {}
    for intent, default in defaults.items():
        raw = values.get(intent, {})
        route = dict(default)
        if isinstance(raw, dict):
            route["mode"] = str(raw.get("mode", default["mode"]))
            route["expert_backend"] = str(raw.get("expert_backend", default["expert_backend"]))
            route["preferred_model"] = str(raw.get("preferred_model", default["preferred_model"]))
            route["feed_strategy"] = str(raw.get("feed_strategy", default["feed_strategy"]))
        normalized[intent] = route
    return normalized
