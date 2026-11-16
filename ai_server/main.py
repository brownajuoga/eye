from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
import tempfile
from typing import Any
import uuid

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from PIL import Image

from agent import AgentLoop
from expert import ExpertSystem
from memory import MemoryStore
from policy import PolicyEngine
from rules import RuleEngine
from vision_renderer import render_vision_jpeg
from wifi_capture import parse_capture_bytes, slice_capture_into_frames
from wifi_engine import WifiEngine
from yolo import YoloDetector


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR.parent / "configs" / "prompts.yaml"
LATEST_FRAME_PATH = BASE_DIR / "latest_frame.jpg"
FEEDS_DIR = BASE_DIR / "feeds"

CAPTURE_EXTENSIONS = {".pcap", ".pcapng", ".csv", ".jsonl", ".ndjson", ".json"}
VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm", ".mpeg", ".mpg", ".m4v"}


@asynccontextmanager
async def lifespan(app: FastAPI):
    policy_engine = PolicyEngine(CONFIG_PATH)
    memory_store = MemoryStore(max_events=500)
    detector = YoloDetector()
    expert_system = ExpertSystem()
    rule_engine = RuleEngine()
    agent_loop = AgentLoop(policy_engine, memory_store)
    wifi_engine = WifiEngine()

    app.state.policy_engine = policy_engine
    app.state.memory_store = memory_store
    app.state.detector = detector
    app.state.expert_system = expert_system
    app.state.rule_engine = rule_engine
    app.state.agent_loop = agent_loop
    app.state.wifi_engine = wifi_engine
    app.state.latest_result = None
    app.state.latest_frame_updated_at = None
    app.state.video_analyses = []
    app.state.captures = {}
    app.state.feeds = {}
    app.state.chat_history = []
    app.state.nodemcu_commands = []
    app.state.nodemcu_config = {
        "mode": policy_engine.get_policy().get("wifi", {}).get("nodemcu_mode", "promisc"),
        "channel_hop": policy_engine.get_policy().get("wifi", {}).get("channel_hop", True),
        "locked_channel": policy_engine.get_policy().get("wifi", {}).get("locked_channel", 6),
        "privacy_mode": policy_engine.get_policy().get("wifi", {}).get("privacy_mode", False),
        "canary_ssid": policy_engine.get_policy().get("wifi", {}).get("canary_ssid", "EYE_CANARY_AP"),
        "wifi_ssid": "",
        "server_url": "http://192.168.1.100:8080/wifi/ingest",
    }
    app.state.sim_running = False
    app.state.sim_scenario = "mixed"
    app.state.sim_tick = 0
    app.state.sim_task = None
    app.state.host_scan_running = False
    app.state.host_scan_iface = detect_host_wifi_interface()
    app.state.host_scan_task = None
    app.state.replay_running = False
    app.state.replay_task = None

    initial_policy = policy_engine.get_policy()
    initial_vision = wifi_engine.get_vision_state(initial_policy)
    palette = initial_policy.get("wifi", {}).get("vision_palette", "night_vision")
    LATEST_FRAME_PATH.write_bytes(render_vision_jpeg(initial_vision, palette_name=palette))
    app.state.latest_frame_updated_at = datetime.now(timezone.utc).isoformat()

    try:
        yield
    finally:
        for attr in ("sim_task", "host_scan_task", "replay_task"):
            task = getattr(app.state, attr, None)
            if task is not None and not task.done():
                task.cancel()
                with suppress(asyncio.CancelledError):
                    await task


app = FastAPI(title="eye wifi intelligence server", lifespan=lifespan)
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
    wifi_engine: WifiEngine = app.state.wifi_engine

    policy = policy_engine.get_policy()
    vision = wifi_engine.get_vision_state(policy)
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
        "feeds": list_feed_snapshots(app.state.feeds),
        "chat_history": app.state.chat_history[-50:],
        "wifi_vision": vision,
        "wifi_sources_status": describe_sources_status(app.state),
        "nodemcu": app.state.nodemcu_config,
    }


@app.get("/wifi/vision")
async def wifi_vision() -> dict:
    policy = app.state.policy_engine.get_policy()
    vision = app.state.wifi_engine.get_vision_state(policy)
    return {
        "vision": vision,
        "wifi": policy.get("wifi", {}),
        "controls": policy.get("controls", {}),
        "runtime": app.state.detector.describe_runtime(policy),
        "sources_status": describe_sources_status(app.state),
    }


@app.get("/wifi/stream.mjpeg")
async def wifi_stream_mjpeg():
    async def frame_generator():
        while True:
            policy = app.state.policy_engine.get_policy()
            vision = app.state.wifi_engine.get_vision_state(policy)
            palette = str(policy.get("wifi", {}).get("vision_palette", "night_vision"))
            jpeg = render_vision_jpeg(vision, palette_name=palette)
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n"
                + f"Content-Length: {len(jpeg)}\r\n\r\n".encode("ascii")
                + jpeg
                + b"\r\n"
            )
            await asyncio.sleep(0.28)

    return StreamingResponse(
        frame_generator(),
        media_type="multipart/x-mixed-replace; boundary=frame",
    )


