#!/usr/bin/env bash
# Tear down the tutorial. Reverts the demo to its bundled DB, then removes Everest.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"
DEMO_NS="${DEMO_NS:-otel-demo}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> Reverting the demo to its bundled Postgres..."
helm upgrade otel-demo open-telemetry/opentelemetry-demo -n "${DEMO_NS}" \
  --reuse-values -f "${HERE}/manifests/otel-demo/values.yaml" || true

echo ">> Deleting the DatabaseCluster..."
kubectl -n "${DB_NS}" delete -f "${HERE}/manifests/everest/database-cluster.yaml" --ignore-not-found

echo ">> Uninstalling Everest..."
everestctl uninstall -y -f || true

# GOTCHA: `everestctl uninstall` leaves the Percona PG operator CRDs behind.
echo ">> Removing residual Percona PG CRDs..."
kubectl get crd -o name | grep pgv2.percona.com | xargs -r kubectl delete || true

echo ">> Teardown complete."
