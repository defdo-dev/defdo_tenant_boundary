defmodule DefdoTenantBoundary.PubSubTest do
  use ExUnit.Case, async: false

  alias Defdo.Tenant
  alias Defdo.Tenant.Boundary.PubSub
  alias Defdo.Tenant.Context

  # Test double for Phoenix.PubSub
  defmodule TestPubSub do
    def subscribe(topic) do
      send(:test_process, {:subscribed, topic})
      :ok
    end

    def broadcast(topic, message) do
      send(:test_process, {:broadcast, topic, message})
      :ok
    end
  end

  setup do
    Process.register(self(), :test_process)
    :ok
  end

  describe "broadcast/4" do
    test "publishes envelope with tenant context" do
      Context.put(Context.new("tenant-pub-123"))

      PubSub.broadcast(TestPubSub, "tenant:orders", "order:created", %{order_id: 1})

      assert_received {:broadcast, "tenant:orders", {:tenant_event, envelope}}

      assert envelope["event"] == "order:created"
      assert envelope["payload"] == %{order_id: 1}
      assert %{"tenant_id" => "tenant-pub-123"} = envelope["tenant_context"]
      assert is_integer(envelope["published_at"])
    after
      Context.clear()
    end

    test "publishes envelope without context in observe mode" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        PubSub.broadcast(TestPubSub, "tenant:orders", :no_context_event, %{order_id: 2})

        assert_received {:broadcast, "tenant:orders", {:tenant_event, envelope}}
        refute Map.has_key?(envelope, "tenant_context")
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when no context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        assert_raise ArgumentError, ~r/no tenant context/, fn ->
          PubSub.broadcast(TestPubSub, "tenant:orders", "event", %{x: 1})
        end
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end
  end

  describe "subscribe/2" do
    test "delegates to pubsub module" do
      PubSub.subscribe(TestPubSub, "tenant:orders")

      assert_received {:subscribed, "tenant:orders"}
    end
  end

  describe "handle_message/2" do
    test "restores context and executes callback" do
      envelope = %{
        "event" => "order:created",
        "payload" => %{"order_id" => 42},
        "tenant_context" => Context.to_serializable(Context.new("tenant-pub-recv")),
        "published_at" => System.system_time(:second)
      }

      PubSub.handle_message(envelope, fn payload ->
        assert Tenant.current_tenant_id() == "tenant-pub-recv"
        assert payload["order_id"] == 42
        send(:test_process, {:processed, Tenant.current_tenant_id()})
      end)

      assert_received {:processed, "tenant-pub-recv"}
      # context is cleared after callback
      assert is_nil(Tenant.current_tenant_id())
    end

    test "runs callback without context when envelope has none" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        envelope = %{
          "event" => "order:created",
          "payload" => %{"order_id" => 1},
          "published_at" => System.system_time(:second)
        }

        PubSub.handle_message(envelope, fn payload ->
          assert is_nil(Tenant.current_tenant_id())
          assert payload["order_id"] == 1
          send(:test_process, {:processed_no_ctx, true})
        end)

        assert_received {:processed_no_ctx, true}
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when envelope has no context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        envelope = %{
          "event" => "order:created",
          "payload" => %{},
          "published_at" => System.system_time(:second)
        }

        assert_raise ArgumentError, ~r/no tenant context/, fn ->
          PubSub.handle_message(envelope, fn _ -> :ok end)
        end
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end
  end

  describe "build_envelope/2" do
    test "returns envelope without broadcasting" do
      Context.put(Context.new("tenant-env"))

      envelope = PubSub.build_envelope("custom.event", %{data: 1})

      assert envelope["event"] == "custom.event"
      assert %{"tenant_id" => "tenant-env"} = envelope["tenant_context"]
      # no broadcast message in mailbox
      refute_received {:broadcast, _, _}
    after
      Context.clear()
    end
  end
end