@app.post("/wifi/ingest")
async def wifi_ingest(payload: dict) -> dict:
    observations = payload.get("observations")
    if observations is None and isinstance(payload.get("observation"), dict):
        observations = [payload["observation"]]
    if not isinstance(observations, list) or not observations:
        raise HTTPException(status_code=400, detail="observations list is required")

    source_id = str(payload.get("source_id") or "wifi_node").strip()
    source_name = str(payload.get("source_name") or source_id).strip()
    source_kind = str(payload.get("source_kind") or "nodemcu").strip()
    live_source = bool(payload.get("live_source", True))

    return _process_rf_batch(
        app.state,
        observations=observations,
        source_id=source_id,
        source_name=source_name,
        source_kind=source_kind,
        live_source=live_source,
    )


@app.post("/wifi/anchors")
async def wifi_anchors(payload: dict) -> dict:
    anchors = payload.get("anchors")
    if not isinstance(anchors, dict):
        raise HTTPException(status_code=400, detail="anchors dict is required")
    updated = app.state.wifi_engine.update_anchors(anchors)
    app.state.memory_store.log("system", "Updated RF spatial room anchors", updated)
    return {"anchors": updated}


@app.post("/wifi/simulator")
async def wifi_simulator(payload: dict) -> dict:
    action = str(payload.get("action", "start")).lower()
    scenario = str(payload.get("scenario", app.state.sim_scenario or "mixed")).lower()
    app.state.sim_scenario = scenario

    if action == "stop":
        await _stop_task(app.state, "sim_task")
        app.state.sim_running = False
        app.state.memory_store.log("system", "RF simulator stopped")
        return {"running": False, "scenario": scenario, "sources_status": describe_sources_status(app.state)}

    if action == "step":
        app.state.sim_tick += 1
        obs = app.state.wifi_engine.generate_sim_observations(scenario=scenario, tick=app.state.sim_tick)
        res = _process_rf_batch(
            app.state,
            observations=obs,
            source_id="sim_rf",
            source_name=f"RF Simulator ({scenario})",
            source_kind="simulator",
            live_source=True,
        )
        return {"running": app.state.sim_running, "scenario": scenario, "result": res}

    # Start or update scenario loop
    await _stop_task(app.state, "sim_task")
    app.state.sim_running = True
    app.state.sim_task = asyncio.create_task(_simulator_loop(app.state))
    app.state.memory_store.log("system", f"RF simulator started ({scenario})")
    return {"running": True, "scenario": scenario, "sources_status": describe_sources_status(app.state)}


@app.post("/wifi/host-scan")
async def wifi_host_scan(payload: dict) -> dict:
    action = str(payload.get("action", "start")).lower()
    iface = str(payload.get("interface") or app.state.host_scan_iface or "").strip() or detect_host_wifi_interface()
    app.state.host_scan_iface = iface

    if action == "stop":
        await _stop_task(app.state, "host_scan_task")
        app.state.host_scan_running = False
        app.state.memory_store.log("system", "Host Wi-Fi scanner stopped")
        return {"running": False, "interface": iface, "sources_status": describe_sources_status(app.state)}

    if action == "once":
        obs = await poll_host_wifi_once(iface)
        if not obs:
            raise HTTPException(status_code=503, detail=f"No Wi-Fi scan results returned for interface {iface}")
        res = _process_rf_batch(
            app.state,
            observations=obs,
            source_id=f"host_{iface}",
            source_name=f"Host Wi-Fi ({iface})",
            source_kind="host_wifi",
            live_source=True,
        )
        return {"running": app.state.host_scan_running, "interface": iface, "result": res}

    await _stop_task(app.state, "host_scan_task")
    app.state.host_scan_running = True
    app.state.host_scan_task = asyncio.create_task(_host_scan_loop(app.state, iface))
    app.state.memory_store.log("system", f"Host Wi-Fi scanner started on {iface}")
    return {"running": True, "interface": iface, "sources_status": describe_sources_status(app.state)}


@app.get("/wifi/nodemcu/config")
async def get_nodemcu_config() -> dict:
    return {"config": app.state.nodemcu_config}


