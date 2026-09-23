# Architecture

## The scenario

The OpenTelemetry Demo's **product-catalog** and **accounting** services read/write
PostgreSQL. By default that's a bundled, unmanaged `postgresql` Deployment inside
the demo's Helm release. This tutorial replaces it with a database **provisioned and
managed by OpenEverest** — demonstrating that a stateful backing service can be
declarative, observable, and operationally owned, without touching application code.

## Before → after

```
BEFORE (baseline)                          AFTER (Everest-managed)
┌─────────────────────────┐                ┌─────────────────────────┐
│ ns: otel-demo           │                │ ns: otel-demo           │
│  frontend-proxy (LB)    │                │  frontend-proxy (LB)    │
│  product-catalog ─┐     │                │  product-catalog ─┐     │
│  accounting ──────┤     │                │  accounting ──────┤     │
│                   ▼     │                │                   │     │
│  postgresql (bundled)   │                │  (bundled DB off) │     │
└─────────────────────────┘                └───────────────────┼─────┘
                                                                │ sslmode=require
                                                                ▼
                                           ┌─────────────────────────┐
                                           │ ns: everest-dbs         │
                                           │  PgBouncer (LB) ── proxy │
                                           │  demo-pg (PostgreSQL 17) │
                                           │  managed by Everest /    │
                                           │  Percona PG operator     │
                                           │  + pg_stat_statements    │
                                           └─────────────────────────┘
```

## Components

| Layer | What | Namespace |
|---|---|---|
| Application | OpenTelemetry Demo (product-catalog, accounting, frontend, …) | `otel-demo` |
| DBaaS control plane | OpenEverest server + Percona PostgreSQL operator | `everest-system` |
| Managed database | `demo-pg` DatabaseCluster (PostgreSQL 17.10 + PgBouncer) | `everest-dbs` |
| Observability | OTel Collector → Jaeger/Grafana (bundled); Dynatrace (optional) | `otel-demo`, `dynatrace` |

## Connection wiring

- **product-catalog** (Go, libpq): `postgres://otelu:otelp@<LB>:5432/otel?sslmode=require`
- **accounting** (.NET, Npgsql): `Host=<LB>;Port=5432;Username=otelu;Password=otelp;Database=otel;SSL Mode=Require;Trust Server Certificate=true`

`<LB>` is the PgBouncer LoadBalancer IP. TLS is required because the operator serves
a self-signed certificate; the .NET side trusts it via `Trust Server Certificate=true`.

## Why these choices

- **CR-based provisioning** (a `DatabaseCluster` manifest) over click-ops: deterministic,
  reviewable, and reproducible — the whole demo is `kubectl apply`.
- **Direct-to-primary for admin DDL, PgBouncer for the app**: `CREATE DATABASE` can't
  run through a transaction pooler, so the seed talks to the primary; the app talks to
  the pooled LoadBalancer endpoint.
- **`pg_stat_statements`**: gives the demo a real database-observability story —
  query-level stats correlated with the demo's traces.
