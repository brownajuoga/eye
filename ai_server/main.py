from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
import tempfile

import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from PIL import Image

from agent import AgentLoop
from expert import ExpertSystem
from memory import MemoryStore
from policy import PolicyEngine
from yolo import YoloDetector


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR.parent / "configs" / "prompts.yaml"
LATEST_FRAME_PATH = BASE_DIR / "latest_frame.jpg"


@asynccontextmanager
async def lifespan(app: FastAPI):
    policy_engine = PolicyEngine(CONFIG_PATH)
    memory_store = MemoryStore(max_events=500)
    detector = YoloDetector()
    expert_system = ExpertSystem()
    agent_loop = AgentLoop(policy_engine, memory_store)

    app.state.policy_engine = policy_engine
    app.state.memory_store = memory_store
    app.state.detector = detector
    app.state.expert_system = expert_system
    app.state.agent_loop = agent_loop
    app.state.latest_result = None
    app.state.latest_frame_updated_at = None
    app.state.video_analyses = []
    yield


app = FastAPI(title="eye ai server", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "config_path": str(CONFIG_PATH),
    }


@app.get("/state")
async def state() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    detector: YoloDetector = app.state.detector
    memory_store: MemoryStore = app.state.memory_store

    policy = policy_engine.get_policy()
    runtime = detector.describe_runtime(policy)

    return {
        "policy": policy,
        "runtime": runtime,
        "memory_size": memory_store.size(),
        "latest_event": memory_store.latest(),
        "latest_result": app.state.latest_result,
    }


@app.get("/dashboard")
async def dashboard() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    detector: YoloDetector = app.state.detector
    memory_store: MemoryStore = app.state.memory_store

    policy = policy_engine.get_policy()
    return {
        "policy": policy,
        "runtime": detector.describe_runtime(policy),
        "capabilities": detector.describe_capabilities(policy),
        "models": detector.list_models(policy),
        "logs": memory_store.logs(limit=100),
        "latest_event": memory_store.latest(),
        "latest_result": app.state.latest_result,
        "latest_frame_url": f"/latest-frame?t={app.state.latest_frame_updated_at}" if LATEST_FRAME_PATH.exists() else None,
        "video_history": list(reversed(app.state.video_analyses[-20:])),
    }


@app.get("/logs")
async def logs(limit: int = 100) -> dict:
    memory_store: MemoryStore = app.state.memory_store
    return {"logs": memory_store.logs(limit=limit)}


@app.get("/models")
async def models() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    detector: YoloDetector = app.state.detector
    policy = policy_engine.get_policy()
    return {"models": detector.list_models(policy), "active_model": detector.describe_runtime(policy)["model_path"]}


@app.get("/capabilities")
async def capabilities() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    detector: YoloDetector = app.state.detector
    policy = policy_engine.get_policy()
    return {"capabilities": detector.describe_capabilities(policy)}


@app.get("/experts")
async def experts() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    policy = policy_engine.get_policy()
    return {
        "expert": policy["expert"],
        "available_backends": ["mock", "ollama", "transformers"],
        "task_profiles": ["general", "security", "tracking", "loitering", "theft"],
    }


