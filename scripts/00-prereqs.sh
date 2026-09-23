#!/usr/bin/env bash
# Prereqs for the OpenEverest × OTel Demo tutorial.
# Adds the OpenEverest + OpenTelemetry Helm repos (OpenEverest is installed via its
# Helm chart in scripts/10-install-everest.sh). Idempotent.
#
# Assumes: a running Kubernetes cluster, kubectl + helm + yq on PATH, a default
# StorageClass backed by local disk (network FS causes PG fsync stalls), and
# a LoadBalancer implementation (MetalLB, cloud LB, etc.).
#
# NOTE: `everestctl` is NO LONGER required to install Everest (Helm handles that).
# It remains a useful OPTIONAL companion CLI for account management, e.g.
# `everestctl accounts set-password`. Install it from
# https://github.com/openeverest/openeverest/releases if you want it.
set -euo pipefail

echo ">> Checking cluster access..."
kubectl version -o json >/dev/null

echo ">> Checking required tools (kubectl, helm, yq)..."
for t in kubectl helm yq; do
  command -v "$t" >/dev/null 2>&1 || { echo "!! missing required tool: $t" >&2; exit 1; }
done

echo ">> Adding the OpenEverest Helm repo..."
helm repo add openeverest https://openeverest.github.io/helm-charts/ >/dev/null 2>&1 || true

echo ">> Adding the OpenTelemetry Helm repo..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true

echo ">> Updating Helm repos..."
helm repo update openeverest open-telemetry

echo ">> Default StorageClass:"
kubectl get storageclass
echo ">> Prereqs OK."
