defmodule Defdo.Tenant.Boundary.Task do
  @moduledoc """
  Tenant-safe `Task` wrapper — part of the Tenant Boundary Kit.

  A spawned task runs in a **separate BEAM process**, so it does not inherit the
  caller's tenant context. Write:

      Defdo.Tenant.Boundary.Task.async(fn -> do_work() end)

  instead of `Task.async/1`. Captures caller's `Defdo.Tenant.Context`,
  restores it inside the task process, runs the work, cleans up afterwards.

  Missing context follows `Defdo.Tenant.Config` enforcement: telemetry always
  emitted; `:warn`/`:test_enforce`/`:strict` log or raise.

  ## Framework-owned async (Phoenix LiveView `start_async`, etc.)

  Some async entry points hand you a callback and spawn the process
  themselves — you cannot swap in `Task.async/1`. Use `wrap/1` to get back a
  plain 0-arity function with the same capture/restore/cleanup behavior,
  which any such API can call:

      socket
      |> start_async(:connect, Defdo.Tenant.Boundary.Task.wrap(fn -> do_work() end))

  `wrap/1` captures context in the **calling** process immediately (same as
  `async/1`); the returned function only performs the restore/run/cleanup
  when invoked, wherever that ends up running.

  ## See also

    * `Defdo.Tenant.Boundary.Oban` — same pattern for Oban jobs
    * `Defdo.Tenant.Boundary.Worker` — same pattern for Oban workers
    * `Defdo.Tenant.Context` — process-local context storage
    * `Defdo.Tenant.Config` — enforcement modes
  """

  require Logger

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @doc "Tenant-safe `Task.async/1`."
  @spec async((-> any())) :: Task.t()
  def async(fun) when is_function(fun, 0) do
    Task.async(wrap(fun))
  end

  @doc """
  Captures the caller's tenant context now; returns a 0-arity function that
  restores it, runs `fun`, and cleans up — for async APIs that spawn the
  process themselves (Phoenix LiveView's `start_async`, custom supervisors,
  etc.) instead of accepting a `Task.t()`.
  """
  @spec wrap((-> any())) :: (-> any())
  def wrap(fun) when is_function(fun, 0) do
    captured = capture()
    fn -> run(captured, fun) end
  end

  @doc "Tenant-safe `Task.async/3`."
  @spec async(module(), atom(), [term()]) :: Task.t()
  def async(mod, fun, args) when is_atom(mod) and is_atom(fun) and is_list(args) do
    captured = capture()
    Task.async(fn -> run(captured, fn -> apply(mod, fun, args) end) end)
  end

  @doc "Tenant-safe `Task.Supervisor.async/2` against `supervisor`."
  @spec supervised(Supervisor.supervisor(), (-> any())) :: Task.t()
  def supervised(supervisor, fun) when is_function(fun, 0) do
    captured = capture()
    Task.Supervisor.async(supervisor, fn -> run(captured, fun) end)
  end

  defdelegate await(task, timeout \\ 5000), to: Task
  defdelegate await_many(tasks, timeout \\ 5000), to: Task

  # ── Internals ─────────────────────────────────────────────────────────────────

  defp capture do
    captured = Context.capture()
    on_missing(captured)
    captured
  end

  defp run(captured, fun) do
    Context.clear()

    case captured do
      %Context{} = ctx ->
        Context.put(ctx)

        :telemetry.execute(
          [:defdo, :tenant, :context, :restored],
          %{count: 1},
          %{boundary: :task, scope: ctx.scope}
        )

      _ ->
        :ok
    end

    try do
      fun.()
    after
      Context.clear()
    end
  end

  defp on_missing(nil) do
    :telemetry.execute([:defdo, :tenant, :context, :missing], %{count: 1}, %{boundary: :task})

    cond do
      Config.raising?() ->
        raise ArgumentError,
              "Defdo.Tenant.Boundary.Task started with no tenant context. " <>
                "Set a context (Defdo.Tenant.with_tenant/2) or use a global/system-edge context."

      Config.warning?() ->
        Logger.warning("Defdo.Tenant.Boundary.Task started with no tenant context")

      true ->
        :ok
    end
  end

  defp on_missing(_ctx), do: :ok
end
