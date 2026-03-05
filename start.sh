#!/bin/bash
set -e

echo "🚀 [0/3] Preparing environment..."
export PADDLE_HOME=${PADDLE_HOME:-"/root/.paddleocr"}
export PADDLEX_HOME=${PADDLEX_HOME:-"/root/.paddlex"}

# Tạo các thư mục cache nếu chưa có (để mount volume dễ dàng)
mkdir -p "$PADDLE_HOME" "$PADDLEX_HOME" /paddlex/var/paddlex_model_repo

echo "📦 Parallel startup: Triton and vLLM servers..."

# 1. Khởi động Triton server (background)
echo "🔹 Starting Triton server..."
(
    cd /app/triton || exit 1
    if [ -f "server.sh" ]; then
        bash server.sh
    else
        tritonserver --model-repository=/models --api-port=8001 --http-port=8000 --grpc-port=8002
    fi
) &
TRITON_PID=$!

# 2. Khởi động vLLM genai_server (background)
echo "🔹 Starting vLLM genai_server..."
paddleocr genai_server \
  --model_name PaddleOCR-VL-1.5-0.9B \
  --host 127.0.0.1 \
  --port 8081 \
  --backend vllm &
VLM_PID=$!

# Function dọn dẹp khi stop container
cleanup() {
    echo "🛑 Stopping servers..."
    kill $TRITON_PID $VLM_PID 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Function check health
wait_for_service() {
    local name=$1
    local url=$2
    local timeout=$3
    echo "⏳ Waiting for $name at $url (max ${timeout}s)..."
    local start_time=$(date +%s)
    while true; do
        if curl -f -s "$url" > /dev/null; then
            echo "✅ $name is ready!"
            return 0
        fi
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ $elapsed -gt $timeout ]; then
            echo "❌ Error: $name timeout after ${timeout}s"
            return 1
        fi
        sleep 5
    done
}

# Đợi cả 2 dịch vụ sẵn sàng
wait_for_service "Triton" "http://localhost:8000/v2/health/ready" 120 &
WAIT_TRITON_PID=$!

wait_for_service "vLLM" "http://localhost:8081/health" 300 &
WAIT_VLM_PID=$!

wait $WAIT_TRITON_PID $WAIT_VLM_PID

# 3. Khởi động Gateway API
echo "🚀 [3/3] Starting Gateway API..."
cd /app/gateway || { echo "Error: /app/gateway not found!"; exit 1; }

# Chạy Uvicorn trực tiếp (thay thế process hiện tại để nhận tín hiệu OS)
exec uvicorn --host 0.0.0.0 --port 8080 --workers ${UVICORN_WORKERS:-4} app:app