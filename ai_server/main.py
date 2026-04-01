from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile

from agent import AgentLoop
from expert import ExpertSystem
from memory import MemoryStore
from policy import PolicyEngine
from yolo import YoloDetector


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR.parent / "configs" / "prompts.yaml"


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
    yield


app = FastAPI(title="eye ai server", lifespan=lifespan)


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
    }


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

    try:
        detections = detector.detect_objects(contents, policy)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Detection failed: {exc}") from exc
    print("Detections:", detections)

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
        raise HTTPException(status_code=500, detail=f"Expert analysis failed: {exc}") from exc
    print("Expert:", expert_decision)

    record = memory_store.store_event(
        detections=detections,
        event=event,
        expert_decision=expert_decision,
        source=file.filename or "frame.jpg",
    )

    policy_update = agent_loop.process(record, expert_decision)
    if policy_update:
        print("Policy updated:", policy_update)

    return {
        "event": event,
        "detections": detections,
        "expert": expert_decision,
        "policy_update": policy_update,
        "runtime": detector.describe_runtime(policy_engine.get_policy()),
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
