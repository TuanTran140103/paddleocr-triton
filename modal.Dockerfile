# Stage 1: Triton (files ở /app)
FROM tuantran2003/paddleocr-vl-tritonserver:latest AS triton-stage

# Stage 2: Gateway (files ở /app)
FROM tuantran2003/paddleocr-vl-api:latest AS gateway-stage

# Stage 3: Base từ image Baidu (đã có vLLM + genai_server)
FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-genai-vllm-server:latest-nvidia-gpu

# Install thêm nếu thiếu (thường không cần vì Baidu image có sẵn)
# RUN apt-get update \
#     && apt-get install -y --no-install-recommends curl libgl1 \
#     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# COPY Triton files (tồn tại ở /app trong source)
COPY --from=triton-stage /app /app/triton

# COPY Gateway files (tồn tại ở /app trong source)
COPY --from=gateway-stage /app /app/gateway

# Nếu gateway install deps vào site-packages, COPY chúng (nếu có custom wheel hoặc deps không trùng Baidu image)
COPY --from=gateway-stage /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

USER root

# Cấu hình đường dẫn cache cố định (để dễ dàng mount volume)
ENV PADDLE_HOME=/root/.paddleocr
ENV PADDLEX_HOME=/root/.paddlex
RUN mkdir -p $PADDLE_HOME $PADDLEX_HOME /paddlex/var/paddlex_model_repo \
    && chmod -R 777 /root /paddlex/var

# [Tùy chọn] Warmup model - Tải model về ngay lúc build để giảm thời gian start container
# Lưu ý: Bước này cần internet. Nếu build offline hãy comment lại.
# Chúng ta dùng script python nhỏ để kích hoạt download thông qua paddlex
RUN python3 -c "import paddlex; paddlex.create_pipeline('PaddleOCR-VL-1.5-0.9B')" || true

# Copy start.sh
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Env vars cho app
ENV HPS_TRITON_URL=http://127.0.0.1:8001
ENV HPS_VLM_URL=http://127.0.0.1:8081
ENV UVICORN_WORKERS=4
ENV PADDLEX_HPS_DEVICE_TYPE=gpu

EXPOSE 8080

CMD ["/app/start.sh"]
