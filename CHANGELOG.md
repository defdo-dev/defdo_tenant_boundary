# 0.3.0

## 0.4.0

### Every requirement declares the line it resolves on

- `defdo_tenant` `~> 0.14` -> `~> 0.15` (0.15.0, published today after its own
  requirement collapse). `~> 0.14` is two-segment and would resolve 0.15.0
  anyway — which is exactly the problem: it would be a lagging floor from the
  moment the parent moved, and this package would need a second release to say
  so.
- `oban` `~> 2.17` -> `~> 2.23` (resolves 2.23.1). Six minors of drift under a
  requirement that never complained.
- `ex_doc` `~> 0.34` -> `~> 0.40`.

Minor rather than patch: no source changed, but a narrowed requirement is not
something a consumer can take blindly.

**Consumers already follow.** Every one declares `defdo_tenant_boundary ~> 0.2`
or `~> 0.3` — both two-segment, so both resolve 0.4.0 without an edit. The
`~> 0.2` holders have in fact been resolving 0.3.x since that release.

53 tests, 0 failures. `mix hex.outdated` empty.

**Breaking for consumers still on `defdo_tenant` 0.13.x.**

- Require `defdo_tenant` `~> 0.14` (was `~> 0.10.3 or ~> 0.11`).

  The old requirement was not blocking anything — a two-segment `~> 0.11` is
  `>= 0.11.0 and < 1.0.0`, so 0.14.x already resolved. It is raised because a
  parent package should not carry compatibility for versions its consumers
  have stopped moving off; that is how the floor stays where the ecosystem
  actually is instead of where it was.

  This is a floor change, so it is a minor bump, not a patch: it changes what
  consumers are able to resolve.

## Who this affects, and how it will look

`defdo_cms` and `defdo_notification_hub` declare `{:defdo_tenant, "~> 0.13.1"}`
— three segments, so `>= 0.13.1 and < 0.14.0`. They cannot take this version.

They will NOT see an error. Hex resolves to the highest satisfiable release and
says nothing, so both stay on `defdo_tenant_boundary` 0.2.7 indefinitely and a
`mix deps.update` there will look like it did nothing. Diagnose it by reading
this package's requirement, not the host's.

Unblocking them is the `defdo_tenant` V05 adoption, not a constraint edit:
a `Tenant.Migrator` V05 wrapper (both sit at v04) and a skip rule that
recognises `shared_`. `defdo_cms`'s `skip_table/1` returns `false` for every
tuple; `defdo_notification_hub` uses the `Defdo.Tenant.Adapters.SkipTable`
default, also false. Without that, V05's rename of `tenant_domain_policies` to
`shared_domain_policies` leaves the renamed table tenant-scoped against a
column it does not have.

53 tests, 0 failures against defdo_tenant 0.14.2.

# 0.2.7

- Lock `defdo_tenant` 0.13.1 and `defdo_migrator` 0.2.4. Nothing in this
  package changes. 0.13.1 makes the tenant migration prefix host-controlled;
  migrator 0.2.4 fails closed on control-table errors (an error no longer
  reads as "version 0" and re-applies the chain) and records `inserted_by`
  ownership per applied version. Full suite against both: 53 tests, 0 failures.

# 0.2.6

- Allow `defdo_tenant` 0.11.x (`~> 0.10.3 or ~> 0.11`). Nothing in this package
  changes; the requirement was the blocker. `defdo_tenant_boundary` is a
  dependency of nearly every app, so its `~> 0.10.3` pin meant any app trying to
  move to `defdo_tenant` 0.11.0 could not resolve at all. `defdo_tenant` 0.11.0
  is migrator v4: `tenant_entitlements`, `tenant_provisions`, and
  `tenant_profiles.tier` converted from a Postgres ENUM to `varchar(64)`. The
  change is additive for anything already deployed — nothing here reads `tier`
  or the new tables.

# 0.2.5

- Fixed: `Defdo.Tenant.Boundary.Oban.new/2` and `insert/3` built jobs through
  `Oban.Job.new/2`, which sets only the worker field and silently drops every
  option the worker declared (`queue`, `max_attempts`, `unique`, ...). Jobs
  landed on the `default` queue with 20 attempts and, on engines that do not
  poll `default`, stayed `available` forever. Jobs are now built through the
  worker's own `new/2`, so declared options apply and explicit options
  override them.
- `new/2` without a `:worker` option now raises `ArgumentError` instead of
  building a worker-less job.

# 0.2.4

- Track `defdo_tenant` 0.10.4, a security release. It also dropped the `bypass`
  test dependency, which kept `plug_cowboy`, `cowboy`, `cowlib` and `ranch` — a
  second HTTP server — in the tree of anything building this package's test
  environment.
- `mix hex.audit` reports no advisories for this package. The existing
  `~> 0.10.3` requirement already allowed 0.10.4, so only the lockfile moved and
  this is a drop-in upgrade.

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
