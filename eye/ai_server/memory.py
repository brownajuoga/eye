from __future__ import annotations

from collections import Counter
from copy import deepcopy
from datetime import datetime, timezone
import threading
from typing import Any


class MemoryStore:
    def __init__(self, max_events: int = 500):
        self.max_events = max_events
        self._events: list[dict[str, Any]] = []
        self._logs: list[dict[str, Any]] = []
        self._lock = threading.RLock()

    def store_event(
        self,
        *,
        detections: list[dict[str, Any]],
        event: dict[str, Any],
        expert_decision: dict[str, Any] | None,
        source: str,
    ) -> dict[str, Any]:
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "source": source,
            "detections": deepcopy(detections),
            "event": deepcopy(event),
            "expert": deepcopy(expert_decision),
        }
        with self._lock:
            self._events.append(record)
            if len(self._events) > self.max_events:
                self._events = self._events[-self.max_events:]
        self.log("event", f"Event stored from {source}", record)
        return deepcopy(record)

    def recent(self, limit: int = 10) -> list[dict[str, Any]]:
        with self._lock:
            return deepcopy(self._events[-limit:])

    def filter(
        self,
        *,
        labels: list[str] | None = None,
        actions: list[str] | None = None,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        labels = set(labels or [])
        actions = set(actions or [])

        with self._lock:
            filtered: list[dict[str, Any]] = []
            for event in reversed(self._events):
                detection_labels = {item.get("label") for item in event.get("detections", [])}
                expert_action = (event.get("expert") or {}).get("action")

                if labels and not labels.intersection(detection_labels):
                    continue
                if actions and expert_action not in actions:
                    continue

                filtered.append(deepcopy(event))
                if len(filtered) >= limit:
                    break
        filtered.reverse()
        return filtered

    def recent_label_counts(self, limit: int = 25) -> dict[str, int]:
        counts: Counter[str] = Counter()
        for event in self.recent(limit=limit):
            counts.update(item.get("label") for item in event.get("detections", []))
        return dict(counts)

    def find_events(
        self,
        *,
        labels: list[str] | None = None,
        source: str | None = None,
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        wanted_labels = {label.strip().lower() for label in (labels or []) if label.strip()}
        with self._lock:
            matches: list[dict[str, Any]] = []
            for event in reversed(self._events):
                if source and str(event.get("source")) != source:
                    continue
                event_labels = {
                    str(item.get("label", "")).strip().lower()
                    for item in event.get("detections", [])
                    if item.get("label")
                }
                if wanted_labels and not wanted_labels.intersection(event_labels):
                    continue
                matches.append(deepcopy(event))
                if len(matches) >= limit:
                    break
        matches.reverse()
        return matches

    def first_seen(self, label: str, *, source: str | None = None) -> dict[str, Any] | None:
        events = self.find_events(labels=[label], source=source, limit=self.max_events)
        return events[0] if events else None

    def last_seen(self, label: str, *, source: str | None = None) -> dict[str, Any] | None:
        events = self.find_events(labels=[label], source=source, limit=1)
        return events[-1] if events else None

    def size(self) -> int:
        with self._lock:
            return len(self._events)

    def latest(self) -> dict[str, Any] | None:
        with self._lock:
            if not self._events:
                return None
            return deepcopy(self._events[-1])

    def log(self, level: str, message: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": level,
            "message": message,
            "data": deepcopy(data) if data else None,
        }
        with self._lock:
            self._logs.append(entry)
            if len(self._logs) > self.max_events:
                self._logs = self._logs[-self.max_events:]
        return deepcopy(entry)

    def logs(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock:
            return deepcopy(self._logs[-limit:])
