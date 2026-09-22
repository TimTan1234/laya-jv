# CUDA=0 builds the CPU-only image (default). CUDA=1 installs CUDA-enabled torch
# for `--gpus all` deployments (see run.sh USE_GPU=1 / docker-compose.gpu.yml).
ARG CUDA=0

FROM python:3.11-slim

ARG CUDA

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models/hf \
    OMP_NUM_THREADS=4

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# CPU-only torch wheel keeps the image ~5x smaller than the CUDA default.
# CUDA torch is pinned to 2.5.1+cu121: works with Windows/WSL driver >= 530
# and supports laptop GPUs from GTX 1650 (sm_75) upward.
RUN if [ "$CUDA" = "1" ]; then \
        pip install --no-cache-dir "torch==2.5.1" --index-url https://download.pytorch.org/whl/cu121; \
    else \
        pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu; \
    fi

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Laya engine, vendored from github.com/NandhaKishorM/laya
COPY laya-src /opt/laya-src
RUN pip install --no-cache-dir /opt/laya-src

# Pre-download the default checkpoint at build time so the container runs offline.
# Luna serves English + Chinese users -> multilingual checkpoint by default.
ARG LAYA_MODEL=multilingual
ENV LAYA_MODEL=${LAYA_MODEL}
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('convaiinnovations/laya', allow_patterns=['${LAYA_MODEL}/*'])"

COPY server.py .

# On a 4GB GPU keep the caching allocator compact; harmless elsewhere.
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

EXPOSE 8100
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8100"]
