#!/usr/bin/env bash
set -euo pipefail

IMAGE=${1:-immich-ml-arm64-cuda:test}
CACHE=${IMMICH_ML_TEST_CACHE:-immich-ml-arm64-cuda-test-cache}
NAME=${IMMICH_ML_TEST_NAME:-immich-ml-arm64-cuda-smoke}
PORT=${IMMICH_ML_TEST_PORT:-3004}

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$CACHE" >/dev/null
docker run --rm -i --runtime=nvidia --entrypoint python "$IMAGE" - <<'PY'
import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper

providers = ort.get_available_providers()
print("ORT providers:", providers)
assert "CUDAExecutionProvider" in providers, providers

# Execute a real matrix multiplication through CUDA, not just provider discovery.
x = helper.make_tensor_value_info("x", TensorProto.FLOAT, [2, 2])
y = helper.make_tensor_value_info("y", TensorProto.FLOAT, [2, 2])
z = helper.make_tensor_value_info("z", TensorProto.FLOAT, [2, 2])
node = helper.make_node("MatMul", ["x", "y"], ["z"])
graph = helper.make_graph([node], "cuda-smoke", [x, y], [z])
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
model.ir_version = 9
session = ort.InferenceSession(
    model.SerializeToString(),
    providers=["CUDAExecutionProvider"],
)
assert session.get_providers()[0] == "CUDAExecutionProvider", session.get_providers()
a = np.array([[1, 2], [3, 4]], dtype=np.float32)
b = np.array([[5, 6], [7, 8]], dtype=np.float32)
result = session.run(None, {"x": a, "y": b})[0]
np.testing.assert_allclose(result, a @ b)
print("CUDA inference result:", result.tolist())
PY

docker run -d --name "$NAME" --runtime=nvidia \
  -e MACHINE_LEARNING_CACHE_FOLDER=/cache \
  -p "127.0.0.1:${PORT}:3003" \
  -v "$CACHE:/cache" "$IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null; then break; fi
  sleep 2
done
curl -fsS "http://127.0.0.1:${PORT}/ping"
docker exec "$NAME" nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
docker exec -i "$NAME" python - <<'PY'
import onnxruntime as ort
providers = ort.get_available_providers()
print("Runtime ORT providers:", providers)
assert "CUDAExecutionProvider" in providers, providers
PY

echo "CUDA provider and Immich ML health checks passed"
