#  eye

**Event-Driven Vision Monitoring for Low-Cost Hardware**

`eye` is an event-driven video analysis system designed to run on modest, low-cost hardware while still delivering useful scene awareness.

Instead of running a giant vision-language model on every frame, **eye keeps the realtime path small and fast**. Scout detects motion, YOLO identifies objects, and a deterministic rule engine turns detections into alerts, idle behavior, and model-control decisions. Heavier expert reasoning remains available as an optional review layer for summaries, chat, or selected important events.

The project is optimized for environments where bandwidth, hardware, and cost are real constraints — such as small shops, homes, offices, and kiosks.

---

##  Why eye?

Traditional CCTV and motion-detection systems:

* Generate too many false alarms
* Require constant human monitoring
* Depend on expensive cloud subscriptions
* Waste bandwidth and storage

**eye solves this by filtering noise before any expensive reasoning runs**, using a small event pipeline that scales from tiny pixel changes to actionable alerts.

---

##  System Architecture

| Tier   | Name           | Technology          | Responsibility                                            |
| ------ | -------------- | ------------------- | --------------------------------------------------------- |
| Tier 1 | **Scout**      | Go + GoCV (OpenCV)  | Detects tiny visual disturbances with near-zero CPU usage |
| Tier 2 | **Detector**   | YOLO (Python)       | Confirms *what* is moving (person, bag, vehicle, etc.)    |
| Tier 3 | **Rule Engine**| Python policy logic | Applies watchlists, thresholds, and automation rules      |
| Tier 4 | **Expert**     | Optional LLM/VLM    | Runs only when enabled for chat, summaries, or review     |

### Example Flow

1. Camera detects movement → **Scout** triggers
2. YOLO confirms relevant objects (e.g. *person + bag*)
3. The rule engine evaluates watchlists and automation rules
4. User receives a fast alert, log entry, or control update
5. Optional expert reasoning can review selected events asynchronously

---

##  Key Features

* 🧠 **Lightweight Rule Intelligence**
  Express behaviors such as `IF person detected with confidence > 0.60` without running an LLM in the hot path.

* ⚡ **Edge-Optimized Performance**
  Built in Go for speed, concurrency, and low memory usage.
 
* 📉 **Bandwidth Efficient**
  Only short, confirmed event clips are sent to the user.

* 🧩 **Modular & Extensible**
  Go controls logic, Python handles AI inference.

---

## 🧰 Tech Stack

### Core Engine

* **Go (Golang)** – system controller and concurrency engine
* **GoCV (OpenCV)** – video capture and motion analysis

### AI & Vision

* **YOLO Nano models** – fast object detection on CPU
* **Rule engine** – realtime decision layer for alerts, idle handling, and control changes
* **Ollama / Transformers** (optional) – expert review when explicitly enabled

### Communication & Alerts

* **FastAPI** – Go ↔ Python bridge
* **Telegram Bot API / Discord Webhooks** – notifications

---

## 📁 Project Structure (Planned)

```
eye/
├── scout/              # Go application (motion detection & control)
│   ├── main.go
│   └── detector.go
│
├── ai_server/          # Python AI sidecar
│   ├── main.py
│   ├── yolo.py
│   └── llava.py
│
├── configs/
│   └── prompts.yaml   # User-defined event prompts
│
├── scripts/
│   └── install.sh 
│
└── README.md
```

---

## 🚀 Getting Started (Development)

### 1️⃣ Requirements

* Go ≥ 1.20
* Python ≥ 3.9
* OpenCV 4.x
* Webcam or video file

---

### 2️⃣ Install GoCV

Follow the official GoCV installation guide for your OS:
[https://gocv.io/getting-started/](https://gocv.io/getting-started/)

> This is the most technical setup step. Complete it first.

---

### 3️⃣ Run the Scout (Go)

```bash
cd scout
go run main.go
```

You should see:

* Live video feed
* Console logs when disturbances are detected

---

### 4️⃣ Start the AI Server (Python)

```bash
cd ai_server
pip install -r requirements.txt
python main.py
```

This starts:

* YOLO object detection
* The realtime rule engine
* Optional expert/chat endpoints

---

## 🎯 Example Automation Rules

* `IF person detected with confidence > 0.60` → `Create alert and keep balanced mode active`
* `IF no objects for 120 seconds` → `Reduce analysis frequency and mark system idle`
* `IF watched object detected` → `Notify operator`

---

## 🌍 Project Vision

**eye** aims to make intelligent video understanding accessible where:

* Internet is expensive
* Hardware is limited
* Existing solutions are overkill

The focus is on **practical intelligence**, not constant surveillance.

---

## 🤝 Contributing

Contributions are welcome:

* Performance optimizations
* New event types
* UI / dashboard
* Mobile notifications
* Additional language support

---
