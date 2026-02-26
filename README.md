#  eyeree to use, modify, and deploy.ree to use, modify, and deploy.ree to use, modify, and deploy.

**Event-Driven AI Video Monitoring for Low-Cost Hardware**

`eye` is a state-of-the-art, event-driven video analysis system designed to run on modest, low-cost hardware while still delivering intelligent, human-like understanding of video footage.

Instead of streaming video 24/7 or triggering alerts for every shadow or movement, **eye understands context**. Users describe what they are looking for in natural language (for example: *"Alert me if someone takes a bag from the counter"*), and the system only reports events that are *confirmed* by multiple AI stages.

The project is optimized for environments where bandwidth, hardware, and cost are real constraints — such as small shops, homes, offices, and kiosks.

---

##  Why eye?

Traditional CCTV and motion-detection systems:

* Generate too many false alarms
* Require constant human monitoring
* Depend on expensive cloud subscriptions
* Waste bandwidth and storage

**eye solves this by filtering noise before running expensive AI models**, using a multi-tier architecture that scales from tiny pixel changes to high-level reasoning.

---

##  System Architecture (Three-Tier Intelligence)

| Tier   | Name           | Technology          | Responsibility                                            |
| ------ | -------------- | ------------------- | --------------------------------------------------------- |
| Tier 1 | **Scout**      | Go + GoCV (OpenCV)  | Detects tiny visual disturbances with near-zero CPU usage |
| Tier 2 | **Gatekeeper** | YOLO11 (Python)     | Confirms *what* is moving (person, bag, vehicle, etc.)    |
| Tier 3 | **Expert**     | LLaVA / Video-LLaVA | Understands *intent* using natural language reasoning     |

### Example Flow

1. Camera detects movement → **Scout** triggers
2. YOLO11 confirms relevant objects (e.g. *person + bag*)
3. LLaVA analyzes intent based on the user prompt
4. User receives a **verified alert**, not raw motion data

---

##  Key Features

* 🗣️ **Natural Language Event Definition**
  Tell the system *what to watch for* — no retraining required.

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

* **YOLO11-Nano** – fast object detection on CPU
* **LLaVA / Video-LLaVA** – high-level reasoning and confirmation
* **Ollama** (optional) – local LLaVA inference

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

* YOLO11 object detection
* LLaVA reasoning endpoint

---

## 🎯 Example User Prompts

* "Alert me if someone reaches over the counter"
* "Notify me if a bag is removed from the table"
* "Watch for people entering after 9pm"
* "Tell me if someone loiters near the door"

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

## 📜 License

free to use, modify
