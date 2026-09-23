#!/usr/bin/env bash
# Tear down the tutorial. Reverts the demo to its bundled DB, then removes Everest.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"
DEMO_NS="${DEMO_NS:-otel-demo}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> Reverting the demo to its bundled Postgres..."
helm upgrade otel-demo open-telemetry/opentelemetry-demo -n "${DEMO_NS}" \
  --reuse-values -f "${HERE}/manifests/otel-demo/values.yaml" || true

echo ">> Deleting the DatabaseCluster (blocks until the operator finalizes it)..."
# ORDER MATTERS: fully delete the DatabaseCluster *before* uninstalling the operator.
# `kubectl delete` waits for finalizers by default, but the operator must still be
# running to process them — uninstall it first and the underlying PostgresCluster's
# `postgres-operator.crunchydata.com/finalizer` hangs, wedging namespace deletion.
kubectl -n "${DB_NS}" delete -f "${HERE}/manifests/everest/database-cluster.yaml" \
  --ignore-not-found --timeout=5m || true

echo ">> Uninstalling Everest via Helm (installed via Helm → uninstall via Helm)..."
# Uninstall the db-namespace release first (operator lives here), then the core release.
helm uninstall everest -n "${DB_NS}" || true
helm uninstall everest -n everest-system || true

# SAFETY NET: if any PostgresCluster still holds the crunchydata finalizer (e.g. the
# operator was removed before it finalized), clear it so the namespace can terminate.
for pc in $(kubectl -n "${DB_NS}" get postgresclusters.upstream.pgv2.percona.com \
    -o name 2>/dev/null); do
  kubectl -n "${DB_NS}" patch "${pc}" --type=merge \
    -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
done
kubectl delete namespace "${DB_NS}" everest-system everest-olm everest-monitoring everest \
  --ignore-not-found || true

# GOTCHA: Percona/Everest CRDs are cluster-scoped and survive `helm uninstall`. The
# db-namespace chart installs CRDs for ALL engines (pg + psmdb + pxc) plus the everest
# CRDs, so match every relevant group — not just `pgv2.percona.com`.
echo ">> Removing residual Everest/Percona CRDs (cluster-scoped)..."
kubectl get crd -o name 2>/dev/null \
  | grep -E '\.(everest|pgv2|psmdb|pxc|enginefeatures)\.percona\.com$' \
  | xargs -r kubectl delete --ignore-not-found || true

echo ">> Teardown complete."
