# ChatLoopBackOff × OpenEverest

> **Companion repo for the CNCF ChatLoopBackOff livestream.** Provision a PostgreSQL
> database with [OpenEverest](https://github.com/openeverest/openeverest), then point
> the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo)'s
> product-catalog + accounting services at it — no app code changes, just Everest and
> connection strings.

<!--
CONTENT WRITER (agent 560a8b46-6043-84e9-8840-7a6de92a65d8): this README skeleton is
owned by you for prose/narrative. The Architect has filled in the technically-accurate
scaffolding (structure, validated commands, links). Please expand the intro, the
"Why this matters" narrative, and add the livestream framing / branding. Every command
and version below has been validated against a real cluster (2026-09-23) — do not change
them without re-validating.
-->

## What's here

| Path | What |
|---|---|
| [`docs/tutorial.md`](docs/tutorial.md) | Full end-to-end, copy-paste tutorial (6 steps). |
| [`docs/prerequisites.md`](docs/prerequisites.md) | Cluster + local-tool requirements, pinned versions. |
| [`docs/architecture.md`](docs/architecture.md) | Before/after diagram and design rationale. |
| [`manifests/everest/`](manifests/everest/) | DatabaseCluster CR, seed Job, and the demo→Everest swap overlay. |
| [`manifests/otel-demo/`](manifests/otel-demo/) | Baseline OTel Demo Helm values. |
| [`manifests/dynatrace/`](manifests/dynatrace/) | Optional DynaKube example for Dynatrace observability. |
| [`scripts/`](scripts/) | One script per tutorial step (`00`→`90`). |

## Quickstart

```sh
./scripts/00-prereqs.sh                       # everestctl + Helm repo
helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
  -n otel-demo --create-namespace --version 0.40.10 -f manifests/otel-demo/values.yaml
./scripts/10-install-everest.sh               # install Everest + PG operator
./scripts/20-provision-postgres.sh            # provision PostgreSQL 17.10
./scripts/30-seed-database.sh                 # load the demo schema/data
EVEREST_LB_IP=<printed above> ./scripts/40-swap-demo.sh   # swap the demo onto Everest
# ... observe in Jaeger/Grafana (bundled) or Dynatrace (optional) ...
./scripts/90-teardown.sh                      # clean up
```

Full walkthrough with explanations: **[docs/tutorial.md](docs/tutorial.md)**.

## Validated versions

everestctl **v1.16.2** · Percona PG operator **v3.0.0** · PostgreSQL **17.10** ·
opentelemetry-demo chart **0.40.10** / app **2.2.0**. See
[docs/prerequisites.md](docs/prerequisites.md).

## License

[Apache-2.0](LICENSE).
