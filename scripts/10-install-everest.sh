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
#   * The db-namespace chart runs an `everest-operators-installer` HOOK job that
#     installs the Percona operator(s) via OLM. This can take well over Helm's
#     DEFAULT 5m `--timeout`, so both installs pass `--timeout 15m`. Without it,
#     `helm install` reports the release `failed`/`pending-install` (and would need
#     `helm uninstall` before retry) even though the operator eventually comes up.
#     Do NOT Ctrl-C a slow install — let it finish.
set -euo pipefail

DB_NS="${DB_NS:-everest-dbs}"
CHART_VERSION="${CHART_VERSION:-1.16.2}"
HELM_TIMEOUT="${HELM_TIMEOUT:-15m}"

echo ">> (1/3) Installing Everest core via Helm (namespace: everest-system)..."
helm install everest openeverest/openeverest \
  --namespace everest-system --create-namespace \
  --version "${CHART_VERSION}" \
  --timeout "${HELM_TIMEOUT}"

echo ">> (2/3) Deploying DB namespace '${DB_NS}' with the PostgreSQL operator only..."
# The everest-db-namespace chart's operator toggles are TOP-LEVEL keys (verified
# against chart 1.16.2 `helm show values`): pxc = Percona XtraDB (MySQL),
# psmdb = Percona Server for MongoDB, postgresql (default true). Disabling pxc +
# psmdb leaves PostgreSQL as the only operator installed in this namespace.
#   NOTE: these are NOT nested under `dbNamespace.*` — a `--set dbNamespace.pxc=false`
#   is silently ignored and would install ALL THREE operators.
helm install everest openeverest/everest-db-namespace \
  --namespace "${DB_NS}" --create-namespace \
  --version "${CHART_VERSION}" \
  --timeout "${HELM_TIMEOUT}" \
  --set pxc=false \
  --set psmdb=false

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
