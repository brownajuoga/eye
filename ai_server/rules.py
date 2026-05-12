from __future__ import annotations

from datetime import datetime, timezone
import re
from typing import Any


CONFIDENCE_RE = re.compile(r"confidence\s*(>=|>|<=|<|=)\s*([0-9]*\.?[0-9]+)", re.IGNORECASE)
DURATION_RE = re.compile(r"for\s+(\d+(?:\.\d+)?)\s*(seconds?|secs?|minutes?|mins?)", re.IGNORECASE)
DETECTED_RE = re.compile(r"([a-z0-9 _-]+?)\s+detected", re.IGNORECASE)


class RuleEngine:
    """Small deterministic planner for realtime event handling."""

    def evaluate(
        self,
        *,
        detections: list[dict[str, Any]],
        event: dict[str, Any],
        policy: dict[str, Any],
        memory: list[dict[str, Any]],
    ) -> dict[str, Any]:
        automation_rules = policy.get("automation_rules", [])
        matched_rules = [
            rule
            for rule in automation_rules
            if is_rule_enabled(rule) and condition_matches(rule.get("condition", ""), detections, event, memory)
        ]

        if matched_rules:
            action = select_action(matched_rules, event)
            reason = build_rule_reason(matched_rules)
            control = merge_control_patches(matched_rules)
        elif event.get("important"):
            action = "alert"
            reason = str(event.get("reason") or "Watched object detected")
            control = {}
        else:
            action = "ignore"
            reason = str(event.get("reason") or "No rule matched")
            control = {}

        confidence = decision_confidence(action, detections, event, matched_rules)
        return {
            "action": action,
            "reason": reason,
            "update_watch_for": [],
            "confidence": confidence,
            "task_summary": build_task_summary(event, detections, matched_rules),
            "control": control,
            "matched_rules": [
                {
                    "name": str(rule.get("name", "")),
                    "condition": str(rule.get("condition", "")),
                    "action": str(rule.get("action", "")),
                }
                for rule in matched_rules
            ],
            "source": "rule_engine",
        }


def condition_matches(
    condition: Any,
    detections: list[dict[str, Any]],
    event: dict[str, Any],
    memory: list[dict[str, Any]],
) -> bool:
    text = str(condition or "").strip().lower()
    if not text:
        return False
    if text.startswith("if "):
        text = text[3:].strip()

    if "no object" in text or "no detections" in text or "nothing detected" in text:
        return no_objects_condition_matches(text, detections, memory)

    if "watch" in text and "detected" in text and event.get("watch_matches"):
        return confidence_condition_matches(text, detections)

    labels = extract_detected_labels(text)
    if len(labels) > 1:
        return all(
            any(labels_match(label, str(detection.get("label", ""))) for detection in detections)
            for label in labels
        ) and confidence_condition_matches(text, detections)

    label = extract_detected_label(text)
    if label:
        if label == "object":
            return bool(detections) and confidence_condition_matches(text, detections)
        return any(
            labels_match(label, str(detection.get("label", "")))
            and confidence_condition_matches(text, [detection])
            for detection in detections
        )

    if "detected" in text:
        return bool(detections) and confidence_condition_matches(text, detections)

    return False


def is_rule_enabled(rule: Any) -> bool:
    return isinstance(rule, dict) and bool(rule.get("enabled", True))


def no_objects_condition_matches(
    condition: str,
    detections: list[dict[str, Any]],
    memory: list[dict[str, Any]],
) -> bool:
    if detections:
        return False

    duration = extract_duration_seconds(condition)
    if duration is None:
        return True

    elapsed = seconds_since_last_detection(memory)
    return elapsed is not None and elapsed >= duration


def extract_detected_label(condition: str) -> str:
    labels = extract_detected_labels(condition)
    if not labels:
        return ""
    return labels[0]


def extract_detected_labels(condition: str) -> list[str]:
    match = DETECTED_RE.search(condition)
    if not match:
        return []
    raw = re.sub(r"\bwith\s+confidence\b.*$", "", match.group(1), flags=re.IGNORECASE)
    raw = raw.replace(",", " and ")
    labels = []
    for label in re.split(r"\s+(?:and|or)\s+", raw):
        label = label.strip()
        for prefix in ("a ", "an ", "the ", "any "):
            if label.startswith(prefix):
                label = label[len(prefix):]
        normalized = normalize_label(label)
        if normalized and normalized not in labels:
            labels.append(normalized)
    return labels


