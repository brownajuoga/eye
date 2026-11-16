from __future__ import annotations

import base64
import json
from json import JSONDecodeError
import re
from typing import Any
from urllib import error as urlerror
from urllib import request as urlrequest

from PIL import Image


JSON_BLOCK_RE = re.compile(r"\{.*\}", re.DOTALL)
VALID_ACTIONS = {"alert", "ignore"}
WIFI_HIGH_PRIORITY = {
    "deauth_flood",
    "evil_twin",
    "canary_hit",
    "beacon_spam",
    "rssi_tripwire_motion",
    "channel_congestion",
}


class ExpertSystem:
    def __init__(self):
        self._transformer_backend: TransformersExpert | None = None

    def analyze(
        self,
        *,
        image_bytes: bytes,
        detections: list[dict[str, Any]],
        memory: list[dict[str, Any]],
        policy: dict[str, Any],
        event: dict[str, Any],
    ) -> dict[str, Any]:
        backend_name = str(policy["expert"].get("backend", "mock")).lower()
        max_retries = int(policy["expert"].get("max_retries", 2))
        timeout = int(policy["expert"].get("timeout_seconds", 20))

        for attempt in range(max_retries + 1):
            try:
                raw_response = self._run_backend(
                    backend_name=backend_name,
                    image_bytes=image_bytes,
                    detections=detections,
                    memory=memory,
                    policy=policy,
                    event=event,
                    timeout=timeout,
                )
                return normalize_expert_output(
                    raw_response,
                    fallback_reason="validated backend output",
                    policy=policy,
                    event=event,
                    detections=detections,
                )
            except Exception as exc:
                if attempt >= max_retries:
                    return build_fallback_decision(
                        detections=detections,
                        event=event,
                        reason=f"{backend_name} backend failed: {exc}",
                    )

        return build_fallback_decision(detections=detections, event=event, reason="expert backend exhausted retries")

    def chat(
        self,
        *,
        message: str,
        policy: dict[str, Any],
        memory: list[dict[str, Any]],
        latest_result: dict[str, Any] | None,
        feed_id: str | None,
        feeds: list[dict[str, Any]] | None = None,
        models: list[dict[str, Any]] | None = None,
        vision: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        backend_name = str(policy["expert"].get("backend", "mock")).lower()
        plan = build_operator_plan(
            message=message,
            policy=policy,
            memory=memory,
            latest_result=latest_result,
            feed_id=feed_id,
            feeds=feeds or [],
            models=models or [],
            vision=vision,
        )
        if backend_name == "mock":
            reply = MockExpert().chat(
                message=message,
                policy=policy,
                memory=memory,
                latest_result=latest_result,
                feed_id=feed_id,
                plan=plan,
                vision=vision,
            )
            reply["plan"] = plan
            reply["evidence"] = plan.get("evidence", [])
            reply["actions"] = plan.get("actions", [])
            return reply

        prompt = build_chat_prompt(
            message=message,
            policy=policy,
            memory=memory,
            latest_result=latest_result,
            feed_id=feed_id,
            plan=plan,
        )
        max_retries = int(policy["expert"].get("max_retries", 2))
        timeout = int(policy["expert"].get("timeout_seconds", 20))
        for attempt in range(max_retries + 1):
            try:
                if backend_name == "ollama":
                    raw = OllamaExpert(
                        model=str(policy["expert"].get("ollama_model", "llava:7b")),
                        timeout_seconds=timeout,
                    ).chat(prompt)
                elif backend_name == "transformers":
                    if self._transformer_backend is None:
                        self._transformer_backend = TransformersExpert(
                            model_id=str(policy["expert"].get("transformers_model", "vikhyatk/moondream2"))
                        )
                    raw = self._transformer_backend.chat(prompt)
                else:
                    raise ValueError(f"Unsupported expert backend: {backend_name}")
                payload = parse_jsonish(raw)
                return {
                    "message": str(payload.get("message", "")).strip() or "No expert reply was produced.",
                    "task_summary": str(payload.get("task_summary", "")).strip(),
                    "plan": payload.get("plan", plan),
                    "evidence": payload.get("evidence", plan.get("evidence", [])),
                    "actions": payload.get("actions", plan.get("actions", [])),
                }
            except Exception as exc:
                if attempt >= max_retries:
                    return {
                        "message": f"Expert backend failed while answering chat: {exc}",
                        "task_summary": "",
                        "plan": plan,
                        "evidence": plan.get("evidence", []),
                        "actions": plan.get("actions", []),
                    }
        return {
            "message": "Expert chat retries exhausted.",
            "task_summary": "",
            "plan": plan,
            "evidence": plan.get("evidence", []),
            "actions": plan.get("actions", []),
        }

    def _run_backend(
        self,
        *,
        backend_name: str,
        image_bytes: bytes,
        detections: list[dict[str, Any]],
        memory: list[dict[str, Any]],
        policy: dict[str, Any],
        event: dict[str, Any],
        timeout: int,
    ) -> dict[str, Any] | str:
        if backend_name == "mock":
            return MockExpert().analyze(detections=detections, memory=memory, event=event, policy=policy)
        if backend_name == "ollama":
            backend = OllamaExpert(
                model=str(policy["expert"].get("ollama_model", "llava:7b")),
                timeout_seconds=timeout,
            )
            return backend.analyze(
                image_bytes=image_bytes,
                detections=detections,
                memory=memory,
                event=event,
                policy=policy,
            )
        if backend_name == "transformers":
            if self._transformer_backend is None:
                self._transformer_backend = TransformersExpert(
                    model_id=str(policy["expert"].get("transformers_model", "vikhyatk/moondream2"))
                )
            return self._transformer_backend.analyze(
                image_bytes=image_bytes,
                detections=detections,
                memory=memory,
                event=event,
                policy=policy,
            )
        raise ValueError(f"Unsupported expert backend: {backend_name}")


class MockExpert:
    def analyze(
        self,
        *,
        detections: list[dict[str, Any]],
        memory: list[dict[str, Any]],
        event: dict[str, Any],
        policy: dict[str, Any],
    ) -> dict[str, Any]:
        labels = [str(item.get("label", "")) for item in detections]
        label_set = set(labels)
        repeated_bottle = sum("bottle" in [d.get("label") for d in item.get("detections", [])] for item in memory)
        expert_cfg = policy.get("expert", {})
        task_profile = str(expert_cfg.get("task_profile", "general")).lower()
        active_task = str(expert_cfg.get("active_task", "")).lower()
        operator_instructions = str(expert_cfg.get("operator_instructions", "")).lower()

        wifi_hits = [lbl for lbl in labels if lbl in WIFI_HIGH_PRIORITY]
        if wifi_hits:
            action = "alert"
            top_reasons = [str(d.get("reason", "")) for d in detections if d.get("label") in WIFI_HIGH_PRIORITY and d.get("reason")]
            reason = top_reasons[0] if top_reasons else f"Wi-Fi intelligence alert: {', '.join(sorted(set(wifi_hits)))}"
            confidence = max(float(d.get("confidence", 0.75)) for d in detections if d.get("label") in WIFI_HIGH_PRIORITY)
        elif event.get("important") and ("person" in label_set and any(lbl in label_set for lbl in ("backpack", "handbag", "cell phone", "bottle"))):
            action = "alert"
            reason = "Important watched objects interacting with a person"
            confidence = 0.84
        elif ("count" in active_task or "inventory" in operator_instructions) and labels:
            action = "alert"
            reason = f"Task requested accounting; observed: {', '.join(sorted(set(l for l in labels if l)))}"
            confidence = 0.77
        elif task_profile in {"tracking", "security", "theft"} and "person" in label_set and any(lbl in label_set for lbl in ("bag", "backpack", "handbag", "cell phone")):
            action = "alert"
            reason = "Task profile prioritizes person-object interactions"
            confidence = 0.81
        elif repeated_bottle >= 3:
            action = "alert"
            reason = "Repeated bottle interactions detected across recent events"
            confidence = 0.74
        else:
            action = "ignore"
            reason = event.get("reason", "RF spectrum nominal")
            confidence = 0.42

        updates = []
        if repeated_bottle >= 3:
            updates.extend(["hand", "bag", "bottle"])

        return {
            "action": action,
            "reason": reason,
            "update_watch_for": dedupe_strings(updates),
            "confidence": round(confidence, 3),
            "task_summary": build_task_summary(policy, event, detections),
            "control": recommended_control_patch(policy, event, detections),
        }

    def chat(
        self,
        *,
        message: str,
        policy: dict[str, Any],
        memory: list[dict[str, Any]],
        latest_result: dict[str, Any] | None,
        feed_id: str | None,
        plan: dict[str, Any],
        vision: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        answer_parts = [str(plan.get("summary", "")).strip()]
        if plan.get("recommendation"):
            answer_parts.append(str(plan["recommendation"]))
        if vision:
            occ = vision.get("occupancy", {})
            metrics = vision.get("metrics", {})
            answer_parts.append(
                f"Live RF: {occ.get('active_aps', 0)} APs, {occ.get('active_clients', 0)} clients, "
                f"disturbance={metrics.get('disturbance', 0):.2f}, cleanest Ch={metrics.get('recommended_channel', 1)}"
            )
        return {
            "message": ". ".join(part for part in answer_parts if part) or f"Operator request received: {message}",
            "task_summary": str(plan.get("task_summary", "")),
        }


class OllamaExpert:
    def __init__(self, model: str, timeout_seconds: int):
        self.model = model
        self.timeout_seconds = timeout_seconds

    def analyze(
        self,
        *,
        image_bytes: bytes,
        detections: list[dict[str, Any]],
        memory: list[dict[str, Any]],
        event: dict[str, Any],
        policy: dict[str, Any],
    ) -> str:
        prompt = build_prompt(detections=detections, memory=memory, event=event, policy=policy)
        payload = json.dumps(
            {
                "model": self.model,
                "stream": False,
                "format": "json",
                "prompt": prompt,
                "images": [base64.b64encode(image_bytes).decode("ascii")],
            }
        ).encode("utf-8")
        req = urlrequest.Request(
            url="http://127.0.0.1:11434/api/generate",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlrequest.urlopen(req, timeout=self.timeout_seconds) as response:
                body = json.loads(response.read().decode("utf-8"))
        except urlerror.URLError as exc:
            raise RuntimeError(f"Ollama request failed: {exc}") from exc

        return str(body.get("response", ""))

    def chat(self, prompt: str) -> str:
        payload = json.dumps(
            {
                "model": self.model,
                "stream": False,
                "format": "json",
                "prompt": prompt,
            }
        ).encode("utf-8")
        req = urlrequest.Request(
            url="http://127.0.0.1:11434/api/generate",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlrequest.urlopen(req, timeout=self.timeout_seconds) as response:
                body = json.loads(response.read().decode("utf-8"))
        except urlerror.URLError as exc:
            raise RuntimeError(f"Ollama request failed: {exc}") from exc
        return str(body.get("response", ""))


class TransformersExpert:
    def __init__(self, model_id: str):
        try:
            from transformers import AutoModelForCausalLM, AutoTokenizer
        except Exception as exc:  # pragma: no cover
            raise RuntimeError("transformers backend is not available") from exc

        self.model_id = model_id
        self.tokenizer = AutoTokenizer.from_pretrained(model_id)
        self.model = AutoModelForCausalLM.from_pretrained(model_id, trust_remote_code=True)

    def analyze(
        self,
        *,
        image_bytes: bytes,
        detections: list[dict[str, Any]],
        memory: list[dict[str, Any]],
        event: dict[str, Any],
        policy: dict[str, Any],
    ) -> str:
        if not hasattr(self.model, "chat"):
            raise RuntimeError(f"Model {self.model_id} does not support chat(image=...)")

        from io import BytesIO

        image = Image.open(BytesIO(image_bytes)).convert("RGB")
        prompt = build_prompt(detections=detections, memory=memory, event=event, policy=policy)
        response = self.model.chat(
            image=image,
            msgs=[{"role": "user", "content": prompt}],
            tokenizer=self.tokenizer,
        )
        return str(response)

    def chat(self, prompt: str) -> str:
        response = self.model.chat(
            msgs=[{"role": "user", "content": prompt}],
            tokenizer=self.tokenizer,
        )
        return str(response)


def build_prompt(
    *,
    detections: list[dict[str, Any]],
    memory: list[dict[str, Any]],
    event: dict[str, Any],
    policy: dict[str, Any],
) -> str:
    expert_cfg = policy.get("expert", {})
    return (
        "You are the central expert reasoning layer for a Wi-Fi surveillance and RF intelligence platform.\n"
        "Return STRICT JSON only.\n"
        "Required keys: action, reason, update_watch_for, confidence.\n"
        "Optional keys when useful: task_summary, control.\n"
        "Valid action values: alert or ignore.\n"
        f"Mission: {expert_cfg.get('mission', '')}\n"
        f"Active task: {expert_cfg.get('active_task', '')}\n"
        f"Wi-Fi settings: {policy.get('wifi', {})}\n"
        f"Policy watch_for: {policy.get('watch_for', [])}\n"
        f"Current event: {event}\n"
        f"Detections: {detections}\n"
        f"Recent memory: {memory}\n"
    )


def build_chat_prompt(
    *,
    message: str,
    policy: dict[str, Any],
    memory: list[dict[str, Any]],
    latest_result: dict[str, Any] | None,
    feed_id: str | None,
    plan: dict[str, Any],
) -> str:
    expert_cfg = policy.get("expert", {})
    return (
        "You are the expert operator interface for the Wi-Fi RF intelligence system.\n"
        "Answer the operator directly and return STRICT JSON with keys: message, task_summary.\n"
        f"Mission: {expert_cfg.get('mission', '')}\n"
        f"Selected feed: {feed_id}\n"
        f"Latest result: {latest_result}\n"
        f"Recent memory: {memory}\n"
        f"Operator execution plan: {plan}\n"
        f"Operator message: {message}\n"
    )


def normalize_expert_output(
    raw: dict[str, Any] | str,
    fallback_reason: str,
    *,
    policy: dict[str, Any] | None = None,
    event: dict[str, Any] | None = None,
    detections: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    if isinstance(raw, dict):
        payload = raw
    else:
        payload = parse_jsonish(raw)

    action = str(payload.get("action", "ignore")).lower()
    if action not in VALID_ACTIONS:
        action = "ignore"

    confidence = payload.get("confidence", 0.0)
    try:
        confidence = max(0.0, min(1.0, float(confidence)))
    except (TypeError, ValueError):
        confidence = 0.0

    return {
        "action": action,
        "reason": str(payload.get("reason") or fallback_reason),
        "update_watch_for": dedupe_strings(payload.get("update_watch_for", [])),
        "confidence": round(confidence, 3),
        "task_summary": str(payload.get("task_summary") or build_task_summary(policy or {}, event or {}, detections or [])),
        "control": normalize_control_patch(payload.get("control")),
    }


def parse_jsonish(raw: str) -> dict[str, Any]:
    raw = raw.strip()
    try:
        return json.loads(raw)
    except JSONDecodeError:
        match = JSON_BLOCK_RE.search(raw)
        if not match:
            raise ValueError("No JSON object found in expert response")
        return json.loads(match.group(0))


def build_fallback_decision(
    *,
    detections: list[dict[str, Any]],
    event: dict[str, Any],
    reason: str,
) -> dict[str, Any]:
    labels = {item.get("label") for item in detections}
    high_pri = "person" in labels or bool(labels.intersection(WIFI_HIGH_PRIORITY))
    action = "alert" if event.get("important") and high_pri else "ignore"
    confidence = 0.55 if action == "alert" else 0.2
    return {
        "action": action,
        "reason": reason,
        "update_watch_for": [],
        "confidence": confidence,
        "task_summary": "",
        "control": {},
    }


def dedupe_strings(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    output: list[str] = []
    for value in values:
        item = str(value).strip()
        if item and item not in output:
            output.append(item)
    return output


def build_task_summary(policy: dict[str, Any], event: dict[str, Any], detections: list[dict[str, Any]]) -> str:
    expert_cfg = policy.get("expert", {})
    task = str(expert_cfg.get("active_task", "")).strip()
    mission = str(expert_cfg.get("mission", "")).strip()
    labels = sorted({str(item.get("label", "")) for item in detections if item.get("label")})
    observed = ", ".join(labels) if labels else "nominal RF field"
    parts = [part for part in [task or mission, f"Observed {observed}", str(event.get("reason", "")).strip()] if part]
    return " | ".join(parts)


def recommended_control_patch(
    policy: dict[str, Any],
    event: dict[str, Any],
    detections: list[dict[str, Any]],
) -> dict[str, Any]:
    labels = {str(item.get("label", "")) for item in detections}
    if event.get("important") and ("person" in labels or bool(labels.intersection(WIFI_HIGH_PRIORITY))):
        return {"mode": "performance"}
    if not detections and policy.get("controls", {}).get("auto_mode", True):
        return {"mode": "lightweight"}
    return {}


def normalize_control_patch(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    allowed = {"mode", "confidence_threshold", "iou_threshold", "detection_enabled", "auto_mode"}
    return {key: value for key, value in raw.items() if key in allowed}


def build_operator_plan(
    *,
    message: str,
    policy: dict[str, Any],
    memory: list[dict[str, Any]],
    latest_result: dict[str, Any] | None,
    feed_id: str | None,
    feeds: list[dict[str, Any]],
    models: list[dict[str, Any]],
    vision: dict[str, Any] | None = None,
) -> dict[str, Any]:
    text = message.lower()
    labels = extract_candidate_labels(message, policy, latest_result, feeds)
    default_feed_id = str(policy.get("ui", {}).get("default_feed_id", "")).strip()
    effective_feed_id = feed_id or default_feed_id or None
    selected_feed = next((feed for feed in feeds if feed.get("id") == effective_feed_id), None)
    active_model = next((model for model in models if model.get("active")), None)
    routing_policy = policy.get("task_routing", {})
    plan = {
        "intent": "general_question",
        "summary": "Review live RF telemetry, security alerts, and occupancy estimates.",
        "task_summary": "",
        "recommendation": "",
        "resources": {
            "feed": effective_feed_id or (selected_feed or {}).get("id") or "latest",
            "expert_backend": policy.get("expert", {}).get("backend", "mock"),
            "model": (active_model or {}).get("name") or policy.get("model", {}).get("custom") or policy.get("model", {}).get("default"),
            "mode": policy.get("mode", "balanced"),
            "feed_strategy": "latest",
        },
        "actions": [],
        "evidence": [],
    }

    latest_result = latest_result or {}
    if any(phrase in text for phrase in ["channel", "congestion", "interference", "spectrum"]):
        metrics = (vision or {}).get("metrics", {})
        best_ch = metrics.get("recommended_channel", 6)
        peak = metrics.get("peak_congestion", 0.0)
        plan["summary"] = f"2.4 GHz spectrum peak congestion is {int(float(peak) * 100)}%"
        plan["recommendation"] = f"Channel {best_ch} is currently cleanest among 1/6/11"
        plan["task_summary"] = "Spectrum congestion inspection"
    elif any(phrase in text for phrase in ["deauth", "attack", "evil twin", "rogue", "security", "intrusion"]):
        alerts = (vision or {}).get("alerts", [])
        deauth = (vision or {}).get("metrics", {}).get("deauth_12s", 0)
        plan["summary"] = f"WIDS observed {deauth} deauth/disassoc frames in the last 12s and {len(alerts)} recent alerts"
        plan["recommendation"] = alerts[-1].get("reason", "No active WIDS attack") if alerts else "Spectrum looks clean of deauth/evil-twin signatures"
        plan["task_summary"] = "WIDS security status"
    elif any(phrase in text for phrase in ["people", "person", "occupancy", "room", "motion", "someone"]):
        occ = (vision or {}).get("occupancy", {})
        dist = (vision or {}).get("metrics", {}).get("disturbance", 0.0)
        plan["summary"] = f"Estimated occupancy: {occ.get('estimate', 0)} ({occ.get('density', 'empty')}), RF disturbance={float(dist):.2f}"
        plan["recommendation"] = "Enable Privacy Mode to hide client MAC identifiers while keeping occupancy and tripwire sensing active"
        plan["task_summary"] = "RF occupancy & motion check"
    elif any(phrase in text for phrase in ["when", "what time", "time did", "occurred", "happened"]):
        plan["intent"] = "event_time_query"
        if labels:
            target = labels[0]
            matching = [
                item for item in memory
                if any(str(det.get("label", "")).lower() == target for det in item.get("detections", []))
            ]
            first = matching[0] if matching else None
            last = matching[-1] if matching else None
            plan["summary"] = f"Search memory for when '{target}' appeared"
            plan["task_summary"] = f"Event timing query for {target}"
            if first:
                plan["evidence"].append({"type": "first_seen", "label": target, "timestamp": first.get("timestamp"), "source": first.get("source")})
            if last and last is not first:
                plan["evidence"].append({"type": "last_seen", "label": target, "timestamp": last.get("timestamp"), "source": last.get("source")})
            plan["recommendation"] = (
                f"{target} was seen {len(matching)} times in recent memory." if matching else f"No recent memory event matched {target}."
            )
        else:
            plan["recommendation"] = "No target RF signature identified from the timing question."
    elif any(phrase in text for phrase in ["find", "search", "look for", "track", "locate"]):
        plan["intent"] = "object_search"
        target = labels[0] if labels else ""
        plan["summary"] = f"Search feeds and RF memory for '{target or 'target signal'}'"
        plan["task_summary"] = f"Signal search for {target or 'requested target'}"
        for feed in feeds:
            feed_labels = {str(det.get("label", "")).lower() for det in feed.get("detections", [])}
            if not target or target in feed_labels:
                plan["actions"].append({"type": "inspect_feed", "feed": feed.get("id"), "reason": "target present"})
                plan["evidence"].append({"type": "feed_match", "feed": feed.get("id"), "labels": sorted(feed_labels)})
        plan["recommendation"] = (
            f"Prioritize {len(plan['actions'])} feed(s)" if plan["actions"] else "No live feed currently matches; relying on memory"
        )
    else:
        detections = latest_result.get("detections", [])
        plan["task_summary"] = build_task_summary(policy, latest_result.get("event", {}), detections)
        if detections:
            plan["evidence"].append({"type": "latest_detections", "labels": [item.get("label") for item in detections]})
            plan["recommendation"] = "Answer grounded in the latest RF scene and recent memory"
        else:
            plan["recommendation"] = "System is ready; start Host Wi-Fi, Simulator, or NodeMCU sensor stream"

    route = routing_policy.get(plan["intent"], {})
    if isinstance(route, dict):
        plan["resources"]["mode"] = str(route.get("mode", plan["resources"]["mode"]))
        plan["resources"]["expert_backend"] = str(route.get("expert_backend", plan["resources"]["expert_backend"]))
        plan["resources"]["model"] = str(route.get("preferred_model", plan["resources"]["model"]))
        plan["resources"]["feed_strategy"] = str(route.get("feed_strategy", plan["resources"]["feed_strategy"]))
    return plan


def extract_candidate_labels(
    message: str,
    policy: dict[str, Any],
    latest_result: dict[str, Any] | None,
    feeds: list[dict[str, Any]],
) -> list[str]:
    vocab = {str(item).lower() for item in policy.get("watch_for", [])}
    vocab.update(str(item).lower() for item in policy.get("ignore", []))
    latest_result = latest_result or {}
    vocab.update(str(item.get("label", "")).lower() for item in latest_result.get("detections", []))
    for feed in feeds:
        vocab.update(str(item.get("label", "")).lower() for item in feed.get("detections", []))
    return [token for token in vocab if token and token in message.lower()]
