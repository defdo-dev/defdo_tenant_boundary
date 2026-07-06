defmodule DefdoTenantBoundary.TaskTest do
  use ExUnit.Case, async: false

  alias Defdo.Tenant
  alias Defdo.Tenant.Boundary.Task, as: TTask
  alias Defdo.Tenant.Context

  setup do
    test_pid = self()

    :telemetry.attach(
      :task_restored,
      [:defdo, :tenant, :context, :restored],
      fn _event, measures, meta, _config ->
        send(test_pid, {:telemetry, :restored, measures, meta})
      end,
      nil
    )

    :telemetry.attach(
      :task_missing,
      [:defdo, :tenant, :context, :missing],
      fn _event, measures, meta, _config ->
        send(test_pid, {:telemetry, :missing, measures, meta})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(:task_restored)
      :telemetry.detach(:task_missing)
      Context.clear()
    end)

    :ok
  end

  describe "async/1" do
    test "restores the caller's tenant context inside the task" do
      Context.put(Context.new("tenant-task-async"))

      task = TTask.async(fn -> Tenant.current_tenant_id() end)

      assert TTask.await(task) == "tenant-task-async"
      assert_received {:telemetry, :restored, %{count: 1}, %{boundary: :task, scope: :tenant}}
    end

    test "does not leak context back into the caller" do
      Context.put(Context.new("tenant-task-no-leak"))

      TTask.async(fn -> :ok end) |> TTask.await()

      assert Tenant.current_tenant_id() == "tenant-task-no-leak"
    end

    test "emits missing-context telemetry when the caller has none" do
      Context.clear()

      TTask.async(fn -> :ok end) |> TTask.await()

      assert_received {:telemetry, :missing, %{count: 1}, %{boundary: :task}}
    end
  end

  describe "wrap/1" do
    test "captures now, restores when the returned function is later invoked elsewhere" do
      Context.put(Context.new("tenant-task-wrap"))
      wrapped = TTask.wrap(fn -> Tenant.current_tenant_id() end)

      # Simulate a framework (Phoenix LiveView's start_async, etc.) invoking
      # the callback in a completely fresh process with no tenant context.
      Context.clear()
      test_pid = self()

      spawn_link(fn -> send(test_pid, {:result, wrapped.()}) end)

      assert_receive {:result, "tenant-task-wrap"}
    end

    test "cleans up context after running so it does not leak into the executor process" do
      Context.put(Context.new("tenant-task-wrap-cleanup"))
      wrapped = TTask.wrap(fn -> :ok end)
      Context.clear()

      test_pid = self()

      spawn_link(fn ->
        wrapped.()
        send(test_pid, {:after_run, Tenant.current_tenant_id()})
      end)

      assert_receive {:after_run, nil}
    end

    test "plugs directly into Task.async as a drop-in callback" do
      Context.put(Context.new("tenant-task-wrap-composable"))

      task = Task.async(TTask.wrap(fn -> Tenant.current_tenant_id() end))

      assert Task.await(task) == "tenant-task-wrap-composable"
    end
  end
end
