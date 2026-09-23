#!/usr/bin/env bash
# Swap the OTel Demo off its bundled Postgres onto the Everest-provisioned DB.
#
# Usage: EVEREST_LB_IP=10.0.0.83 ./scripts/40-swap-demo.sh
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"
DEMO_NS="${DEMO_NS:-otel-demo}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${EVEREST_LB_IP:-}" ]]; then
  EVEREST_LB_IP="$(kubectl -n "${DB_NS}" get svc -l postgres-operator.crunchydata.com/role=pgbouncer \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
fi
echo ">> Using EVEREST_LB_IP=${EVEREST_LB_IP}"

# Render the overlay with the live LB IP substituted in.
OVERLAY="$(mktemp)"
sed "s/<EVEREST_LB_IP>/${EVEREST_LB_IP}/g" \
  "${HERE}/manifests/everest/otel-demo-everest-values.yaml" > "${OVERLAY}"

echo ">> helm upgrade (reuse existing values + apply swap overlay)..."
helm upgrade otel-demo open-telemetry/opentelemetry-demo -n "${DEMO_NS}" \
  --reuse-values -f "${OVERLAY}"
rm -f "${OVERLAY}"

echo ">> Rolling out product-catalog + accounting..."
kubectl -n "${DEMO_NS}" rollout status deploy/product-catalog
kubectl -n "${DEMO_NS}" rollout status deploy/accounting

echo ">> Swap complete. The bundled 'postgresql' Deployment should now be gone:"
kubectl -n "${DEMO_NS}" get deploy | grep -E 'postgresql|product-catalog|accounting' || true
