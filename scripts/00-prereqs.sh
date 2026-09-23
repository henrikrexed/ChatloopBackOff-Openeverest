#!/usr/bin/env bash
# Prereqs for the OpenEverest × OTel Demo tutorial.
# Installs everestctl and adds the OpenTelemetry Helm repo. Idempotent.
#
# Assumes: a running Kubernetes cluster, kubectl + helm on PATH, a default
# StorageClass backed by local disk (network FS causes PG fsync stalls), and
# a LoadBalancer implementation (MetalLB, cloud LB, etc.).
set -euo pipefail

EVERESTCTL_VERSION="${EVERESTCTL_VERSION:-v1.16.2}"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"; case "$ARCH" in x86_64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; esac

echo ">> Checking cluster access..."
kubectl version -o json >/dev/null

echo ">> Installing everestctl ${EVERESTCTL_VERSION} (${OS}/${ARCH})..."
if ! command -v everestctl >/dev/null 2>&1; then
  curl -fsSL -o /tmp/everestctl \
    "https://github.com/openeverest/openeverest/releases/download/${EVERESTCTL_VERSION}/everestctl-${OS}-${ARCH}"
  chmod +x /tmp/everestctl
  sudo mv /tmp/everestctl /usr/local/bin/everestctl
fi
everestctl version || true

echo ">> Adding the OpenTelemetry Helm repo..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry

echo ">> Default StorageClass:"
kubectl get storageclass
echo ">> Prereqs OK."
