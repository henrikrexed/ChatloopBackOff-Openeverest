# Prerequisites

You need a running Kubernetes cluster you have admin access to. The tutorial was
validated on Kubernetes v1.35, but any reasonably recent cluster works.

## Cluster requirements

| Requirement | Why |
|---|---|
| **Local-disk default StorageClass** (e.g. `local-path`) | PostgreSQL fsyncs its WAL; network filesystems (NFS/CIFS) cause stalls and, in some cases, silent corruption. If your cluster's default SC is network-backed, install `local-path-provisioner` and set `storage.class: local-path` in the DatabaseCluster CR (already done). |
| **A LoadBalancer implementation** (MetalLB, cloud LB, …) | The PgBouncer proxy and the demo storefront are exposed as `Service type=LoadBalancer`. |
| **Egress to GitHub** | The seed Job pulls the pinned `init.sql` from GitHub. Air-gapped? Bake it into a ConfigMap instead. |

## Local tools

| Tool | Version | Install |
|---|---|---|
| `kubectl` | matches your cluster | https://kubernetes.io/docs/tasks/tools/ |
| `helm` | v3.x | https://helm.sh/docs/intro/install/ |
| `everestctl` | v1.16.2 | installed by `scripts/00-prereqs.sh` |

## Pinned versions (validated 2026-09-23)

| Component | Version |
|---|---|
| everestctl / Everest server | v1.16.2 |
| Percona PostgreSQL operator | v3.0.0 |
| PostgreSQL (provisioned) | 17.10 |
| opentelemetry-demo (Helm chart / app) | 0.40.10 / 2.2.0 |
| cert-manager (optional, for Dynatrace) | v1.19.1 |
| dynatrace-operator (optional) | v1.6.0 |

Run `scripts/00-prereqs.sh` to install `everestctl` and add the OpenTelemetry Helm
repo, then follow [tutorial.md](./tutorial.md).