@app.post("/wifi/nodemcu/config")
async def update_nodemcu_config(payload: dict) -> dict:
    cfg = app.state.nodemcu_config
    commands: list[str] = []
    if "mode" in payload:
        mode = str(payload["mode"]).lower()
        cfg["mode"] = mode
        mode_map = {"promisc": "MODE:PROMISC", "link": "MODE:LINK", "hybrid": "MODE:HYBRID", "canary": "MODE:CANARY"}
        if mode in mode_map:
            commands.append(mode_map[mode])
    if "channel_hop" in payload:
        hop = bool(payload["channel_hop"])
        cfg["channel_hop"] = hop
        commands.append("HOP:1" if hop else "HOP:0")
    if "locked_channel" in payload:
        ch = max(1, min(13, int(payload["locked_channel"])))
        cfg["locked_channel"] = ch
        if not cfg.get("channel_hop", True):
            commands.append(f"CHANNEL:{ch}")
    if "privacy_mode" in payload:
        priv = bool(payload["privacy_mode"])
        cfg["privacy_mode"] = priv
        commands.append("PRIVACY:1" if priv else "PRIVACY:0")
    if "canary_ssid" in payload:
        cfg["canary_ssid"] = str(payload["canary_ssid"])
    if "wifi_ssid" in payload:
        cfg["wifi_ssid"] = str(payload["wifi_ssid"])
        if cfg["wifi_ssid"]:
            commands.append(f"SSID:{cfg['wifi_ssid']}")
    if "wifi_pass" in payload and str(payload["wifi_pass"]):
        commands.append(f"PASS:{payload['wifi_pass']}")
    if "server_url" in payload:
        cfg["server_url"] = str(payload["server_url"])
        if cfg["server_url"]:
            commands.append(f"URL:{cfg['server_url']}")

    app.state.nodemcu_commands.extend(commands)
    app.state.policy_engine.patch_policy(
        {
            "wifi": {
                "nodemcu_mode": cfg["mode"],
                "channel_hop": cfg["channel_hop"],
                "locked_channel": cfg["locked_channel"],
                "privacy_mode": cfg["privacy_mode"],
                "canary_ssid": cfg["canary_ssid"],
            }
        }
    )
    app.state.memory_store.log("system", "Updated NodeMCU ESP8266 config", {"commands": commands})
    return {"config": cfg, "queued_commands": commands}


@app.get("/wifi/nodemcu/command")
async def get_nodemcu_commands(consume: bool = False) -> dict:
    cmds = list(app.state.nodemcu_commands)
    if consume:
        app.state.nodemcu_commands.clear()
    return {"commands": cmds}


@app.post("/wifi/nodemcu/command")
async def push_nodemcu_command(payload: dict) -> dict:
    cmd = str(payload.get("command", "")).strip()
    if not cmd:
        raise HTTPException(status_code=400, detail="command is required")
    app.state.nodemcu_commands.append(cmd)
    app.state.memory_store.log("system", f"Queued NodeMCU serial command: {cmd}")
    return {"queued": cmd, "pending": list(app.state.nodemcu_commands)}


@app.post("/wifi/upload")
@app.post("/videos/analyze")
async def analyze_capture_or_video(file: UploadFile = File(...)) -> dict:
    suffix = Path(file.filename or "").suffix.lower()
    contents = await file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded capture file is empty")

    if suffix in CAPTURE_EXTENSIONS or not suffix:
        return await _analyze_rf_capture_upload(app.state, contents, filename=file.filename or "capture.pcap")
    if suffix in VIDEO_EXTENSIONS:
        return _analyze_legacy_video_upload(app.state, contents, filename=file.filename or f"uploaded{suffix}", suffix=suffix)
    raise HTTPException(
        status_code=400,
        detail="Expected .pcap, .pcapng, .csv, .jsonl/.json RF capture or video file",
    )


@app.post("/wifi/replay")
async def wifi_replay(payload: dict) -> dict:
    action = str(payload.get("action", "load_frame")).lower()
    capture_id = str(payload.get("capture_id", "")).strip()

    if action == "stop":
        await _stop_task(app.state, "replay_task")
        app.state.replay_running = False
        app.state.wifi_engine.set_replay_meta(None)
        return {"running": False}

    capture = app.state.captures.get(capture_id)
    if not capture:
        raise HTTPException(status_code=404, detail="Unknown capture_id for replay")

    slices = capture["slices"]
    if not slices:
        raise HTTPException(status_code=400, detail="Capture contains no replayable frames")

    if action == "play":
        await _stop_task(app.state, "replay_task")
        speed = max(0.25, min(5.0, float(payload.get("speed", 1.0))))
        start_idx = max(0, min(len(slices) - 1, int(payload.get("frame_index", 0))))
        app.state.replay_running = True
        app.state.replay_task = asyncio.create_task(_replay_loop(app.state, capture, start_idx=start_idx, speed=speed))
        return {"running": True, "capture_id": capture_id, "total_frames": len(slices)}

    frame_idx = max(0, min(len(slices) - 1, int(payload.get("frame_index", 0))))
    if frame_idx == 0:
        app.state.wifi_engine.reset_state()
    res = _process_rf_batch(
        app.state,
        observations=slices[frame_idx],
        source_id=f"replay_{capture_id}",
        source_name=f"Replay: {capture['filename']}",
        source_kind="capture_replay",
        live_source=False,
        replay_meta={
            "capture_id": capture_id,
            "filename": capture["filename"],
            "frame_index": frame_idx,
            "total_frames": len(slices),
        },
    )
    return {"running": False, "frame_index": frame_idx, "total_frames": len(slices), "result": res}


@app.get("/logs")
async def logs(limit: int = 100) -> dict:
    memory_store: MemoryStore = app.state.memory_store
    return {"logs": memory_store.logs(limit=limit)}


@app.get("/feeds")
async def feeds() -> dict:
    return {"feeds": list_feed_snapshots(app.state.feeds)}


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


