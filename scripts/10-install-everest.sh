#!/usr/bin/env bash
# Install OpenEverest and add a PostgreSQL-only database namespace.
#
# GOTCHA (v1.16.2): `everestctl install --namespaces <ns>` does NOT create the DB
# namespace or the PostgreSQL operator. You must add it as a SEPARATE step, or the
# DatabaseCluster apply fails because everest-dbs / the Percona PG operator do not exist.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"

echo ">> (1/3) Installing Everest core (no DB namespace yet)..."
everestctl install --skip-wizard

echo ">> (2/3) Adding DB namespace '${DB_NS}' with the PostgreSQL operator only..."
everestctl namespaces add "${DB_NS}" \
  --operator.postgresql=true --operator.mysql=false --operator.mongodb=false \
  --skip-wizard

echo ">> (3/3) Admin password (rotate before any public/live use):"
everestctl accounts initial-admin-password
echo ">>   rotate with: everestctl accounts set-password --username admin"

echo
echo ">> Everest UI (optional): kubectl -n everest-system port-forward svc/everest 8080:8080"
echo ">> Available PG versions:"
kubectl -n "${DB_NS}" get databaseengine percona-postgresql-operator \
  -o jsonpath='{.status.availableVersions.engine}' 2>/dev/null | tr ',' '\n' || true
echo
echo ">> Everest install complete."
