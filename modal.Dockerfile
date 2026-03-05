# Stage 1: Triton
FROM tuantran2003/paddleocr-vl-tritonserver:latest AS triton-stage

# Stage 2: Gateway
FROM tuantran2003/paddleocr-vl-api:latest AS gateway-stage

# Stage 3: Base từ image Baidu (đã có vLLM + genai_server)
FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-genai-vllm-server:latest-nvidia-gpu

# Install thêm nếu thiếu
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl libgl1 \
    && rm -rf /var/lib/apt/lists/*

# TẠO THƯ MỤC CHO TRITON MODEL REPO (fix lỗi cp trong server.sh)
RUN mkdir -p /paddlex/var/paddlex_model_repo \
    && chmod -R 777 /paddlex/var  
    # Đảm bảo permission để Triton write nếu cần

WORKDIR /app

# COPY Triton files
COPY --from=triton-stage /app /app/triton

# COPY Gateway files
COPY --from=gateway-stage /app /app/gateway

# COPY deps pip từ gateway nếu có custom (comment nếu không cần)
# COPY --from=gateway-stage /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

# Copy start.sh
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Env vars full từ README
ENV HPS_TRITON_URL=http://127.0.0.1:8001
ENV HPS_VLM_URL=http://127.0.0.1:8081
ENV HPS_MAX_CONCURRENT_INFERENCE_REQUESTS=16
ENV HPS_MAX_CONCURRENT_NON_INFERENCE_REQUESTS=64
ENV HPS_INFERENCE_TIMEOUT=600
ENV HPS_LOG_LEVEL=INFO
ENV UVICORN_WORKERS=4
ENV PADDLEX_HPS_DEVICE_TYPE=gpu  # Ưu tiên GPU trên Modal

ENV MODEL_NAME=PaddleOCR-VL-1.5-0.9B
ENV GENAI_PORT=8081
ENV GATEWAY_PORT=8080

EXPOSE 8080

CMD ["/app/start.sh"]