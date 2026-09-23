# Tutorial: Run the OpenTelemetry Demo on an OpenEverest-provisioned PostgreSQL

> **Status:** provision → seed → swap → observe were validated end-to-end against a
> real cluster on 2026-09-23 (OpenEverest v1.16.2 · Percona PG operator v3.0.0 ·
> PostgreSQL 17.10 · otel-demo chart 0.40.10 / app 2.2.0). Do not change any command or
> version without re-validating against a real cluster.
>
> **Install/teardown (Step 2 + Teardown)** now follow the official OpenEverest **Helm
> chart** procedure ([1.16.2 docs](https://openeverest.io/documentation/1.16.2/install/install_everest_helm_charts.html)),
> replacing the earlier `everestctl` path. These two steps are pending a live
> re-validation on the cluster; everything downstream is unchanged.

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

Think of it as a controlled organ transplant. The OTel Demo arrives with its own
bundled PostgreSQL — fine for a laptop, but unmanaged, unbacked-up, and invisible past
the pod boundary. Rather than redeploy the whole demo against a different database, you
provision a *better* database next to it and then re-point just the two services that
actually use it — **product-catalog** (Go) and **accounting** (.NET) — at the new
endpoint. Nothing about the application's image, code, or business logic changes; the
only thing that moves is a connection string. That's the whole trick, and it's why this
pattern generalizes far beyond a demo: if you can change where an app connects, you can
migrate its state without touching the app.

The six steps below build up to exactly this. You start from a working baseline (the
demo on its bundled DB), stand up the Everest control plane, provision and seed a real
PostgreSQL cluster, perform the swap, and finally observe the result — first confirming
the storefront still works, then watching the telemetry prove *where* its queries now
land.

![Observability architecture — Everest provisions the PostgreSQL cluster; the OTel Demo's product-catalog and accounting services consume it through PgBouncer; the OTel Operator + Collector and the Dynatrace Operator carry the telemetry out to Jaeger/Grafana and Dynatrace.](assets/observability-architecture.png)

> **Diagram:** the end state. Everest (top) owns the `demo-pg` PostgreSQL cluster in
> `everest-dbs`; the OTel Demo (bottom) reaches it through the PgBouncer LoadBalancer;
> and everything is instrumented, so the migration is legible in both Jaeger/Grafana and
> Dynatrace. Keep this picture in mind as you work through the steps — each one lights up
> one more edge of it. A step-by-step version of the flow is in
> [`assets/demo-flow.png`](assets/demo-flow.png).

## Prerequisites

See [prerequisites.md](./prerequisites.md). In short: a Kubernetes cluster with a
**local-disk** default StorageClass (network filesystems cause PostgreSQL fsync
stalls), a **LoadBalancer** implementation, and `kubectl` + `helm` on PATH.

```sh
./scripts/00-prereqs.sh      # adds the OpenEverest + OTel Helm repos
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

## Step 2 — Install OpenEverest (Helm)

Install OpenEverest from its official Helm chart, following the
[1.16.2 install guide](https://openeverest.io/documentation/1.16.2/install/install_everest_helm_charts.html).

> ⚠️ **Gotcha:** the core chart only installs the Everest control plane into the fixed
> `everest-system` namespace — it does **not** create the DB namespace or the PostgreSQL
> operator. Database namespaces are a **separate** chart (`openeverest/everest-db-namespace`).
> The script below installs both releases.

```sh
./scripts/10-install-everest.sh
```

This runs:

```sh
# 1) Everest control plane (fixed namespace `everest-system` on 1.16.2)
helm install everest openeverest/openeverest \
  --namespace everest-system --create-namespace

# 2) A PostgreSQL-only database namespace (pxc=MySQL, psmdb=MongoDB → both disabled)
helm install everest openeverest/everest-db-namespace \
  --namespace everest-dbs --create-namespace \
  --set dbNamespace.pxc=false \
  --set dbNamespace.psmdb=false

# 3) Initial admin password hash (rotate before any public use):
kubectl get secret everest-accounts -n everest-system \
  -o jsonpath='{.data.users\.yaml}' | base64 --decode | yq '.admin.passwordHash'
#    Set a known admin password with the optional everestctl companion CLI:
#      everestctl accounts set-password --username admin
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

This is the payoff. Up to now you've *asserted* that the demo moved onto Everest; now
you'll *see* it. Because product-catalog and accounting are OpenTelemetry-instrumented,
their database calls carry spans — so the migration shows up as a change in where those
spans point, not as a leap of faith.

- **Jaeger / Grafana** (bundled): open a trace that touches product-catalog or
  accounting and follow it to the PostgreSQL span. Before the swap it resolved to the
  in-cluster `postgresql` service; after the swap it resolves to the Everest PgBouncer
  endpoint. In parallel, `pg_stat_statements` on the managed cluster now accumulates
  per-query stats — the same statements you see in the traces, counted at the database.
- **Dynatrace** (optional): install the operator, create the token Secret, and apply a
  DynaKube — see [`dynakube.yaml.example`](../manifests/dynatrace/dynakube.yaml.example).
  Dynatrace's Smartscape/service view gives you the same story from the other side:
  the demo services now depend on an external PostgreSQL host, and its query load is
  attributed back to the calling services.

Two screenshots make this land — capture them live during the walkthrough:

![Jaeger service map / trace waterfall showing a product-catalog request whose PostgreSQL span now targets the Everest PgBouncer endpoint.](images/jaeger-service-map.png)

> **Screenshot — Jaeger:** a product-catalog (or accounting) trace expanded to the
> database span. The point to highlight on screen: the span's peer/host is the Everest
> PgBouncer LoadBalancer IP on port `5432`, database `otel` — proof the query left the
> bundled DB. _(Capture during the stream; drop the PNG at `docs/images/jaeger-service-map.png`.)_

![OpenEverest UI database view showing the demo-pg PostgreSQL 17.10 cluster in state ready, with its PgBouncer endpoint and connection details.](images/everest-ui-db-view.png)

> **Screenshot — Everest UI:** the `demo-pg` cluster detail page (Everest UI,
> port-forwarded in Step 2), showing engine **PostgreSQL 17.10**, state **ready**, and
> the exposed connection endpoint. This is the "managed database" half of the story —
> the same database the Jaeger span is now hitting. _(Capture during the stream; drop the
> PNG at `docs/images/everest-ui-db-view.png`.)_

## Teardown

```sh
./scripts/90-teardown.sh
```

Reverts the demo to its bundled DB, deletes the DatabaseCluster, uninstalls both
Everest Helm releases (`helm uninstall everest` in `everest-dbs` then `everest-system`),
and removes the residual `*.pgv2.percona.com` CRDs that survive the Helm uninstall
(the Percona operator's CRDs are cluster-scoped).

## Troubleshooting / gotchas (all hit during the real dry-run)

1. The `openeverest/openeverest` core chart doesn't create the DB namespace/operator → install the separate `openeverest/everest-db-namespace` chart.
2. PostgreSQL 17.4 unavailable on operator v3.0.0 → pin 17.10.
3. `expose.type: external` is deprecated → use `LoadBalancer`.
4. The pguser Secret has **no `uri` key** → build the conn string from `user`/`password`.
5. `pg_stat_statements` preloads but isn't installed → `CREATE EXTENSION` in the seed.
6. The demo uses db `otel` / user `otelu`, **not** `astronomy_db` / `astronomy_user`.
7. The bundled DB component is `postgresql`, **not** `astronomy-db`.
8. `helm uninstall` leaves the cluster-scoped Percona CRDs → delete them manually (teardown script does this).
