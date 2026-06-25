# defdo_tenant_boundary — agent guide

Cross-process tenant boundary wrappers for the Defdo ecosystem. Third layer of the
Defdo Tenant Boundary Platform Kit (`defdo_tenant` → `defdo_tenant_plug` → `defdo_tenant_boundary`).

Conventions: smallest slice that compiles and passes tests; all wrappers respect
`Defdo.Tenant.Config` enforcement modes; telemetry events for every capture/restore/missing;
never log secrets; all artifacts in English.

**Tags have NO `v` prefix** — use `0.2.0`, not `v0.2.0`.

**Before every commit and tag**, run and pass:
- `DEFDO_TENANT_PATH=../defdo_tenant mix format` (then `--check-formatted` to confirm)
- `DEFDO_TENANT_PATH=../defdo_tenant mix credo --strict`
- `DEFDO_TENANT_PATH=../defdo_tenant mix test`

## Dev setup

When developing `defdo_tenant` and `defdo_tenant_boundary` together, set
`DEFDO_TENANT_PATH=../defdo_tenant` so the boundary package uses the local core:

```bash
DEFDO_TENANT_PATH=../defdo_tenant mix test
```

Before publishing, remove the `DEFDO_TENANT_PATH` conditional from `mix.exs`
and ensure the `defdo_tenant` Hex dep resolves cleanly.

## Namespace

All wrappers live under `Defdo.Tenant.Boundary.*`:

| Module | Purpose |
|---|---|
| `Defdo.Tenant.Boundary.Task` | Tenant-safe `Task.async` |
| `Defdo.Tenant.Boundary.Oban` | Job insertion with context capture |
| `Defdo.Tenant.Boundary.Worker` | `use` macro for Oban workers |
| `Defdo.Tenant.Boundary.GenServer` | Capture/restore helpers |
| `Defdo.Tenant.Boundary.PubSub` | Tenant-aware envelope |
| `Defdo.Tenant.Boundary.Webhook` | Trusted-edge tenant resolution |
| `Defdo.Tenant.Boundary.Cache` | Tenant-scoped cache key builder |
| `Defdo.Tenant.Boundary.Storage` | Tenant-scoped object storage path builder |

## Architecture rules

- Use `Defdo.Tenant.Boundary.*` wrappers; never hand-roll capture/restore.
- Context is always captured at the edge (insert/broadcast/init) and restored
  at the worker/callback.
- Enforcement modes (`:observe`, `:warn`, `:test_enforce`, `:strict`) are
  respected everywhere.
- Telemetry is emitted for every context capture, restore, and missing event.
- Heavy deps (Oban) stay here; `defdo_tenant` core stays light.
