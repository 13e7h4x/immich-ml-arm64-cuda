# syntax=docker/dockerfile:1.7

ARG CUDA_IMAGE=nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04
ARG IMMICH_VERSION=v3.3.5
ARG IMMICH_MODEL_COMMIT=8bf3fd1b44b0c8608f52fb6e50ddff52826576d8
ARG ONNXRUNTIME_GPU_VERSION=1.31.0

FROM ${CUDA_IMAGE} AS builder
ARG IMMICH_VERSION
ARG IMMICH_MODEL_COMMIT
ARG ONNXRUNTIME_GPU_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH
RUN sed -i 's|http://ports.ubuntu.com|https://ports.ubuntu.com|' /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential git python3 python3-dev python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv && \
    pip install --no-cache-dir --upgrade pip setuptools wheel
RUN git clone --depth 1 --branch "${IMMICH_VERSION}" \
      https://github.com/immich-app/immich.git /src/immich
RUN pip install --no-cache-dir \
      "immich-model @ git+https://github.com/immich-app/ml-models.git@${IMMICH_MODEL_COMMIT}" && \
    pip install --no-cache-dir "/src/immich/machine-learning" && \
    pip install --no-cache-dir "onnxruntime-gpu==${ONNXRUNTIME_GPU_VERSION}"
RUN python - <<'PY'
import onnxruntime as ort
providers = ort.get_available_providers()
print("Build-time ORT providers:", providers)
assert "CUDAExecutionProvider" in providers, providers
PY

FROM ${CUDA_IMAGE} AS runtime
ARG IMMICH_VERSION
ARG ONNXRUNTIME_GPU_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/usr/src \
    DEVICE=cuda \
    MACHINE_LEARNING_MODEL_ARENA=false \
    MACHINE_LEARNING_CACHE_FOLDER=/cache \
    HF_HOME=/cache/hf-cache \
    TRANSFORMERS_CACHE=/cache \
    CUDA_CACHE_PATH=/cache/jit/cuda \
    IMMICH_BUILD_IMAGE="${IMMICH_VERSION}-arm64-cuda13" \
    IMMICH_ARM64_CUDA_ORT_VERSION="${ONNXRUNTIME_GPU_VERSION}"
RUN sed -i 's|http://ports.ubuntu.com|https://ports.ubuntu.com|' /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && apt-get install -y --no-install-recommends \
      libgomp1 python3 tini && \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /src/immich/machine-learning/scripts/healthcheck.py /usr/src/healthcheck.py
WORKDIR /usr/src
RUN mkdir -p /cache && chmod 0755 /cache
EXPOSE 3003
ENTRYPOINT ["tini", "--"]
CMD ["python", "-m", "immich_ml"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python /usr/src/healthcheck.py
