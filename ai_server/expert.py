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
        )
        if backend_name == "mock":
            reply = MockExpert().chat(
                message=message,
                policy=policy,
                memory=memory,
                latest_result=latest_result,
                feed_id=feed_id,
                plan=plan,
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
        labels = [item.get("label") for item in detections]
        repeated_bottle = sum("bottle" in [d.get("label") for d in item.get("detections", [])] for item in memory)
        expert_cfg = policy.get("expert", {})
        task_profile = str(expert_cfg.get("task_profile", "general")).lower()
        active_task = str(expert_cfg.get("active_task", "")).lower()
        operator_instructions = str(expert_cfg.get("operator_instructions", "")).lower()

        if event.get("important") and ("person" in labels and any(label in labels for label in ("backpack", "handbag", "cell phone", "bottle"))):
            action = "alert"
            reason = "Important watched objects interacting with a person"
            confidence = 0.84
        elif ("count" in active_task or "inventory" in operator_instructions) and labels:
            action = "alert"
            reason = f"Task requested object accounting; observed: {', '.join(sorted(set(str(label) for label in labels if label)))}"
            confidence = 0.77
        elif task_profile in {"tracking", "security", "theft"} and "person" in labels and any(label in labels for label in ("bag", "backpack", "handbag", "cell phone")):
            action = "alert"
            reason = "Task profile prioritizes person-object interactions"
            confidence = 0.81
        elif repeated_bottle >= 3:
            action = "alert"
            reason = "Repeated bottle interactions detected across recent events"
            confidence = 0.74
        else:
            action = "ignore"
            reason = event.get("reason", "No suspicious pattern detected")
            confidence = 0.42

        updates = []
        if repeated_bottle >= 3:
            updates.extend(["hand", "bag", "bottle"])

        return {
            "action": action,
            "reason": reason,
            "update_watch_for": dedupe_strings(updates),
            "confidence": confidence,
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
    ) -> dict[str, Any]:
        answer_parts = [str(plan.get("summary", "")).strip()]
        if plan.get("recommendation"):
            answer_parts.append(str(plan["recommendation"]))
        if plan.get("resources"):
            resource_desc = ", ".join(f"{key}={value}" for key, value in plan["resources"].items() if value not in (None, "", []))
            if resource_desc:
                answer_parts.append(f"Resource plan: {resource_desc}")
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
        except Exception as exc:  # pragma: no cover - optional dependency path
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
        "You are the central expert reasoning layer for an autonomous surveillance system.\n"
        "You own reasoning quality, prioritization, and suggested control adaptations.\n"
        "Return STRICT JSON only.\n"
        "Required keys: action, reason, update_watch_for, confidence.\n"
        "Optional keys when useful: task_summary, control.\n"
        "Valid action values: alert or ignore.\n"
        f"Mission: {expert_cfg.get('mission', '')}\n"
        f"Active task: {expert_cfg.get('active_task', '')}\n"
        f"Operator instructions: {expert_cfg.get('operator_instructions', '')}\n"
        f"Task profile: {expert_cfg.get('task_profile', 'general')}\n"
        f"Policy watch_for: {policy.get('watch_for', [])}\n"
        f"Policy ignore: {policy.get('ignore', [])}\n"
        f"Automation rules: {policy.get('automation_rules', [])}\n"
        f"Current event: {event}\n"
        f"Detections: {detections}\n"
        f"Recent memory: {memory}\n"
        "If you suggest policy changes, keep update_watch_for short and concrete.\n"
        "If task intent changes what matters in the scene, explain that in reason and task_summary.\n"
        "If control changes are useful, return them in control as a small JSON object.\n"
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
        "You are the expert operator interface for the surveillance system.\n"
        "Answer the operator directly and return STRICT JSON with keys: message, task_summary.\n"
        f"Mission: {expert_cfg.get('mission', '')}\n"
        f"Active task: {expert_cfg.get('active_task', '')}\n"
        f"Operator instructions: {expert_cfg.get('operator_instructions', '')}\n"
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
    action = "alert" if event.get("important") and "person" in labels else "ignore"
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
    observed = ", ".join(labels) if labels else "no tracked objects"
    parts = [part for part in [task or mission, f"Observed {observed}", str(event.get("reason", "")).strip()] if part]
    return " | ".join(parts)


def recommended_control_patch(
    policy: dict[str, Any],
    event: dict[str, Any],
    detections: list[dict[str, Any]],
) -> dict[str, Any]:
    labels = {str(item.get("label", "")) for item in detections}
    if event.get("important") and "person" in labels:
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
) -> dict[str, Any]:
    text = message.lower()
    labels = extract_candidate_labels(message, policy, latest_result, feeds)
    selected_feed = next((feed for feed in feeds if feed.get("id") == feed_id), None)
    active_model = next((model for model in models if model.get("active")), None)
    plan = {
        "intent": "general_question",
        "summary": "Review the current scene state and answer using available feed and memory context.",
        "task_summary": "",
        "recommendation": "",
        "resources": {
            "feed": feed_id or (selected_feed or {}).get("id") or "latest",
            "expert_backend": policy.get("expert", {}).get("backend", "mock"),
            "model": (active_model or {}).get("name") or policy.get("model", {}).get("custom") or policy.get("model", {}).get("default"),
            "mode": policy.get("mode", "balanced"),
        },
        "actions": [],
        "evidence": [],
    }

    latest_result = latest_result or {}
    if any(phrase in text for phrase in ["when", "what time", "time did", "occurred", "happened"]):
        plan["intent"] = "event_time_query"
        if labels:
            target = labels[0]
            matching = [
                item for item in memory
                if any(str(det.get("label", "")).lower() == target for det in item.get("detections", []))
            ]
            first = matching[0] if matching else None
            last = matching[-1] if matching else None
            plan["summary"] = f"Search memory for when '{target}' appeared and report the earliest and latest matching events."
            plan["task_summary"] = f"Event timing query for {target}"
            if first:
                plan["evidence"].append({"type": "first_seen", "label": target, "timestamp": first.get("timestamp"), "source": first.get("source")})
            if last and last is not first:
                plan["evidence"].append({"type": "last_seen", "label": target, "timestamp": last.get("timestamp"), "source": last.get("source")})
            if matching:
                plan["recommendation"] = f"{target} was seen {len(matching)} times in recent memory."
            else:
                plan["recommendation"] = f"No recent memory event matched {target}."
        else:
            plan["recommendation"] = "No target object was identified from the timing question."
    elif any(phrase in text for phrase in ["find", "search", "look for", "track", "locate"]):
        plan["intent"] = "object_search"
        target = labels[0] if labels else ""
        plan["summary"] = (
            f"Search current feeds and recent memory for '{target}' and prioritize feeds where it is visible."
            if target else
            "Search current feeds and recent memory for the requested object."
        )
        plan["task_summary"] = f"Object search for {target or 'requested target'}"
        for feed in feeds:
            feed_labels = {str(det.get('label', '')).lower() for det in feed.get("detections", [])}
            if not target or target in feed_labels:
                plan["actions"].append({"type": "inspect_feed", "feed": feed.get("id"), "reason": "target present in latest detections"})
                plan["evidence"].append({"type": "feed_match", "feed": feed.get("id"), "labels": sorted(feed_labels)})
        if not plan["actions"]:
            plan["recommendation"] = f"No live feed currently shows {target or 'the requested target'}; relying on recent memory."
        else:
            plan["recommendation"] = f"Prioritize {len(plan['actions'])} feed(s) for the requested search."
    elif any(phrase in text for phrase in ["switch model", "change model", "use model", "weight"]):
        plan["intent"] = "resource_switch"
        plan["summary"] = "Review available models and recommend the most suitable weight for the requested task."
        plan["task_summary"] = "Model and resource planning"
        for model in models:
            plan["evidence"].append({"type": "model", "name": model.get("name"), "active": model.get("active", False)})
        plan["recommendation"] = "Use a lightweight model for broad live scans and switch to the highest-capability available weight when precision is explicitly requested."
    else:
        detections = latest_result.get("detections", [])
        plan["task_summary"] = build_task_summary(policy, latest_result.get("event", {}), detections)
        if detections:
            plan["evidence"].append({"type": "latest_detections", "labels": [item.get("label") for item in detections]})
            plan["recommendation"] = "Answer grounded in the latest scene and recent memory."
        else:
            plan["recommendation"] = "No immediate detections are available; answer from recent memory and current policy."
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