@app.post("/experts")
async def update_experts(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    updated = policy_engine.patch_policy({"expert": payload})
    memory_store.log("system", "Expert settings updated", updated["expert"])
    return {"policy": updated}


@app.post("/watchlist")
async def update_watchlist(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    patch = {}
    if "watch_for" in payload:
        patch["watch_for"] = payload["watch_for"]
    if "ignore" in payload:
        patch["ignore"] = payload["ignore"]
    updated = policy_engine.patch_policy(patch)
    memory_store.log("system", "Watchlist updated", patch)
    return {"policy": updated}


@app.post("/models/activate")
async def activate_model(payload: dict) -> dict:
    model_path = str(payload.get("model_path", "")).strip()
    if not model_path:
        raise HTTPException(status_code=400, detail="model_path is required")

    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    updated = policy_engine.patch_policy({"model": {"custom": model_path}})
    memory_store.log("system", f"Activated model {Path(model_path).name}", {"model_path": model_path})
    return {"policy": updated}


@app.post("/models/upload")
async def upload_model(file: UploadFile = File(...)) -> dict:
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in {".pt", ".onnx"}:
        raise HTTPException(status_code=400, detail="Model must be a .pt or .onnx file")

    target = BASE_DIR / (file.filename or f"uploaded_model{suffix}")
    contents = await file.read()
    target.write_bytes(contents)

    memory_store: MemoryStore = app.state.memory_store
    memory_store.log("system", f"Uploaded model {target.name}", {"model_path": str(target)})
    return {"uploaded": str(target)}


@app.post("/controls")
async def update_controls(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store

    controls = {}
    if "detection_enabled" in payload:
        controls["detection_enabled"] = bool(payload["detection_enabled"])
    if "auto_mode" in payload:
        controls["auto_mode"] = bool(payload["auto_mode"])
    if "confidence_threshold" in payload:
        threshold = float(payload["confidence_threshold"])
        controls["confidence_threshold"] = threshold
        payload.setdefault("rules", {})
        payload.setdefault("model", {})
        payload["rules"]["min_confidence"] = threshold
        payload["model"]["confidence_threshold"] = threshold
    if "iou_threshold" in payload:
        controls["iou_threshold"] = float(payload["iou_threshold"])
    if controls:
        payload["controls"] = controls
    if "mode" in payload:
        payload["mode"] = str(payload["mode"])

    updated = policy_engine.patch_policy(payload)
    memory_store.log("system", "Controls updated", {"controls": controls, "mode": payload.get("mode")})
    return {"policy": updated}


@app.post("/rules")
async def update_rules(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    updated = policy_engine.patch_policy({"automation_rules": payload.get("automation_rules", [])})
    memory_store.log("system", "Automation rules updated", {"count": len(updated.get("automation_rules", []))})
    return {"policy": updated}


@app.get("/latest-frame")
async def latest_frame():
    if not LATEST_FRAME_PATH.exists():
        raise HTTPException(status_code=404, detail="No frame captured yet")
    return FileResponse(LATEST_FRAME_PATH, media_type="image/jpeg")


@app.get("/videos/history")
async def videos_history() -> dict:
    return {"items": list(reversed(app.state.video_analyses[-20:]))}


@app.post("/videos/analyze")
async def analyze_video(file: UploadFile = File(...)) -> dict:
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in {".mp4", ".avi", ".mov", ".mkv", ".webm", ".mpeg", ".mpg", ".m4v"}:
        raise HTTPException(status_code=400, detail="Expected a supported video file")

    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded video is empty")

    policy_engine: PolicyEngine = app.state.policy_engine
    detector: YoloDetector = app.state.detector
    expert_system: ExpertSystem = app.state.expert_system
    memory_store: MemoryStore = app.state.memory_store

    policy = policy_engine.get_policy()
    sample_interval = max(0.2, float(policy["video_analysis"].get("sample_interval_seconds", 1.0)))
    max_frames = max(1, int(policy["video_analysis"].get("max_frames", 8)))

    try:
        summary = _analyze_video_bytes(
            contents,
            suffix=suffix,
            detector=detector,
            expert_system=expert_system,
            memory_store=memory_store,
            policy=policy,
            sample_interval=sample_interval,
            max_frames=max_frames,
        )
    except Exception as exc:
        memory_store.log("error", f"Video analysis failed: {exc}")
        raise HTTPException(status_code=500, detail=f"Video analysis failed: {exc}") from exc

    summary["filename"] = file.filename or f"uploaded{suffix}"
    summary["created_at"] = datetime.now(timezone.utc).isoformat()
    app.state.video_analyses.append(summary)
    memory_store.log("system", "Video analyzed", {"filename": summary["filename"], "frames": summary["frames_processed"]})
    return summary


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)) -> dict:
    if file.content_type and not (
        file.content_type.startswith("image/") or file.content_type == "application/octet-stream"
    ):
        raise HTTPException(status_code=400, detail="Expected an image upload")

    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")

    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    detector: YoloDetector = app.state.detector
    expert_system: ExpertSystem = app.state.expert_system
    agent_loop: AgentLoop = app.state.agent_loop

    policy = policy_engine.get_policy()
    memory_store.max_events = int(policy["memory"].get("max_events", memory_store.max_events))
    LATEST_FRAME_PATH.write_bytes(contents)
    app.state.latest_frame_updated_at = datetime.now(timezone.utc).isoformat()
    frame_size = extract_frame_size(contents)

    if not policy.get("controls", {}).get("detection_enabled", True):
        result = {
            "event": {
                "important": False,
                "reason": "Detection disabled",
                "objects": [],
                "filtered_objects": [],
                "watch_matches": [],
                "ignored_objects": [],
            },
            "detections": [],
            "expert": {
                "action": "ignore",
                "reason": "Detection disabled",
                "update_watch_for": [],
                "confidence": 0.0,
            },
            "policy_update": None,
            "frame": frame_size,
            "runtime": detector.describe_runtime(policy_engine.get_policy()),
        }
        app.state.latest_result = result
        memory_store.log("system", "Detection skipped because controls disabled")
        return result

    try:
        detections = detector.detect_objects(contents, policy)
    except Exception as exc:
        memory_store.log("error", f"Detection failed: {exc}")
        raise HTTPException(status_code=500, detail=f"Detection failed: {exc}") from exc
    print("Detections:", detections)
    memory_store.log("info", "Detections processed", {"count": len(detections), "detections": detections})

    event = policy_engine.analyze_event(detections)
    print("Event:", event)

    recent_memory = memory_store.recent(limit=policy["memory"]["recent_limit"])

    try:
        expert_decision = expert_system.analyze(
            image_bytes=contents,
            detections=detections,
            memory=recent_memory,
            policy=policy,
            event=event,
        )
    except Exception as exc:
        memory_store.log("error", f"Expert analysis failed: {exc}")
        raise HTTPException(status_code=500, detail=f"Expert analysis failed: {exc}") from exc
    print("Expert:", expert_decision)
    memory_store.log("decision", "Expert decision produced", expert_decision)

    record = memory_store.store_event(
        detections=detections,
        event=event,
        expert_decision=expert_decision,
        source=file.filename or "frame.jpg",
    )

    policy_update = agent_loop.process(record, expert_decision)
    if policy_update:
        print("Policy updated:", policy_update)
        memory_store.log("system", "Policy updated", policy_update)

    result = {
        "event": event,
        "detections": detections,
        "expert": expert_decision,
        "policy_update": policy_update,
        "frame": frame_size,
        "runtime": detector.describe_runtime(policy_engine.get_policy()),
    }
    app.state.latest_result = result
    return result


def extract_frame_size(image_bytes: bytes) -> dict:
    image = Image.open(BytesIO(image_bytes))
    return {
        "width": image.width,
        "height": image.height,
    }


def _analyze_video_bytes(
    video_bytes: bytes,
    *,
    suffix: str,
    detector: YoloDetector,
    expert_system: ExpertSystem,
    memory_store: MemoryStore,
    policy: dict,
    sample_interval: float,
    max_frames: int,
) -> dict:
    cv2 = __import__("cv2")
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as handle:
        handle.write(video_bytes)
        temp_path = Path(handle.name)

    capture = cv2.VideoCapture(str(temp_path))
    if not capture.isOpened():
        temp_path.unlink(missing_ok=True)
        raise RuntimeError("Unable to open uploaded video")

    fps = capture.get(cv2.CAP_PROP_FPS) or 0
    frame_step = max(1, int((fps if fps > 0 else 25) * sample_interval))

    frame_index = 0
    processed = 0
    detections_summary = []
    expert_actions = []
    latest_frame = None

    while processed < max_frames:
        ok, frame = capture.read()
        if not ok:
            break
        if frame_index % frame_step != 0:
            frame_index += 1
            continue

        ok, encoded = cv2.imencode(".jpg", frame)
        if not ok:
            frame_index += 1
            continue

        frame_bytes = encoded.tobytes()
        latest_frame = {"width": int(frame.shape[1]), "height": int(frame.shape[0])}
        detections = detector.detect_objects(frame_bytes, policy)
        event = PolicyEngine(CONFIG_PATH).analyze_event(detections)
        expert = expert_system.analyze(
            image_bytes=frame_bytes,
            detections=detections,
            memory=memory_store.recent(limit=policy["memory"]["recent_limit"]),
            policy=policy,
            event=event,
        )
        detections_summary.append(
            {
                "frame_index": frame_index,
                "detections": detections,
                "event": event,
                "expert": expert,
            }
        )
        expert_actions.append(expert.get("action", "ignore"))
        processed += 1
        frame_index += 1

    capture.release()
    temp_path.unlink(missing_ok=True)

    aggregated_labels = sorted(
        {
            item["label"]
            for frame in detections_summary
            for item in frame["detections"]
        }
    )
    return {
        "frames_processed": processed,
        "sample_interval_seconds": sample_interval,
        "aggregated_labels": aggregated_labels,
        "alert_frames": [frame for frame in detections_summary if frame["expert"].get("action") == "alert"],
        "timeline": detections_summary,
        "dominant_action": "alert" if "alert" in expert_actions else "ignore",
        "latest_frame": latest_frame,
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
