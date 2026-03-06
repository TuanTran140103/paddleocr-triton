# Stage 1: Triton (files ở /app)
FROM tuantran2003/paddleocr-vl-tritonserver:latest AS triton-stage

# Stage 2: Gateway (files ở /app)
FROM tuantran2003/paddleocr-vl-api:latest AS gateway-stage

# Stage 3: Base từ image Baidu (đã có vLLM + genai_server)
FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-genai-vllm-server:latest-nvidia-gpu

USER root

WORKDIR /app

# 1. Cấu hình Cơ sở hạ tầng (Binaries & System Libs) - Ít thay đổi nhất
# COPY Triton binaries + libs vào image
COPY --from=triton-stage /opt/tritonserver /opt/tritonserver

# FIX: copy đúng các thư viện .so cần thiết cho tritonserver từ triton-stage
RUN mkdir -p /opt/triton_deps
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libre2.so.5* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libssl.so.1.1* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libb64.so* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libdcgm.so* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libssh.so* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libarchive.so.13* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/liblzo2.so* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libnettle.so* /opt/triton_deps/
COPY --from=triton-stage /usr/lib/x86_64-linux-gnu/libhogweed.so* /opt/triton_deps/
# Bổ sung thư viện CUDA 11.0 mà Triton backend đang đòi hỏi
COPY --from=triton-stage /usr/local/cuda/lib64/libcudart.so.11.0* /opt/triton_deps/
COPY --from=triton-stage /usr/local/cuda/lib64/libcublas.so.11* /opt/triton_deps/
COPY --from=triton-stage /usr/local/cuda/lib64/libcublasLt.so.11* /opt/triton_deps/

RUN ldconfig /opt/triton_deps/

ENV PATH="/opt/tritonserver/bin:${PATH}"
# Thêm /opt/triton_deps vào LD_LIBRARY_PATH. Khởi tạo nếu trống để tránh cảnh báo.
ENV LD_LIBRARY_PATH="/opt/tritonserver/lib:/opt/triton_deps:${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# 2. Cấu hình Python Environment - Thay đổi khi thêm thư viện
# COPY site-packages từ gateway
COPY --from=gateway-stage /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

# Pin lại phiên bản huggingface-hub. 
# Bỏ qua giới hạn urllib3 vì tritonclient cần bản mới (2.x) vốn đã có trong base image.
RUN pip install --no-cache-dir "huggingface-hub>=0.34.0,<1.0"

# 3. Cấu hình Biến môi trường & Thư mục (Static)
ENV PADDLE_HOME=/root/.paddleocr
ENV PADDLEX_HOME=/root/.paddlex
ENV PADDLE_PDX_PAG_MODEL_DIR=/root/.paddlex/models
ENV PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

RUN mkdir -p $PADDLE_HOME $PADDLEX_HOME /paddlex/var/paddlex_model_repo \
    && chmod -R 777 /root /paddlex/var

# 4. Copy Mã nguồn ứng dụng - Thay đổi thường xuyên nhất (Bỏ xuống cuối để tối ưu cache)
COPY --from=triton-stage /app /app/triton
COPY --from=gateway-stage /app /app/gateway
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Env vars cho app
ENV HPS_TRITON_URL=127.0.0.1:8001
ENV HPS_VLM_URL=http://127.0.0.1:8081
ENV UVICORN_WORKERS=4
ENV PADDLEX_HPS_DEVICE_TYPE=gpu

EXPOSE 8080

CMD ["/app/start.sh"]
