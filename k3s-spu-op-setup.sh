#!/usr/bin/env bash
# GPU-enabled Kubernetes on a single node with 4x H100:
#   - k3s (with containerd)
#   - NVIDIA GPU Operator (driver + device plugin)
#
# Run as root or with sudo. Tested on Ubuntu 22.04/24.04.

set -e

install_helm() {
  if command -v helm &>/dev/null; then
    echo "==> Helm already installed: $(helm version --short)"
    return
  fi
  echo "==> Installing Helm..."
  HELM_VER="${HELM_VERSION:-v3.16.4}"
  HELM_ARCH="linux-amd64"
  curl -sSL "https://get.helm.sh/helm-${HELM_VER}-${HELM_ARCH}.tar.gz" | tar xz -C /tmp
  mv /tmp/linux-amd64/helm /usr/local/bin/helm
  chmod +x /usr/local/bin/helm
  rm -rf /tmp/linux-amd64
  echo "==> Helm installed: $(helm version --short)"
}

install_helm

echo "==> Installing k3s..."
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
chmod 600 "$KUBECONFIG"

echo "==> Waiting for k3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q Ready; do
  sleep 5
done

echo "==> Creating gpu-operator namespace and pod-security label..."
kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -
kubectl label --overwrite namespace gpu-operator \
  pod-security.kubernetes.io/enforce=privileged

echo "==> Adding NVIDIA Helm repo and installing GPU Operator..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade --install gpu-operator -n gpu-operator --create-namespace \
  nvidia/gpu-operator \
  --version v25.3.4

echo "==> GPU Operator installed. Wait for all pods to be Ready:"
echo "    kubectl get pods -n gpu-operator -w"
echo ""
echo "Then verify GPUs:"
echo "    kubectl get nodes -o jsonpath='{.items[*].status.capacity}' | jq ."
echo ""
echo "KUBECONFIG: $KUBECONFIG"
