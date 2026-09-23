#!/usr/bin/env bash
# Install OpenEverest via its official Helm chart and add a PostgreSQL-only DB namespace.
#
# Source: https://openeverest.io/documentation/1.16.2/install/install_everest_helm_charts.html
#
# NOTES (v1.16.2 Helm install):
#   * The core chart installs into the FIXED `everest-system` namespace (not
#     customizable in 1.16.2).
#   * Database namespaces are a SEPARATE chart (`openeverest/everest-db-namespace`).
#     Installing the core chart alone does NOT create the DB namespace or the
#     PostgreSQL operator — deploy the db-namespace chart as its own release.
#   * Chart hooks are required; do not pass `--no-hooks`.
#   * Assumes the `openeverest` Helm repo was added by scripts/00-prereqs.sh.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"

echo ">> (1/3) Installing Everest core via Helm (namespace: everest-system)..."
helm install everest openeverest/openeverest \
  --namespace everest-system --create-namespace

echo ">> (2/3) Deploying DB namespace '${DB_NS}' with the PostgreSQL operator only..."
# pxc = Percona XtraDB (MySQL), psmdb = Percona Server for MongoDB — both disabled,
# leaving PostgreSQL as the only enabled operator in this namespace.
helm install everest openeverest/everest-db-namespace \
  --namespace "${DB_NS}" --create-namespace \
  --set dbNamespace.pxc=false \
  --set dbNamespace.psmdb=false

echo ">> (3/3) Initial admin credentials (rotate before any public/live use):"
echo ">>   username: admin"
echo ">>   password hash (per official docs):"
kubectl get secret everest-accounts -n everest-system \
  -o jsonpath='{.data.users\.yaml}' | base64 --decode | yq '.admin.passwordHash' || true
echo ">>   To set a known admin password, use the everestctl companion CLI (optional):"
echo ">>     everestctl accounts set-password --username admin"

echo
echo ">> Everest UI (optional): kubectl -n everest-system port-forward svc/everest 8080:8080"
echo ">> Available PG versions:"
kubectl -n "${DB_NS}" get databaseengine percona-postgresql-operator \
  -o jsonpath='{.status.availableVersions.engine}' 2>/dev/null | tr ',' '\n' || true
echo
echo ">> Everest install complete."
