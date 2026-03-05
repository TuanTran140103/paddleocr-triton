# Stage 1: Triton (files ở /app)
FROM tuantran2003/paddleocr-vl-tritonserver:latest AS triton-stage

# Stage 2: Gateway (files ở /app)
FROM tuantran2003/paddleocr-vl-api:latest AS gateway-stage

# Stage 3: Base từ image Baidu (đã có vLLM + genai_server)
FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-genai-vllm-server:latest-nvidia-gpu

USER root

WORKDIR /app

# COPY Triton files (tồn tại ở /app trong source)
COPY --from=triton-stage /app /app/triton

# COPY Triton binaries + libs vào image (base image Baidu không có)
COPY --from=triton-stage /opt/tritonserver /opt/tritonserver

# FIX: copy đúng các thư viện .so cần thiết cho tritonserver từ triton-stage
# (thay vì apt-get bị lỗi do Baidu mirror)
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libre2.so.5* /usr/lib/x86_64-linux-gnu/
RUN ldconfig

ENV PATH="/opt/tritonserver/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/tritonserver/lib:${LD_LIBRARY_PATH}"

# COPY Gateway files (code ở /app)
COPY --from=gateway-stage /app /app/gateway

# COPY site-packages từ gateway (đây là bước copy các thư viện Gateway vào image)
COPY --from=gateway-stage /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

# FIX: sau khi copy site-packages từ gateway (có huggingface-hub==1.5.0),
# cần pin lại phiên bản để tương thích với transformers/vLLM của image Baidu
# Phải làm SAU lệnh COPY để không bị ghi đè
RUN pip install --no-cache-dir "huggingface-hub>=0.34.0,<1.0" "urllib3<2"

# Cấu hình cache
ENV PADDLE_HOME=/root/.paddleocr
ENV PADDLEX_HOME=/root/.paddlex
ENV PADDLE_PDX_PAG_MODEL_DIR=/root/.paddlex/models
ENV PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

# Tạo các thư mục cần thiết và phân quyền
RUN mkdir -p $PADDLE_HOME $PADDLEX_HOME /paddlex/var/paddlex_model_repo \
    && chmod -R 777 /root /paddlex/var

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
