#!/usr/bin/env bash
# Seed the Everest PostgreSQL with the OTel Demo schema/data via a one-shot Job.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> Launching seed Job..."
kubectl -n "${DB_NS}" delete job otel-demo-pg-seed --ignore-not-found
kubectl apply -f "${HERE}/manifests/everest/seed-job.yaml"

echo ">> Waiting for seed to complete..."
kubectl -n "${DB_NS}" wait --for=condition=complete job/otel-demo-pg-seed --timeout=5m &
WAIT_PID=$!
kubectl -n "${DB_NS}" wait --for=condition=failed job/otel-demo-pg-seed --timeout=5m \
  && { echo "!! Seed FAILED — logs:"; kubectl -n "${DB_NS}" logs job/otel-demo-pg-seed; exit 1; } &
FAIL_PID=$!
wait -n "$WAIT_PID" "$FAIL_PID" || true

kubectl -n "${DB_NS}" logs job/otel-demo-pg-seed --tail=20
echo ">> Seed done."
