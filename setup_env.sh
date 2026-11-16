#!/bin/bash
set -e

echo "==========================================="
echo "  eye Wi-Fi RF Intelligence Setup Script   "
echo "==========================================="

cd "$(dirname "$0")"

echo ""
echo "[1/3] Setting up lightweight Python Virtual Environment (ai_server/venv)..."
if [ ! -d "ai_server/venv" ]; then
    python3 -m venv ai_server/venv
fi

ai_server/venv/bin/pip install --upgrade pip
ai_server/venv/bin/pip install fastapi uvicorn pillow pyyaml python-multipart

echo ""
echo "[2/3] Building Pure-Go Scout Wi-Fi Collector (no OpenCV required)..."
(cd scout && go build -o scout . && go test ./...)

echo ""
echo "[3/3] Setup Complete!"
echo "-------------------------------------------"
echo "1) Start Python server:"
echo "   ai_server/venv/bin/python ai_server/main.py"
echo ""
echo "2) Start Scout (optional if using UI Host Scan / Simulator):"
echo "   cd scout && ./scout detect -source auto -api-url http://127.0.0.1:8080"
echo ""
echo "3) Run Flutter UI:"
echo "   cd ui && flutter run -d chrome --dart-define=EYE_API_BASE_URL=http://127.0.0.1:8080"
echo "==========================================="
