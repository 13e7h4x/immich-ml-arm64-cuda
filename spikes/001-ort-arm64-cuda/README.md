# Spike 001: ARM64 ONNX Runtime CUDA on GB10

## Question

Can an official Linux ARM64 `onnxruntime-gpu` wheel load CUDA 13 on a DGX Spark GB10 and execute both a synthetic ONNX graph and a real Immich CLIP model while another GPU service remains active?

## Approach

- Base image: `nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04`
- Python: Ubuntu Python 3.12
- ONNX Runtime GPU: 1.31.0 from PyPI (`manylinux_2_34_aarch64`)
- Immich ML: v3.3.5
- Synthetic test: 2x2 ONNX `MatMul`
- Real test: Immich `/predict` textual CLIP request using `ViT-B-32__openai`
- Shared workload: vLLM remained active on the GB10 throughout

## Results

```text
Build-time ORT providers: ['CUDAExecutionProvider', 'CPUExecutionProvider']
CUDA inference result: [[19.0, 22.0], [43.0, 50.0]]
Immich CLIP embedding dimensions: 512
Immich ML GPU memory during inference: 452 MiB
vLLM GPU memory during inference: 84391 MiB
```

The Immich logs selected `CUDAExecutionProvider` for the downloaded textual model. The host simultaneously reported both vLLM and Immich ML as GPU compute processes.

The GPU Operator was configured for four time-sliced `nvidia.com/gpu` resources. A Kubernetes smoke pod requested one share and completed the same CUDA matrix inference successfully while vLLM remained active outside Kubernetes.

## Verdict

**VALIDATED** for DGX Spark GB10 with driver 580 and CUDA 13.

## Remaining publication/integration work

- Push the image to a registry visible to containerd.
- Run the exact built image as the GPU Operator workload.
- Point production Immich at the new service only after readiness and CLIP inference pass.
