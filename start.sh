echo "🚀 [0/3] Preparing environment..."

# 1. Liên kết các Volume từ Modal (nếu có)
# Model cache (PaddleX & PaddleOCR)
export PADDLE_HOME=${PADDLE_HOME:-"/root/.paddleocr"}
export PADDLEX_HOME=${PADDLEX_HOME:-"/root/.paddlex"}

if [ -d "/mnt/paddlex" ]; then
    echo "Found Modal Volume at /mnt/paddlex, linking..."
    rm -rf "$PADDLEX_HOME" && ln -s /mnt/paddlex "$PADDLEX_HOME"
fi
if [ -d "/mnt/paddleocr" ]; then
    echo "Found Modal Volume at /mnt/paddleocr, linking..."
    rm -rf "$PADDLE_HOME" && ln -s /mnt/paddleocr "$PADDLE_HOME"
fi

# Triton Model Repo
TRITON_REPO_DIR="/paddlex/var/paddlex_model_repo"
if [ -d "/mnt/paddlex_var" ]; then
    echo "Found Modal Volume at /mnt/paddlex_var, linking Triton repo..."
    mkdir -p /mnt/paddlex_var/paddlex_model_repo
    # Xoá thư mục tĩnh trong image và thay bằng symlink tới Volume
    rm -rf "/paddlex/var" && ln -s /mnt/paddlex_var "/paddlex/var"
fi

# Đảm bảo các thư mục tồn tại
mkdir -p "$PADDLE_HOME" "$PADDLEX_HOME" "$TRITON_REPO_DIR"

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