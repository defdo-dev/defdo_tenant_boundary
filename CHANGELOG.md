# 0.2.3

- Raise the minimum `defdo_tenant` dependency to `~> 0.10.3` and refresh the
  lockfile to the current tenant platform release.
- Stabilize enforcement-mode tests by serializing suites that temporarily
  change the global `:defdo_tenant` application configuration.

# 0.2.1

- Bump `defdo_tenant` dependency to `~> 0.10` to adopt the new
  `Defdo.Tenant.Context` process-local context as the single source of truth.

# 0.2.0

**Breaking:** all wrapper modules graduate to the `Defdo.Tenant.Boundary.*` namespace,
matching the documented public API contract. `Task` wrapper moves from `defdo_tenant`
core into this package.

- **Namespace:** `Defdo.Tenant.{Oban,Worker,...}` → `Defdo.Tenant.Boundary.{Oban,Worker,...}`.
- **Task:** `Defdo.Tenant.Boundary.Task` — tenant-safe `Task.async/1` / `async/3` /
  `supervised/2` / `await/1` / `await_many/1`.
- **Oban.insert/3:** removed redundant `:args` in opts; delegates to `new/2` for consistency.
- **Cache / Storage fallback:** no-context fallback uses `"unknown:"` / `"unknown/"` prefix
  instead of colliding with the legitimate `global:` namespace.
- **GenServer telemetry:** `module: nil` replaced with `boundary: :genserver` for consistency
  across all wrappers.
- **Worker:** removed dead `rescue e -> reraise e` from generated `perform/1`.
- **Tests:** +9 tests (Oban `insert/3`, Webhook `:host`/`:domain` resolvers, telemetry assertions).
- **Credo:** `--strict` exits 0 with no issues.
- **Docs:** `AGENTS.md` added; `Application` supervisor documented.
- **Packaging:** `VERSION` and `AGENTS.md` now included in Hex tarball.

---

# 0.1.0

Initial release of the Defdo Tenant Boundary Kit — cross-process wrappers.

- `Defdo.Tenant.Boundary.Oban` — tenant-safe job insertion; captures `Context` into job `meta`.
- `Defdo.Tenant.Boundary.Worker` — `use` macro wrapping `perform/1` with context restore;
  implement `perform_with_tenant/1` instead of `perform/1`.
- `Defdo.Tenant.Boundary.GenServer` — `capture_init_context/0` + `restore_context/0` helpers
  for explicit context management in GenServer callbacks.
- `Defdo.Tenant.Boundary.PubSub` — tenant-aware envelope: `broadcast/4`, `subscribe/2`,
  `handle_message/2`, `build_envelope/2`.
- `Defdo.Tenant.Boundary.Webhook` — two-phase trusted-edge resolution: `resolve/2` with
  built-in `:host` and `:domain` resolvers + custom MFA; `execute/2` for scoped logic.
- `Defdo.Tenant.Boundary.Cache` — `key/1` prefixes with tenant ID; `global_key/1` for shared keys.
- `Defdo.Tenant.Boundary.Storage` — `path/1` prefixes with `tenants/:id/`; `global_path/1` for shared.

All wrappers respect `Defdo.Tenant.Config` enforcement modes (`:observe`, `:warn`,
`:test_enforce`, `:strict`) and emit telemetry events for context capture, restore,
and missing events.
