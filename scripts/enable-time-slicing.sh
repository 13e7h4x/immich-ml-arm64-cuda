#!/usr/bin/env bash
set -euo pipefail

REPLICAS=${1:-4}
NODE=${2:-${NODE:-}}
if ! [[ "$REPLICAS" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: $0 [positive-replica-count] [gpu-node-name]" >&2
  exit 2
fi

kubectl cluster-info >/dev/null || {
  echo "kubectl cannot reach the cluster" >&2
  exit 1
}
kubectl auth can-i patch clusterpolicies.nvidia.com >/dev/null | grep -qx yes || {
  echo "current Kubernetes identity cannot patch NVIDIA ClusterPolicy" >&2
  exit 1
}

if [[ -z "$NODE" ]]; then
  mapfile -t gpu_nodes < <(kubectl get nodes -l nvidia.com/gpu.present=true -o name | sed 's|node/||')
  if [[ ${#gpu_nodes[@]} -ne 1 ]]; then
    echo "found ${#gpu_nodes[@]} GPU nodes; pass the target node as argument 2" >&2
    exit 2
  fi
  NODE=${gpu_nodes[0]}
fi
kubectl get node "$NODE" >/dev/null

manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
sed "s/replicas: 4/replicas: ${REPLICAS}/" \
  "$(dirname "$0")/../k8s/time-slicing-config.yaml" > "$manifest"
kubectl apply -f "$manifest"
kubectl patch clusterpolicy cluster-policy --type merge -p \
  '{"spec":{"devicePlugin":{"config":{"name":"nvidia-device-plugin-time-slicing","default":"any"}}}}'
kubectl -n nvidia-gpu-operator rollout status daemonset/nvidia-device-plugin-daemonset --timeout=3m

current=""
for _ in $(seq 1 60); do
  current=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')
  [[ "$current" == "$REPLICAS" ]] && break
  sleep 2
done
[[ "$current" == "$REPLICAS" ]] || {
  echo "expected $REPLICAS allocatable GPU shares on $NODE, found ${current:-none}" >&2
  exit 1
}
echo "GPU Operator time-slicing enabled on $NODE: $current shares"