@app.get("/chat/history")
async def chat_history(limit: int = 50) -> dict:
    return {"messages": app.state.chat_history[-limit:]}


@app.post("/chat/message")
async def chat_message(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    expert_system: ExpertSystem = app.state.expert_system
    memory_store: MemoryStore = app.state.memory_store
    detector: YoloDetector = app.state.detector
    wifi_engine: WifiEngine = app.state.wifi_engine

    message = str(payload.get("message", "")).strip()
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    feed_id = str(payload.get("feed_id", "")).strip() or None
    policy = policy_engine.get_policy()
    latest_result = resolve_chat_result(app.state, feed_id)
    recent_memory = memory_store.recent(limit=policy["memory"]["recent_limit"])
    vision = wifi_engine.get_vision_state(policy)

    reply = expert_system.chat(
        message=message,
        policy=policy,
        memory=recent_memory,
        latest_result=latest_result,
        feed_id=feed_id,
        feeds=list_feed_snapshots(app.state.feeds),
        models=detector.list_models(policy),
        vision=vision,
    )

    user_entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "role": "user",
        "content": message,
        "feed_id": feed_id,
    }
    assistant_entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "role": "assistant",
        "content": reply["message"],
        "feed_id": feed_id,
        "task_summary": reply.get("task_summary", ""),
        "plan": reply.get("plan", {}),
        "evidence": reply.get("evidence", []),
        "actions": reply.get("actions", []),
    }
    app.state.chat_history.extend([user_entry, assistant_entry])
    memory_store.log("system", "Operator chatted with expert", {"feed_id": feed_id, "message": message})
    return {"reply": reply, "messages": app.state.chat_history[-50:]}


@app.get("/experts")
async def experts() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    policy = policy_engine.get_policy()
    return {
        "expert": policy["expert"],
        "available_backends": ["mock", "ollama", "transformers"],
        "task_profiles": ["wifi_security", "tripwire", "privacy_occupancy", "spectrum_audit", "general"],
    }


@app.get("/settings")
async def settings() -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    detector: YoloDetector = app.state.detector
    policy = policy_engine.get_policy()
    return {
        "policy": policy,
        "runtime": detector.describe_runtime(policy),
        "capabilities": detector.describe_capabilities(policy),
        "models": detector.list_models(policy),
    }


