defmodule Defdo.Tenant.Boundary.Oban do
  @moduledoc """
  Tenant-safe Oban job insertion.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  ## Problem

  Oban jobs execute in **separate BEAM processes**. The caller's
  `Defdo.Tenant.Context` — stored in the process dictionary — is not inherited.
  Without explicit handling, a job runs without tenant scope and
  `Defdo.Tenant.Repo.Protection` rejects every query.

  ## Solution

  `Defdo.Tenant.Boundary.Oban` captures the current `Defdo.Tenant.Context` and serializes
  it into the job's `meta` map (key `"defdo_tenant_context"`). On execution,
  `Defdo.Tenant.Boundary.Worker` restores it before the business callback.

  ## Usage

      # Build a changeset (same API as Oban.Job.new/2):
      changeset = Defdo.Tenant.Boundary.Oban.new(%{user_id: 42}, worker: MyWorker)

      # Insert a job with context auto-attached:
      {:ok, job} = Defdo.Tenant.Boundary.Oban.insert(MyWorker, %{user_id: 42})

      # Insert with custom options:
      {:ok, job} = Defdo.Tenant.Boundary.Oban.insert(MyWorker, %{user_id: 42}, queue: :critical)

      # Attach context to an existing job/changeset:
      changeset = Defdo.Tenant.Boundary.Oban.attach_tenant(existing_changeset)

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement:

  | Mode | Missing-context behaviour |
  |---|---|
  | `:observe` (default) | Emit `[:defdo, :tenant, :oban, :context_missing]` telemetry |
  | `:warn` | Telemetry + log warning |
  | `:test_enforce` | Raise if no context (test/CI only) |
  | `:strict` | Raise if no context |

  ## Telemetry

  | Event | Metadata |
  |---|---|
  | `[:defdo, :tenant, :oban, :context_captured]` | `worker`, `scope` |
  | `[:defdo, :tenant, :oban, :context_missing]` | `worker` |

  ## See also

  * `Defdo.Tenant.Boundary.Worker` — restores context before job execution
  * `Defdo.Tenant.Config` — enforcement modes
  * `Defdo.Tenant.Boundary.Task` — same pattern for `Task.async`
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @context_meta_key "defdo_tenant_context"

  @doc """
  Build a job changeset with tenant context captured into `meta`.

  The job is built through the worker's own `new/2`, so the options the
  worker declared (`use Oban.Worker, queue: ..., max_attempts: ...,
  unique: ...`) apply; explicit opts override them. Building via
  `Oban.Job.new/2` with `worker:` would only set the worker field and
  silently drop everything the worker declared — which strands jobs on
  the `default` queue.

  Returns an `Ecto.Changeset` ready for `Oban.insert/1`.
  """
  @spec new(map(), keyword()) :: Ecto.Changeset.t()
  def new(args, opts) when is_map(args) and is_list(opts) do
    {worker, opts} = Keyword.pop(opts, :worker)

    unless is_atom(worker) and not is_nil(worker) do
      raise ArgumentError,
            "Defdo.Tenant.Boundary.Oban.new/2 requires the :worker option, " <>
              "got: #{inspect(worker)}"
    end

    worker
    |> worker_new(args, opts)
    |> attach_tenant()
  end

  @doc """
  Insert a tenant-scoped job.

  Builds the job via the worker's `new/2` (respecting its declared opts),
  attaches tenant context, and calls `Oban.insert/1`.
  """
  @spec insert(module(), map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def insert(worker, args, opts \\ []) when is_atom(worker) and is_map(args) and is_list(opts) do
    new(args, Keyword.put(opts, :worker, worker))
    |> Oban.insert()
  end

  @doc """
  Attach tenant context to an existing changeset or job struct.
  Useful when wrapping jobs built by other libraries.
  """
  def attach_tenant(%Ecto.Changeset{data: %Oban.Job{} = job} = cs) do
    %{cs | data: put_meta(job)}
  end

  def attach_tenant(%Oban.Job{} = job) do
    put_meta(job)
  end

  # ── Internals ─────────────────────────────────────────────────────────────────

  defp worker_new(worker, args, opts) do
    Code.ensure_loaded(worker)

    if function_exported?(worker, :new, 2) do
      worker.new(args, opts)
    else
      Oban.Job.new(args, Keyword.put(opts, :worker, worker))
    end
  end

  defp put_meta(%Oban.Job{} = job) do
    case Context.capture() do
      %Context{} = ctx ->
        :telemetry.execute(
          [:defdo, :tenant, :oban, :context_captured],
          %{count: 1},
          %{worker: job.worker, scope: ctx.scope}
        )

        meta = Map.put(job.meta, @context_meta_key, Context.to_serializable(ctx))
        %Oban.Job{job | meta: meta}

      nil ->
        :telemetry.execute(
          [:defdo, :tenant, :oban, :context_missing],
          %{count: 1},
          %{worker: job.worker}
        )

        cond do
          Config.raising?() ->
            raise ArgumentError,
                  "Defdo.Tenant.Boundary.Oban job #{inspect(job.worker)} has no tenant context. " <>
                    "Set a context with Defdo.Tenant.with_tenant/2 or use a global/system-edge context."

          Config.warning?() ->
            require Logger

            Logger.warning(
              "Defdo.Tenant.Boundary.Oban job #{inspect(job.worker)} has no tenant context"
            )

          true ->
            :ok
        end

        job
    end
  end
end