def normalize_label(value: str) -> str:
    return " ".join(value.replace("_", " ").replace("-", " ").split()).lower()


def labels_match(expected: str, observed: str) -> bool:
    expected = normalize_label(expected)
    observed = normalize_label(observed)
    if not expected or not observed:
        return False
    return expected == observed or expected in observed or observed in expected


def confidence_condition_matches(condition: str, detections: list[dict[str, Any]]) -> bool:
    match = CONFIDENCE_RE.search(condition)
    if not match:
        return True

    operator = match.group(1)
    threshold = float(match.group(2))
    confidences = [float(detection.get("confidence", 0.0)) for detection in detections]
    if not confidences:
        return False

    if operator == ">":
        return any(confidence > threshold for confidence in confidences)
    if operator == ">=":
        return any(confidence >= threshold for confidence in confidences)
    if operator == "<":
        return any(confidence < threshold for confidence in confidences)
    if operator == "<=":
        return any(confidence <= threshold for confidence in confidences)
    return any(confidence == threshold for confidence in confidences)


def extract_duration_seconds(condition: str) -> float | None:
    match = DURATION_RE.search(condition)
    if not match:
        return None
    value = float(match.group(1))
    unit = match.group(2).lower()
    if unit.startswith("min"):
        return value * 60
    return value


def seconds_since_last_detection(memory: list[dict[str, Any]]) -> float | None:
    for record in reversed(memory):
        if not record.get("detections"):
            continue
        timestamp = parse_timestamp(record.get("timestamp"))
        if timestamp is None:
            return None
        return max(0.0, (datetime.now(timezone.utc) - timestamp).total_seconds())
    return None


def parse_timestamp(raw: Any) -> datetime | None:
    if not raw:
        return None
    try:
        value = str(raw)
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def select_action(matched_rules: list[dict[str, Any]], event: dict[str, Any]) -> str:
    action_text = " ".join(str(rule.get("action", "")).lower() for rule in matched_rules)
    if any(token in action_text for token in ("alert", "notify", "alarm", "flag")):
        return "alert"
    if any(token in action_text for token in ("ignore", "suppress", "dismiss")):
        return "ignore"
    return "alert" if event.get("important") else "ignore"


def merge_control_patches(matched_rules: list[dict[str, Any]]) -> dict[str, Any]:
    action_text = " ".join(str(rule.get("action", "")).lower() for rule in matched_rules)
    if "performance" in action_text:
        return {"mode": "performance"}
    if "balanced" in action_text:
        return {"mode": "balanced"}
    if "lightweight" in action_text or "reduce" in action_text or "idle" in action_text:
        return {"mode": "lightweight"}
    return {}


def build_rule_reason(matched_rules: list[dict[str, Any]]) -> str:
    names = [str(rule.get("name", "")).strip() for rule in matched_rules if str(rule.get("name", "")).strip()]
    if not names:
        return "Matched automation rule"
    return "Matched automation rule: " + ", ".join(names)


def decision_confidence(
    action: str,
    detections: list[dict[str, Any]],
    event: dict[str, Any],
    matched_rules: list[dict[str, Any]],
) -> float:
    if detections:
        base = max(float(detection.get("confidence", 0.0)) for detection in detections)
    elif matched_rules:
        base = 0.65
    elif event.get("important"):
        base = 0.6
    else:
        base = 0.2

    if action == "alert" and matched_rules:
        base = min(1.0, base + 0.05)
    return round(max(0.0, min(1.0, base)), 3)


def build_task_summary(
    event: dict[str, Any],
    detections: list[dict[str, Any]],
    matched_rules: list[dict[str, Any]],
) -> str:
    labels = sorted({str(item.get("label", "")) for item in detections if item.get("label")})
    observed = ", ".join(labels) if labels else "no objects"
    if matched_rules:
        rule_names = ", ".join(str(rule.get("name", "")).strip() for rule in matched_rules if rule.get("name"))
        return f"Observed {observed} | Rules: {rule_names or 'matched'}"
    return f"Observed {observed} | {event.get('reason', 'No important event')}"