@app.post("/settings")
async def update_settings(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    updated = policy_engine.patch_policy(payload)
    memory_store.log("system", "Settings updated", payload)
    return {"policy": updated}


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
    patch: dict[str, Any] = {}
    if "watch_for" in payload:
        patch["watch_for"] = payload["watch_for"]
    if "ignore" in payload:
        patch["ignore"] = payload["ignore"]
    if "known_aps" in payload:
        patch.setdefault("wifi", {})["known_aps"] = payload["known_aps"]
    updated = policy_engine.patch_policy(patch)
    memory_store.log("system", "Watchlist / Trusted APs updated", patch)
    return {"policy": updated}


@app.post("/models/activate")
async def activate_model(payload: dict) -> dict:
    model_path = str(payload.get("model_path", "")).strip()
    if not model_path:
        raise HTTPException(status_code=400, detail="model_path is required")

    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store
    patch: dict[str, Any] = {"model": {"custom": model_path}}

    name = Path(model_path).name.lower()
    if name == "rf_wids_security.profile":
        patch["wifi"] = {"mode": "wids", "privacy_mode": False}
    elif name == "rf_tripwire_motion.profile":
        patch["wifi"] = {"mode": "tripwire"}
    elif name == "rf_privacy_occupancy.profile":
        patch["wifi"] = {"mode": "occupancy", "privacy_mode": True}
    elif name == "rf_spectrum_survey.profile":
        patch["wifi"] = {"mode": "spectrum"}
    elif name == "rf_multi_guard.profile":
        patch["wifi"] = {"mode": "multi"}

    updated = policy_engine.patch_policy(patch)
    memory_store.log("system", f"Activated profile {Path(model_path).name}", {"model_path": model_path})
    return {"policy": updated}


@app.post("/models/upload")
async def upload_model(file: UploadFile = File(...)) -> dict:
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in {".pt", ".onnx", ".profile", ".yaml", ".json"}:
        raise HTTPException(status_code=400, detail="Model/Profile must be .profile, .yaml, .json, .pt, or .onnx")

    target = BASE_DIR / (file.filename or f"uploaded_model{suffix}")
    contents = await file.read()
    target.write_bytes(contents)

    memory_store: MemoryStore = app.state.memory_store
    memory_store.log("system", f"Uploaded profile {target.name}", {"model_path": str(target)})
    return {"uploaded": str(target)}


@app.post("/controls")
async def update_controls(payload: dict) -> dict:
    policy_engine: PolicyEngine = app.state.policy_engine
    memory_store: MemoryStore = app.state.memory_store

    controls: dict[str, Any] = {}
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

    # Sync NodeMCU serial commands if privacy/channel changed in wifi controls
    wifi_patch = payload.get("wifi")
    if isinstance(wifi_patch, dict):
        if "privacy_mode" in wifi_patch:
            app.state.nodemcu_config["privacy_mode"] = bool(wifi_patch["privacy_mode"])
            app.state.nodemcu_commands.append("PRIVACY:1" if wifi_patch["privacy_mode"] else "PRIVACY:0")
        if "channel_hop" in wifi_patch:
            app.state.nodemcu_config["channel_hop"] = bool(wifi_patch["channel_hop"])
            app.state.nodemcu_commands.append("HOP:1" if wifi_patch["channel_hop"] else "HOP:0")
        if "locked_channel" in wifi_patch and not wifi_patch.get("channel_hop", app.state.nodemcu_config.get("channel_hop", True)):
            ch = max(1, min(13, int(wifi_patch["locked_channel"])))
            app.state.nodemcu_config["locked_channel"] = ch
            app.state.nodemcu_commands.append(f"CHANNEL:{ch}")

    updated = policy_engine.patch_policy(payload)
    vision = app.state.wifi_engine.get_vision_state(updated)
    palette = str(updated.get("wifi", {}).get("vision_palette", "night_vision"))
    LATEST_FRAME_PATH.write_bytes(render_vision_jpeg(vision, palette_name=palette))
    app.state.latest_frame_updated_at = datetime.now(timezone.utc).isoformat()
    memory_store.log("system", "Controls updated", {"controls": controls, "mode": payload.get("mode"), "wifi": wifi_patch})
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


@app.get("/feed-frame/{feed_id}")
async def feed_frame(feed_id: str):
    feed = app.state.feeds.get(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Unknown feed")
    frame_path = Path(feed["frame_path"])
    if not frame_path.exists():
        raise HTTPException(status_code=404, detail="No frame captured yet for feed")
    return FileResponse(frame_path, media_type="image/jpeg")


@app.get("/videos/history")
async def videos_history() -> dict:
    return {"items": list(reversed(app.state.video_analyses[-20:]))}


@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...),
    source_id: str = Form("default"),
    source_name: str = Form("default"),
    live_source: bool = Form(True),
) -> dict:
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
    rule_engine: RuleEngine = app.state.rule_engine
    agent_loop: AgentLoop = app.state.agent_loop

    policy = policy_engine.get_policy()
    memory_store.max_events = int(policy["memory"].get("max_events", memory_store.max_events))
    LATEST_FRAME_PATH.write_bytes(contents)
    app.state.latest_frame_updated_at = datetime.now(timezone.utc).isoformat()
    frame_size = extract_frame_size(contents)
    feed_frame_path = write_feed_frame(source_id, contents)

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
            "feed": {"id": source_id, "name": source_name, "live": live_source},
        }
        app.state.latest_result = result
        update_feed_state(
            app.state.feeds,
            source_id=source_id,
            source_name=source_name,
            live_source=live_source,
            frame_path=str(feed_frame_path),
            frame_size=frame_size,
            result=result,
        )
        memory_store.log("system", "Detection skipped because controls disabled")
        return result

    detections = detector.detect_objects(contents, policy)
    event = policy_engine.analyze_event(detections)
    recent_memory = memory_store.recent(limit=policy["memory"]["recent_limit"])
    rule_decision = rule_engine.evaluate(
        detections=detections,
        event=event,
        policy=policy,
        memory=recent_memory,
    )

    if should_consult_expert(policy, event, rule_decision):
        expert_decision = expert_system.analyze(
            image_bytes=contents,
            detections=detections,
            memory=recent_memory,
            policy=policy,
            event=event,
        )
        expert_decision["rule_decision"] = rule_decision
        expert_decision.setdefault("source", policy.get("expert", {}).get("backend", "expert"))
    else:
        expert_decision = rule_decision

    record = memory_store.store_event(
        detections=detections,
        event=event,
        expert_decision=expert_decision,
        source=source_id or file.filename or "frame.jpg",
    )
    policy_update = agent_loop.process(record, expert_decision)

    result = {
        "event": event,
        "detections": detections,
        "expert": expert_decision,
        "policy_update": policy_update,
        "frame": frame_size,
        "runtime": detector.describe_runtime(policy_engine.get_policy()),
        "feed": {"id": source_id, "name": source_name, "live": live_source},
    }
    app.state.latest_result = result
    update_feed_state(
        app.state.feeds,
        source_id=source_id,
        source_name=source_name,
        live_source=live_source,
        frame_path=str(feed_frame_path),
        frame_size=frame_size,
        result=result,
    )
    return result


