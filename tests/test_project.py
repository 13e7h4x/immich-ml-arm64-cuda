#!/usr/bin/env python3
"""Static contract tests for the publishable image project."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProjectContractTests(unittest.TestCase):
    def test_dockerfile_uses_arm64_capable_cuda_runtime(self) -> None:
        text = (ROOT / "Dockerfile").read_text()
        self.assertIn("nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04", text)
        self.assertIn("ARG ONNXRUNTIME_GPU_VERSION=1.31.0", text)
        self.assertIn("ARG IMMICH_MODEL_COMMIT=", text)
        self.assertIn('ml-models.git@${IMMICH_MODEL_COMMIT}', text)
        self.assertIn('onnxruntime-gpu==${ONNXRUNTIME_GPU_VERSION}', text)
        self.assertIn("CMD [\"python\", \"-m\", \"immich_ml\"]", text)
        self.assertIn("chmod 0755 /cache", text)
        self.assertNotIn("chmod 0777", text)

    def test_kubernetes_manifest_uses_gpu_operator(self) -> None:
        text = (ROOT / "k8s" / "deployment.yaml").read_text()
        self.assertIn("runtimeClassName: nvidia", text)
        self.assertIn("nvidia.com/gpu: 1", text)
        self.assertIn("imagePullPolicy: Always", text)
        self.assertNotIn("/dev/nvidia", text)
        self.assertNotIn("privileged: true", text)

    def test_smoke_test_requires_cuda_provider(self) -> None:
        text = (ROOT / "scripts" / "smoke-test.sh").read_text()
        self.assertIn("CUDAExecutionProvider", text)
        self.assertIn("nvidia-smi", text)
        self.assertIn("MatMul", text)
        self.assertIn("np.testing.assert_allclose", text)

    def test_time_slicing_profile_is_gpu_operator_compatible(self) -> None:
        text = (ROOT / "k8s" / "time-slicing-config.yaml").read_text()
        self.assertIn("namespace: nvidia-gpu-operator", text)
        self.assertIn("  any: |", text)
        self.assertIn("name: nvidia.com/gpu", text)
        self.assertIn("replicas: 4", text)


if __name__ == "__main__":
    unittest.main()
