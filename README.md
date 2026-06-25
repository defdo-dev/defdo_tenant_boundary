# Defdo.Tenant.Boundary v0.2.0

Cross-process tenant boundary wrappers for the Defdo ecosystem.

Part of the [Defdo Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

## Installation

```elixir
def deps do
  [
    {:defdo_tenant_boundary, "~> 0.1", organization: "defdo"}
  ]
end
```

## API Reference

### Task

```elixir
# Spawn a tenant-safe task — context captured now, restored in child process
task = Defdo.Tenant.Boundary.Task.async(fn -> do_tenant_work() end)
result = Defdo.Tenant.Boundary.Task.await(task)

# MFA form
task = Defdo.Tenant.Boundary.Task.async(MyModule, :my_function, [arg1, arg2])

# Under a supervisor
task = Defdo.Tenant.Boundary.Task.supervised(MySupervisor, fn -> do_work() end)

# Await multiple tasks
results = Defdo.Tenant.Boundary.Task.await_many([task1, task2])
```

### Oban

```elixir
# Insert with tenant context auto-attached
{:ok, job} = Defdo.Tenant.Boundary.Oban.insert(MyWorker, %{user_id: 42})
{:ok, job} = Defdo.Tenant.Boundary.Oban.insert(MyWorker, %{user_id: 42}, queue: :critical)

# Build changeset (same API as Oban.Job.new/2)
changeset = Defdo.Tenant.Boundary.Oban.new(%{user_id: 42}, worker: MyWorker)

# Attach context to an existing changeset
changeset = Defdo.Tenant.Boundary.Oban.attach_tenant(existing_changeset)
```

### Worker

```elixir
defmodule MyApp.Workers.SyncTenant do
  use Defdo.Tenant.Boundary.Worker, queue: :default, max_attempts: 3

  def perform_with_tenant(%Oban.Job{args: args}) do
    # tenant context already restored here
    do_tenant_work(args)
  end
end

# Standalone: restore context without the macro
def perform(job) do
  Defdo.Tenant.Boundary.Worker.restore_context_from_job(job)
  do_work(job)
end
```

### GenServer

```elixir
defmodule MyApp.TenantCache do
  use GenServer

  @impl true
  def init(tenant_id) do
    Defdo.Tenant.Boundary.GenServer.capture_init_context()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    Defdo.Tenant.Boundary.GenServer.restore_context()
    {:reply, state, state}
  end
end
```

### PubSub

```elixir
# Broadcast — captures context automatically
Defdo.Tenant.Boundary.PubSub.broadcast(MyApp.PubSub, "tenant:orders", "order:created", %{order_id: 123})

# Build envelope without broadcasting (for other transports)
envelope = Defdo.Tenant.Boundary.PubSub.build_envelope("order:created", %{order_id: 123})

# Subscribe
Defdo.Tenant.Boundary.PubSub.subscribe(MyApp.PubSub, "tenant:orders")

# Handle — restores context from envelope
def handle_info({:tenant_event, envelope}, state) do
  Defdo.Tenant.Boundary.PubSub.handle_message(envelope, fn payload ->
    process_order(payload)
  end)
  {:noreply, state}
end
```

### Webhook

```elixir
# Resolve tenant from trusted edge data
case Defdo.Tenant.Boundary.Webhook.resolve(%{host: "acme.example.com"}, resolver: :host) do
  {:ok, tenant} ->
    Defdo.Tenant.Boundary.Webhook.execute(tenant, fn ->
      process_webhook(payload)
    end)

  {:error, :unresolved} ->
    Logger.warning("Unknown tenant for webhook")
end

# Custom resolver
Defdo.Tenant.Boundary.Webhook.resolve(
  %{credential_id: "key-123"},
  resolver: {MyApp.Resolver, :by_credential, []}
)
```

### Cache

```elixir
# Tenant-scoped key
Defdo.Tenant.with_tenant("tenant-abc", fn ->
  key = Defdo.Tenant.Boundary.Cache.key("user:42")
  # => "tenant-abc:user:42"
end)

# Global key (no context needed)
Defdo.Tenant.Boundary.Cache.global_key("rate_limit:1.2.3.4")
# => "global:rate_limit:1.2.3.4"
```

### Storage

```elixir
# Tenant-scoped path
Defdo.Tenant.with_tenant("tenant-xyz", fn ->
  path = Defdo.Tenant.Boundary.Storage.path("uploads/avatar.jpg")
  # => "tenants/tenant-xyz/uploads/avatar.jpg"
end)

# Global path (no context needed)
Defdo.Tenant.Boundary.Storage.global_path("public/logo.png")
# => "global/public/logo.png"
```

## Enforcement Modes

All wrappers respect `Defdo.Tenant.Config` enforcement:

| Mode | Missing-context behaviour |
|---|---|
| `:observe` (default) | Emit telemetry; continue with fallback |
| `:warn` | Telemetry + log warning; continue with fallback |
| `:test_enforce` | Raise (test/CI only) |
| `:strict` | Raise |

## Telemetry Events

| Event | Source |
|---|---|
| `[:defdo, :tenant, :context, :restored]` | Task, Worker, GenServer, PubSub, Webhook |
| `[:defdo, :tenant, :context, :missing]` | Task, Worker, GenServer, PubSub |
| `[:defdo, :tenant, :oban, :context_captured]` | Oban insert |
| `[:defdo, :tenant, :oban, :context_missing]` | Oban insert (no context) |
| `[:defdo, :tenant, :genserver, :context_captured]` | GenServer init |
| `[:defdo, :tenant, :genserver, :context_missing]` | GenServer init (no context) |
| `[:defdo, :tenant, :context, :restored]` | Context restored (all wrappers) |
| `[:defdo, :tenant, :context, :missing]` | Context absent (all wrappers) |
| `[:defdo, :tenant, :pubsub, :published]` | PubSub broadcast |
| `[:defdo, :tenant, :pubsub, :context_missing]` | PubSub broadcast (no context) |
| `[:defdo, :tenant, :webhook, :resolved]` | Webhook tenant found |
| `[:defdo, :tenant, :webhook, :unresolved]` | Webhook tenant not found |
| `[:defdo, :tenant, :cache, :key_missing_context]` | Cache key (no context) |
| `[:defdo, :tenant, :storage, :path_missing_context]` | Storage path (no context) |
| `[:defdo, :tenant, :context, :restored]` | Context restored (Worker, GenServer, PubSub, Webhook) |
| `[:defdo, :tenant, :context, :missing]` | Context absent (Worker, GenServer, PubSub) |

## License

Apache-2.0
