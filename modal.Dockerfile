# Stage 1: Triton
FROM tuantran2003/paddleocr-vl-tritonserver:latest AS triton-stage

# Stage 2: Gateway
FROM tuantran2003/paddleocr-vl-api:latest AS gateway-stage

# Stage 3: Base từ image vLLM Baidu (đã có genai_server, vLLM, PaddlePaddle GPU)
FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-genai-vllm-server:latest-nvidia-gpu

# Install system deps nếu thiếu (curl, libgl1 thường đã có, nhưng thêm cho an toàn)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl libgl1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# COPY Triton files
COPY --from=triton-stage /app /app/triton

# COPY Gateway files + pip deps nếu cần
COPY --from=gateway-stage /app /app/gateway
COPY --from=gateway-stage /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages  # Nếu gateway có deps custom

# Nếu cần thêm deps từ gateway (nhưng image Baidu đã có vLLM/paddleocr, nên có thể skip pip install)

# Copy start.sh
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Env vars localhost
ENV HPS_TRITON_URL=http://127.0.0.1:8001
ENV HPS_VLM_URL=http://127.0.0.1:8081
ENV UVICORN_WORKERS=4
ENV PADDLEX_HPS_DEVICE_TYPE=cpu

EXPOSE 8080

CMD ["/app/start.sh"]