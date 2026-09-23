# Tutorial screenshots (live captures)

These two images are referenced from [`docs/tutorial.md`](../tutorial.md) **Step 6 —
Observe**. They are captured **live** during the ChatLoopBackOff walkthrough (the exact
IPs, trace IDs, and cluster state are environment-specific), so they are intentionally
not committed as static assets. Drop the PNGs here with these exact filenames:

| File | What to capture |
|---|---|
| `jaeger-service-map.png` | A product-catalog (or accounting) trace in Jaeger, expanded to its PostgreSQL span. Highlight that the span's peer/host is the **Everest PgBouncer LoadBalancer IP** on port `5432`, database `otel` — proof the query left the bundled DB. |
| `everest-ui-db-view.png` | The `demo-pg` cluster detail page in the OpenEverest UI (port-forwarded in Step 2), showing engine **PostgreSQL 17.10**, state **ready**, and the exposed connection endpoint. |

Until they are captured, the tutorial's image links will show as placeholders — that is
expected. The branded diagrams that *are* committed (hero, observability architecture,
demo flow) live in [`docs/assets/`](../assets/).
