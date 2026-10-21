# Immich GPU Acceleration for NVIDIA DGX Spark (ARM64 CUDA)

A reproducible GPU-accelerated Immich machine-learning container for NVIDIA DGX Spark GB10, Linux ARM64, CUDA 13 and NVIDIA GPU Operator.

Immich publishes a CUDA machine-learning image for `linux/amd64`, but not for DGX Spark's `linux/arm64` architecture. This project fills that gap using the official ARM64 `onnxruntime-gpu` wheel and includes verified Docker and Kubernetes deployment paths.

## Verified platform

- NVIDIA DGX Spark GB10 (`linux/arm64`, compute capability 12.1)
- NVIDIA driver 580.178.04
- CUDA 13.0.2 / cuDNN 9.14 runtime
- Immich ML v3.3.5
- Python 3.12
- ONNX Runtime GPU 1.31.0
- NVIDIA GPU Operator v26.3.0

The validation run completed a real CLIP text inference through Immich ML and produced a 512-dimensional embedding. The process appeared alongside an existing vLLM GPU process, confirming concurrent use of the unified GPU.

## What this project does

- Builds Immich's upstream machine-learning service from a pinned release.
- Installs the pinned upstream `immich-model` source revision.
- Installs the official PyPI ARM64 `onnxruntime-gpu` wheel.
- Uses an ARM64-capable NVIDIA CUDA/cuDNN runtime.
- Fails the build unless `CUDAExecutionProvider` is present.
- Provides an actual CUDA matrix-inference smoke test.
- Provides GPU Operator manifests and an optional four-way time-slicing configuration.

It does **not** modify Immich's database or media library.

## Build

```bash
docker build -t immich-ml-arm64-cuda:v3.3.5 .
```

Override pinned versions when testing a newer release:

```bash
docker build \
  --build-arg IMMICH_VERSION=v3.3.5 \
  --build-arg ONNXRUNTIME_GPU_VERSION=1.31.0 \
  -t immich-ml-arm64-cuda:v3.3.5 .
```

## Docker smoke test

```bash
./scripts/smoke-test.sh immich-ml-arm64-cuda:v3.3.5
```

The smoke service binds only to `127.0.0.1:3004` by default, leaving a production service on port 3003 untouched. Override it with `IMMICH_ML_TEST_PORT=<port>`.

The test requires all of the following:

1. `CUDAExecutionProvider` is available.
2. A real ONNX matrix multiplication produces the expected result on the CUDA session.
3. The Immich ML `/ping` endpoint returns `pong`.
4. The container can query the assigned NVIDIA GPU.

## NVIDIA GPU Operator

The workload requests the GPU through the NVIDIA device plugin:

```yaml
runtimeClassName: nvidia
resources:
  limits:
    nvidia.com/gpu: 1
```

No `/dev/nvidia*` mounts and no privileged container are required.

### Optional time-slicing

`k8s/time-slicing-config.yaml` exposes four schedulable shares of the physical GPU. Apply it and point the ClusterPolicy at the `any` profile:

```bash
./scripts/enable-time-slicing.sh 4 <gpu-node-name>
```

The script validates cluster access and permissions, applies `k8s/time-slicing-config.yaml`, points the NVIDIA ClusterPolicy at the `any` profile, and verifies the selected node advertises four shares. The equivalent manual commands are:

```bash
kubectl apply -f k8s/time-slicing-config.yaml
kubectl patch clusterpolicy cluster-policy --type merge -p \
  '{"spec":{"devicePlugin":{"config":{"name":"nvidia-device-plugin-time-slicing","default":"any"}}}}'
```

Verify:

```bash
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}{"\n"}'
```

Time-slicing provides scheduling shares, not memory isolation or quality-of-service guarantees. Every process can still consume available unified GPU memory. Set sensible pod memory limits and avoid excessive ML job concurrency when another large model server is active.

### Operator smoke test

```bash
kubectl delete pod immich-ml-arm64-cuda-operator-smoke --ignore-not-found
kubectl apply -f k8s/smoke-pod.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/immich-ml-arm64-cuda-operator-smoke --timeout=10m
kubectl logs immich-ml-arm64-cuda-operator-smoke
```

Expected output contains:

```text
GPU_OPERATOR_CUDA_INFERENCE_OK [[19.0, 22.0], [43.0, 50.0]]
```

## Deploy

1. Build and push the image to a registry visible to your cluster.
2. Replace `ghcr.io/OWNER/...` in `k8s/deployment.yaml`.
3. Create the `immich-ml-cache` PVC or change the volume definition.
4. Apply the deployment and service.
5. Set Immich's machine-learning URL to `http://immich-ml-arm64-cuda:3003` when Immich runs in the same cluster.

For a Docker-hosted Immich server and a Kubernetes-hosted ML service, expose the service through a controlled NodePort or a host-networked deployment. Do not expose port 3003 to untrusted networks.

## Compatibility warning

This project intentionally moves beyond Immich v3.3.5's CUDA dependency pin. Upstream pins ONNX Runtime GPU below 1.28 for its CUDA 12.2 image, while ARM64 GPU wheels are available from PyPI beginning with newer releases intended for CUDA 13. Validate every Immich and ONNX Runtime upgrade independently.

## Evidence from the DGX Spark validation

```text
ORT providers: ['CUDAExecutionProvider', 'CPUExecutionProvider']
CUDA inference result: [[19.0, 22.0], [43.0, 50.0]]
Immich CLIP embedding dimensions: 512
GPU processes during inference:
- vLLM EngineCore: 84391 MiB
- Immich ML Python: 452 MiB
```

## Development

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh
```

## License

GNU Affero General Public License v3.0, matching Immich. Immich is a separate project and trademark; this repository is not an official Immich image.