# ---------- Internal RF Pipeline Helpers ----------
def _process_rf_batch(
    app_state,
    *,
    observations: list[dict[str, Any]],
    source_id: str,
    source_name: str,
    source_kind: str,
    live_source: bool,
    replay_meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    policy_engine: PolicyEngine = app_state.policy_engine
    memory_store: MemoryStore = app_state.memory_store
    detector: YoloDetector = app_state.detector
    expert_system: ExpertSystem = app_state.expert_system
    rule_engine: RuleEngine = app_state.rule_engine
    agent_loop: AgentLoop = app_state.agent_loop
    wifi_engine: WifiEngine = app_state.wifi_engine

    policy = policy_engine.get_policy()
    memory_store.max_events = int(policy["memory"].get("max_events", memory_store.max_events))

    rf_out = wifi_engine.ingest_batch(
        observations,
        policy=policy,
        source_id=source_id,
        source_name=source_name,
        source_kind=source_kind,
        replay_meta=replay_meta,
    )
    vision = rf_out["vision"]
    detections = rf_out["detections"]

    palette = str(policy.get("wifi", {}).get("vision_palette", "night_vision"))
    frame_bytes = render_vision_jpeg(vision, palette_name=palette)
    LATEST_FRAME_PATH.write_bytes(frame_bytes)
    app_state.latest_frame_updated_at = datetime.now(timezone.utc).isoformat()
    feed_frame_path = write_feed_frame(source_id, frame_bytes)
    frame_size = vision["frame_size"]

    if not policy.get("controls", {}).get("detection_enabled", True):
        result = {
            "event": {
                "important": False,
                "reason": "RF rule analysis paused (monitoring raw signal)",
                "objects": [],
                "filtered_objects": [],
                "watch_matches": [],
                "ignored_objects": [],
            },
            "detections": detections,
            "expert": {"action": "ignore", "reason": "Detection disabled", "confidence": 0.0},
            "policy_update": None,
            "frame": frame_size,
            "runtime": detector.describe_runtime(policy),
            "feed": {"id": source_id, "name": source_name, "live": live_source},
            "vision": vision,
        }
        app_state.latest_result = result
        update_feed_state(
            app_state.feeds,
            source_id=source_id,
            source_name=source_name,
            live_source=live_source,
            frame_path=str(feed_frame_path),
            frame_size=frame_size,
            result=result,
        )
        return result

    event = policy_engine.analyze_event(detections)
    recent_memory = memory_store.recent(limit=policy["memory"]["recent_limit"])
    rule_decision = rule_engine.evaluate(
        detections=detections,
        event=event,
        policy=policy,
        memory=recent_memory,
        vision=vision,
    )

    if should_consult_expert(policy, event, rule_decision):
        expert_decision = expert_system.analyze(
            image_bytes=frame_bytes,
            detections=detections,
            memory=recent_memory,
            policy=policy,
            event=event,
        )
        expert_decision["rule_decision"] = rule_decision
        expert_decision.setdefault("source", policy.get("expert", {}).get("backend", "expert"))
        memory_store.log("decision", "Expert RF decision produced", expert_decision)
    else:
        expert_decision = rule_decision
        if rule_decision.get("action") == "alert":
            memory_store.log("alert", str(rule_decision.get("reason")), {"source": source_id})

    record = memory_store.store_event(
        detections=detections,
        event=event,
        expert_decision=expert_decision,
        source=source_id,
    )
    policy_update = agent_loop.process(record, expert_decision)
    if policy_update:
        memory_store.log("system", "Adaptive policy updated", policy_update)

    result = {
        "event": event,
        "detections": detections,
        "expert": expert_decision,
        "policy_update": policy_update,
        "frame": frame_size,
        "runtime": detector.describe_runtime(policy_engine.get_policy()),
        "feed": {"id": source_id, "name": source_name, "live": live_source},
        "vision": vision,
    }
    app_state.latest_result = result
    update_feed_state(
        app_state.feeds,
        source_id=source_id,
        source_name=source_name,
        live_source=live_source,
        frame_path=str(feed_frame_path),
        frame_size=frame_size,
        result=result,
    )
    return result


async def _analyze_rf_capture_upload(app_state, contents: bytes, *, filename: str) -> dict[str, Any]:
    observations = parse_capture_bytes(contents, filename=filename)
    if not observations:
        raise HTTPException(status_code=400, detail="No valid 802.11 / RF observations found in capture file")

    policy = app_state.policy_engine.get_policy()
    sample_interval = max(0.25, float(policy["video_analysis"].get("sample_interval_seconds", 1.0)))
    max_frames = max(1, int(policy["video_analysis"].get("max_frames", 24)))
    slices = slice_capture_into_frames(observations, bucket_seconds=sample_interval, max_frames=max_frames)

    capture_id = uuid.uuid4().hex[:10]
    scratch_engine = WifiEngine()
    temp_memory = MemoryStore(max_events=200)
    rule_engine: RuleEngine = app_state.rule_engine
    policy_engine: PolicyEngine = app_state.policy_engine

    timeline: list[dict[str, Any]] = []
    actions: list[str] = []
    all_labels: set[str] = set()

    for idx, obs_slice in enumerate(slices):
        out = scratch_engine.ingest_batch(
            obs_slice,
            policy=policy,
            source_id=f"capture_{capture_id}",
            source_name=filename,
            source_kind="capture_upload",
        )
        dets = out["detections"]
        ev = policy_engine.analyze_event(dets)
        dec = rule_engine.evaluate(
            detections=dets,
            event=ev,
            policy=policy,
            memory=temp_memory.recent(limit=12),
            vision=out["vision"],
        )
        temp_memory.store_event(detections=dets, event=ev, expert_decision=dec, source=filename)
        for d in dets:
            all_labels.add(str(d.get("label", "")))
        actions.append(str(dec.get("action", "ignore")))
        timeline.append(
            {
                "frame_index": idx,
                "packet_count": len(obs_slice),
                "detections": dets,
                "event": ev,
                "expert": dec,
                "disturbance": out["vision"]["metrics"]["disturbance"],
                "occupancy": out["vision"]["occupancy"]["estimate"],
            }
        )

    app_state.captures[capture_id] = {
        "capture_id": capture_id,
        "filename": filename,
        "slices": slices,
        "total_packets": len(observations),
    }

    # Immediately render the final/most informative slice into live Night-Vision Cam so user sees it!
    preview_idx = max(0, len(slices) - 1)
    _process_rf_batch(
        app_state,
        observations=slices[preview_idx],
        source_id=f"replay_{capture_id}",
        source_name=f"Capture: {filename}",
        source_kind="capture_replay",
        live_source=False,
        replay_meta={
            "capture_id": capture_id,
            "filename": filename,
            "frame_index": preview_idx,
            "total_frames": len(slices),
        },
    )

    summary = {
        "capture_id": capture_id,
        "filename": filename,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "frames_processed": len(slices),
        "total_packets": len(observations),
        "sample_interval_seconds": sample_interval,
        "aggregated_labels": sorted(all_labels),
        "alert_frames": [item for item in timeline if item["expert"].get("action") == "alert"],
        "timeline": timeline,
        "dominant_action": "alert" if "alert" in actions else "ignore",
    }
    app_state.video_analyses.append(summary)
    app_state.memory_store.log(
        "system",
        f"Analyzed RF capture {filename}",
        {"capture_id": capture_id, "packets": len(observations), "slices": len(slices)},
    )
    return summary


def _analyze_legacy_video_upload(app_state, contents: bytes, *, filename: str, suffix: str) -> dict[str, Any]:
    try:
        cv2 = __import__("cv2")
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail="OpenCV is disabled in Wi-Fi mode; upload .pcap, .pcapng, .csv, or .jsonl RF captures instead.",
        ) from exc

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as handle:
        handle.write(contents)
        temp_path = Path(handle.name)
    capture = cv2.VideoCapture(str(temp_path))
    if not capture.isOpened():
        temp_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="Unable to open uploaded video")
    capture.release()
    temp_path.unlink(missing_ok=True)
    summary = {
        "capture_id": uuid.uuid4().hex[:10],
        "filename": filename,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "frames_processed": 0,
        "aggregated_labels": [],
        "timeline": [],
        "dominant_action": "ignore",
    }
    app_state.video_analyses.append(summary)
    return summary


