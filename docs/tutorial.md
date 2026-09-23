# Tutorial: Run the OpenTelemetry Demo on an OpenEverest-provisioned PostgreSQL

> **Status:** technical steps validated end-to-end against a real cluster on
> 2026-09-23 (everestctl v1.16.2 · Percona PG operator v3.0.0 · PostgreSQL 17.10 ·
> otel-demo chart 0.40.10 / app 2.2.0). Prose/narrative polish is owned by the
> Content Writer — see the section markers below.

## What you'll build

The OpenTelemetry Demo ships a bundled PostgreSQL used by its **product-catalog**
(Go) and **accounting** (.NET) services. In this tutorial you:

1. Install **OpenEverest** — a Kubernetes-native database-as-a-service operator.
2. Provision a **PostgreSQL 17.10** instance through Everest (with a PgBouncer proxy
   exposed via a LoadBalancer, and `pg_stat_statements` enabled).
3. Seed it with the demo's schema/data.
4. **Swap** the demo's product-catalog + accounting off the bundled Postgres onto
   the Everest-managed database — with zero code changes, just connection strings.
5. Observe the result with OpenTelemetry (Jaeger/Grafana) and, optionally, Dynatrace.

The payoff: the storefront keeps serving products, but the database is now a
declaratively-managed, observable Everest resource — and its query stats light up
through `pg_stat_statements`.

<!-- Content Writer: expand "What you'll build" into a narrative intro + a diagram callout. -->

## Prerequisites

See [prerequisites.md](./prerequisites.md). In short: a Kubernetes cluster with a
**local-disk** default StorageClass (network filesystems cause PostgreSQL fsync
stalls), a **LoadBalancer** implementation, and `kubectl` + `helm` on PATH.

```sh
./scripts/00-prereqs.sh      # installs everestctl, adds the OTel Helm repo
```

## Step 1 — Deploy the OTel Demo (baseline)

Install the demo with its bundled Postgres so you have a working baseline to swap
away from later.

```sh
helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
  -n otel-demo --create-namespace --version 0.40.10 \
  -f manifests/otel-demo/values.yaml

kubectl -n otel-demo get svc frontend-proxy   # note the LoadBalancer EXTERNAL-IP
# open http://<EXTERNAL-IP>:8080 → products visible, checkout works
```

## Step 2 — Install OpenEverest

> ⚠️ **Gotcha:** `everestctl install --namespaces <ns>` does **not** create the DB
> namespace or the PostgreSQL operator on v1.16.2. Adding the namespace is a
> separate command — the script below does both.

```sh
./scripts/10-install-everest.sh
```

This runs:

```sh
everestctl install --skip-wizard
everestctl namespaces add everest-dbs \
  --operator.postgresql=true --operator.mysql=false --operator.mongodb=false --skip-wizard
everestctl accounts initial-admin-password        # rotate before any public use
```

Everest does **not** require cert-manager. Optionally open the UI:

```sh
kubectl -n everest-system port-forward svc/everest 8080:8080   # http://127.0.0.1:8080
```

## Step 3 — Provision PostgreSQL

```sh
./scripts/20-provision-postgres.sh
```

This applies [`manifests/everest/database-cluster.yaml`](../manifests/everest/database-cluster.yaml)
and waits for `state: ready` (~90s), then prints the PgBouncer LoadBalancer IP.

Key manifest choices, and *why*:

| Field | Value | Why |
|---|---|---|
| `engine.version` | `17.10` | 17.4 is **not** offered by operator v3.0.0 (only 17.7/17.9/17.10). |
| `storage.class` | `local-path` | Explicit local disk — avoids the network-FS fsync gotcha. |
| `proxy.expose.type` | `LoadBalancer` | `external` is deprecated in v1.16.2. |
| `config` | `pg_stat_statements` | Preloads the library for the DB-observability angle. |

## Step 4 — Seed the database

Everest hands you an **empty** database, so the storefront would be blank and
accounting inserts would fail. Seed it with the demo's schema:

```sh
./scripts/30-seed-database.sh
```

The seed Job ([`seed-job.yaml`](../manifests/everest/seed-job.yaml)):

- Builds its connection from the **individual** fields of the `everest-secrets-demo-pg`
  Secret (`user` + `password`). That Secret has **no `uri` key** — a common trap.
- Connects directly to `demo-pg-primary.everest-dbs.svc` (not PgBouncer), because
  `CREATE DATABASE` can't run in a pooled session.
- Creates database `otel`, loads the pinned
  [otel-demo 2.2.0 `init.sql`](https://raw.githubusercontent.com/open-telemetry/opentelemetry-demo/2.2.0/src/postgresql/init.sql)
  (which itself creates user `otelu` and the accounting/reviews/catalog schemas),
  and runs `CREATE EXTENSION IF NOT EXISTS pg_stat_statements`.

Expected: `catalog.products = 10`, `reviews.productreviews = 50`.

## Step 5 — Swap the demo onto Everest

```sh
EVEREST_LB_IP=<from step 3> ./scripts/40-swap-demo.sh
```

This applies [`otel-demo-everest-values.yaml`](../manifests/everest/otel-demo-everest-values.yaml)
as a `helm upgrade --reuse-values` overlay, which:

- disables the bundled DB via `components.postgresql.enabled: false` (on this chart
  the component is named **`postgresql`**, *not* `astronomy-db` — disabling the
  latter is a silent no-op), and
- repoints product-catalog and accounting at `otelu:otelp@<EVEREST_LB_IP>:5432/otel`
  with `sslmode=require` (the operator serves a self-signed certificate).

Verify the storefront still serves products — now from Everest:

```sh
kubectl -n otel-demo rollout status deploy/product-catalog deploy/accounting
kubectl -n otel-demo get pods | grep -E 'product-catalog|accounting|postgresql'
# open http://<frontend EXTERNAL-IP>:8080 → products still visible
```

## Step 6 — Observe

- **Jaeger / Grafana** (bundled): traces from product-catalog and accounting now
  show calls to the Everest PostgreSQL; `pg_stat_statements` surfaces query stats.
- **Dynatrace** (optional): install the operator, create the token Secret, and
  apply a DynaKube — see [`dynakube.yaml.example`](../manifests/dynatrace/dynakube.yaml.example).

<!-- Content Writer: add screenshots of Jaeger service map + the Everest UI DB view. -->

## Teardown

```sh
./scripts/90-teardown.sh
```

Reverts the demo to its bundled DB, deletes the DatabaseCluster, uninstalls
Everest, and removes the residual `*.pgv2.percona.com` CRDs that `everestctl
uninstall` leaves behind.

## Troubleshooting / gotchas (all hit during the real dry-run)

1. `everestctl install --namespaces` doesn't create the DB namespace/operator → add it separately.
2. PostgreSQL 17.4 unavailable on operator v3.0.0 → pin 17.10.
3. `expose.type: external` is deprecated → use `LoadBalancer`.
4. The pguser Secret has **no `uri` key** → build the conn string from `user`/`password`.
5. `pg_stat_statements` preloads but isn't installed → `CREATE EXTENSION` in the seed.
6. The demo uses db `otel` / user `otelu`, **not** `astronomy_db` / `astronomy_user`.
7. The bundled DB component is `postgresql`, **not** `astronomy-db`.
8. `everestctl uninstall` leaves Percona CRDs → delete them manually (teardown script does this).
