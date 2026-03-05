#!/bin/bash
set -e  # Dừng ngay nếu có lỗi

echo "===== Starting PaddleOCR-VL Pipeline (Single Container) ====="
echo "Current time: $(date)"
echo "Container has GPU access: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'No GPU detected')"

# 1. Khởi động Triton server
echo "[1/3] Starting Triton server..."
cd /app/triton || { echo "Error: /app/triton not found!"; exit 1; }

# Nếu có server.sh, chạy nó; nếu không, fallback tritonserver trực tiếp
if [ -f "server.sh" ]; then
  bash server.sh &
else
  echo "Warning: server.sh not found, trying default tritonserver..."
  tritonserver --model-repository=/models --api-port=8001 --http-port=8000 --grpc-port=8002 &
fi
TRITON_PID=$!

# Wait Triton ready (tăng timeout lên 120s để an toàn)
echo "Waiting for Triton healthcheck (max 120s)..."
for i in {1..24}; do
  if curl -f -s http://localhost:8000/v2/health/ready > /dev/null; then
    echo "Triton ready! (took $((i*5)) seconds)"
    break
  fi
  sleep 5
  echo "Still waiting... ($i/24)"
done
[ $i -eq 24 ] && { echo "Error: Triton timeout!"; exit 1; }

# 2. Khởi động vLLM / genai_server
echo "[2/3] Starting vLLM genai_server..."
paddleocr genai_server \
  --model_name PaddleOCR-VL-1.5-0.9B \
  --host 127.0.0.1 \
  --port 8081 \
  --backend vllm &
VLM_PID=$!

# Wait vLLM ready (tăng timeout 300s vì model load có thể lâu)
echo "Waiting for vLLM healthcheck (max 300s)..."
for i in {1..60}; do
  if curl -f -s http://localhost:8081/health > /dev/null; then
    echo "vLLM ready! (took $((i*5)) seconds)"
    break
  fi
  sleep 5
  echo "Still waiting... ($i/60)"
done
[ $i -eq 60 ] && { echo "Error: vLLM timeout!"; exit 1; }

# 3. Khởi động Gateway API
echo "[3/3] Starting Gateway API..."
cd /app/gateway || { echo "Error: /app/gateway not found!"; exit 1; }

exec uvicorn --host 0.0.0.0 --port 8080 --workers ${UVICORN_WORKERS:-4} app:app