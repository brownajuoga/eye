#!/bin/bash
set -e

echo "==========================================="
echo "   Eye Surveillance Platform Setup Script  "
echo "==========================================="

echo ""
echo "[1/3] Installing System Dependencies (OpenCV for Scout & Python venv)"
echo "You will be prompted for your sudo password."
sudo apt-get update
sudo apt-get install -y pkg-config libopencv-dev python3.14-venv python3-venv zenity

echo ""
echo "[2/3] Setting up Python Virtual Environment..."
cd "$(dirname "$0")"

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

# Activate and install requirements
source .venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn pillow pyyaml python-multipart opencv-python ultralytics

echo ""
echo "[3/3] Setup Complete!"
echo "-------------------------------------------"
echo "To run the AI server, open a terminal and run:"
echo "  source .venv/bin/activate"
echo "  python3 ai_server/main.py"
echo ""
echo "To run Scout, open another terminal and run:"
echo "  cd scout"
echo "  go run . detect -source auto -api-url http://127.0.0.1:8080 -headless"
echo ""
echo "To run the UI, open another terminal and run:"
echo "  cd ui"
echo "  flutter run -d chrome"
echo "==========================================="
