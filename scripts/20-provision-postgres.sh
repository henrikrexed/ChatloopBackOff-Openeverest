#!/usr/bin/env bash
# Provision the PostgreSQL DatabaseCluster and wait for it to become ready.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> Applying DatabaseCluster demo-pg..."
kubectl apply -f "${HERE}/manifests/everest/database-cluster.yaml"

echo ">> Waiting for demo-pg to become ready (typ. ~90s)..."
kubectl -n "${DB_NS}" wait --for=jsonpath='{.status.status}'=ready \
  databasecluster/demo-pg --timeout=10m

echo ">> PgBouncer LoadBalancer address:"
LB="$(kubectl -n "${DB_NS}" get svc -l postgres-operator.crunchydata.com/role=pgbouncer \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo "   EVEREST_LB_IP = ${LB}"
echo "   (use this in manifests/everest/otel-demo-everest-values.yaml)"
