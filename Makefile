IMAGE ?= immich-ml-arm64-cuda:test

.PHONY: test build smoke operator-smoke

test:
	python3 -m unittest discover -s tests -v
	bash -n scripts/*.sh

build: test
	docker build --progress=plain -t $(IMAGE) .

smoke:
	./scripts/smoke-test.sh $(IMAGE)

operator-smoke:
	kubectl delete pod immich-ml-arm64-cuda-operator-smoke --ignore-not-found --wait=true
	kubectl apply -f k8s/smoke-pod.yaml
	kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/immich-ml-arm64-cuda-operator-smoke --timeout=10m
	kubectl logs immich-ml-arm64-cuda-operator-smoke