async def _simulator_loop(app_state) -> None:
    try:
        while app_state.sim_running:
            app_state.sim_tick += 1
            scenario = app_state.sim_scenario or "mixed"
            obs = app_state.wifi_engine.generate_sim_observations(scenario=scenario, tick=app_state.sim_tick)
            _process_rf_batch(
                app_state,
                observations=obs,
                source_id="sim_rf",
                source_name=f"RF Simulator ({scenario})",
                source_kind="simulator",
                live_source=True,
            )
            await asyncio.sleep(0.55)
    except asyncio.CancelledError:
        pass


async def _host_scan_loop(app_state, iface: str) -> None:
    try:
        while app_state.host_scan_running:
            obs = await poll_host_wifi_once(iface)
            if obs:
                _process_rf_batch(
                    app_state,
                    observations=obs,
                    source_id=f"host_{iface}",
                    source_name=f"Host Wi-Fi ({iface})",
                    source_kind="host_wifi",
                    live_source=True,
                )
            await asyncio.sleep(1.8)
    except asyncio.CancelledError:
        pass


async def _replay_loop(app_state, capture: dict[str, Any], *, start_idx: int, speed: float) -> None:
    slices = capture["slices"]
    capture_id = capture["capture_id"]
    if start_idx == 0:
        app_state.wifi_engine.reset_state()
    try:
        for idx in range(start_idx, len(slices)):
            if not app_state.replay_running:
                break
            _process_rf_batch(
                app_state,
                observations=slices[idx],
                source_id=f"replay_{capture_id}",
                source_name=f"Replay: {capture['filename']}",
                source_kind="capture_replay",
                live_source=False,
                replay_meta={
                    "capture_id": capture_id,
                    "filename": capture["filename"],
                    "frame_index": idx,
                    "total_frames": len(slices),
                },
            )
            await asyncio.sleep(max(0.15, 0.85 / speed))
    except asyncio.CancelledError:
        pass
    finally:
        app_state.replay_running = False


async def _stop_task(app_state, attr_name: str) -> None:
    task = getattr(app_state, attr_name, None)
    setattr(app_state, attr_name, None)
    if task is not None and not task.done():
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task


