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
                return normalize_expert_output(raw_response, fallback_reason="validated backend output")
            except Exception as exc:
                if attempt >= max_retries:
                    return build_fallback_decision(
                        detections=detections,
                        event=event,
                        reason=f"{backend_name} backend failed: {exc}",
                    )

        return build_fallback_decision(detections=detections, event=event, reason="expert backend exhausted retries")

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
            return MockExpert().analyze(detections=detections, memory=memory, event=event)
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
    ) -> dict[str, Any]:
        labels = [item.get("label") for item in detections]
        repeated_bottle = sum("bottle" in [d.get("label") for d in item.get("detections", [])] for item in memory)

        if event.get("important") and ("person" in labels and any(label in labels for label in ("backpack", "handbag", "cell phone", "bottle"))):
            action = "alert"
            reason = "Important watched objects interacting with a person"
            confidence = 0.84
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


def build_prompt(
    *,
    detections: list[dict[str, Any]],
    memory: list[dict[str, Any]],
    event: dict[str, Any],
    policy: dict[str, Any],
) -> str:
    return (
        "You are the expert reasoning layer for an autonomous surveillance system.\n"
        "Return STRICT JSON only with keys: action, reason, update_watch_for, confidence.\n"
        "Valid action values: alert or ignore.\n"
        f"Policy watch_for: {policy.get('watch_for', [])}\n"
        f"Policy ignore: {policy.get('ignore', [])}\n"
        f"Current event: {event}\n"
        f"Detections: {detections}\n"
        f"Recent memory: {memory}\n"
        "If you suggest policy changes, keep update_watch_for short and concrete.\n"
    )


def normalize_expert_output(raw: dict[str, Any] | str, fallback_reason: str) -> dict[str, Any]:
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
    return output