def detect_host_wifi_interface() -> str:
    net_dir = Path("/sys/class/net")
    if net_dir.exists():
        for iface in sorted(net_dir.iterdir()):
            if (iface / "wireless").is_dir():
                return iface.name
    return "wlan0"


def _split_nmcli_escaped(line: str) -> list[str]:
    parts: list[str] = []
    cur: list[str] = []
    escaped = False
    for ch in line:
        if escaped:
            cur.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


async def poll_host_wifi_once(iface: str) -> list[dict[str, Any]]:
    observations: list[dict[str, Any]] = []
    try:
        proc = await asyncio.create_subprocess_exec(
            "nmcli",
            "-t",
            "-f",
            "IN-USE,BSSID,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY",
            "dev",
            "wifi",
            "list",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5.0)
        if proc.returncode == 0:
            for line in stdout.decode("utf-8", errors="ignore").splitlines():
                if not line.strip():
                    continue
                cols = _split_nmcli_escaped(line.strip())
                if len(cols) < 7:
                    continue
                in_use = cols[0].strip() == "*"
                bssid = cols[1].strip().lower()
                ssid = cols[2].strip()
                try:
                    ch = int(cols[3].strip())
                except ValueError:
                    ch = 6
                rate_val = 0.0
                for tok in cols[5].split():
                    try:
                        rate_val = float(tok)
                        break
                    except ValueError:
                        continue
                try:
                    pct = int(cols[6].strip())
                except ValueError:
                    pct = 35
                rssi = -98 if pct <= 0 else (-35 if pct >= 100 else (pct // 2) - 100)
                sec = cols[7].strip() if len(cols) >= 8 else ""
                observations.append(
                    {
                        "node_id": f"host-{iface}",
                        "source": "host_wifi_nmcli",
                        "channel": ch,
                        "rssi": rssi,
                        "frame_type": "mgmt",
                        "subtype": "beacon",
                        "sa": bssid,
                        "bssid": bssid,
                        "ssid": ssid,
                        "security": sec,
                        "rate": rate_val,
                        "in_use": in_use,
                    }
                )
    except Exception:
        pass
    return observations


def describe_sources_status(app_state) -> dict[str, Any]:
    return {
        "simulator_running": bool(app_state.sim_running),
        "simulator_scenario": app_state.sim_scenario,
        "host_scan_running": bool(app_state.host_scan_running),
        "host_interface": app_state.host_scan_iface,
        "replay_running": bool(app_state.replay_running),
    }


def extract_frame_size(image_bytes: bytes) -> dict:
    image = Image.open(BytesIO(image_bytes))
    return {"width": image.width, "height": image.height}


def write_feed_frame(source_id: str, image_bytes: bytes) -> Path:
    FEEDS_DIR.mkdir(parents=True, exist_ok=True)
    safe_id = sanitize_feed_id(source_id)
    frame_path = FEEDS_DIR / f"{safe_id}.jpg"
    frame_path.write_bytes(image_bytes)
    return frame_path


def sanitize_feed_id(feed_id: str) -> str:
    cleaned = "".join(char if char.isalnum() or char in {"_", "-"} else "_" for char in (feed_id or "default"))
    return cleaned or "default"


def update_feed_state(
    feeds: dict,
    *,
    source_id: str,
    source_name: str,
    live_source: bool,
    frame_path: str,
    frame_size: dict,
    result: dict,
) -> None:
    feed_key = sanitize_feed_id(source_id)
    feed = feeds.get(feed_key, {})
    feed.update(
        {
            "id": feed_key,
            "source_id": source_id,
            "name": source_name,
            "live": live_source,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "frame_path": frame_path,
            "frame_size": frame_size,
            "result": result,
            "frame_url": f"/feed-frame/{feed_key}?t={datetime.now(timezone.utc).isoformat()}",
        }
    )
    feeds[feed_key] = feed


def list_feed_snapshots(feeds: dict) -> list[dict]:
    items = []
    for feed in feeds.values():
        result = feed.get("result") or {}
        items.append(
            {
                "id": feed.get("id"),
                "source_id": feed.get("source_id"),
                "name": feed.get("name"),
                "live": feed.get("live", True),
                "updated_at": feed.get("updated_at"),
                "frame_url": feed.get("frame_url"),
                "frame": feed.get("frame_size"),
                "detections": result.get("detections", []),
                "event": result.get("event", {}),
                "expert": result.get("expert", {}),
            }
        )
    items.sort(key=lambda item: item.get("updated_at") or "", reverse=True)
    return items


def resolve_chat_result(app_state, feed_id: str | None) -> dict | None:
    if feed_id:
        feed = app_state.feeds.get(feed_id) or app_state.feeds.get(sanitize_feed_id(feed_id))
        if feed:
            return feed.get("result")
    return app_state.latest_result


def should_consult_expert(policy: dict, event: dict, rule_decision: dict) -> bool:
    expert_cfg = policy.get("expert", {})
    if not bool(expert_cfg.get("realtime_enabled", False)):
        return False
    if bool(expert_cfg.get("realtime_only_important", True)):
        return bool(event.get("important") or rule_decision.get("action") == "alert")
    return True


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
