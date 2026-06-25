defmodule DefdoTenantBoundary.WebhookTest do
  use ExUnit.Case, async: false

  alias Defdo.Tenant
  alias Defdo.Tenant.Boundary.Webhook

  # Mock repo for testing built-in resolvers without a real database.
  # Uses process dictionary to configure the profile that `one/2` returns.
  defmodule MockRepo do
    def one(_query, _opts) do
      Process.get(:mock_repo_profile)
    end
  end

  defmodule TestResolver do
    def by_client_id(%{client_id: "known-client"}), do: profile()
    def by_client_id(_), do: nil

    defp profile do
      %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-resolved-456",
        domain: "known.example.com",
        is_active: true
      }
    end
  end

  describe "resolve/2 with custom resolver" do
    test "resolves tenant using custom MFA" do
      result =
        Webhook.resolve(
          %{client_id: "known-client"},
          resolver: {TestResolver, :by_client_id, []}
        )

      assert {:ok, profile} = result
      assert profile.tenant_id == "tenant-resolved-456"
    end

    test "returns unresolved when custom resolver returns nil" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        result =
          Webhook.resolve(
            %{client_id: "unknown"},
            resolver: {TestResolver, :by_client_id, []}
          )

        assert {:error, :unresolved} = result
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when unresolved" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        assert_raise ArgumentError, ~r/unable to resolve/, fn ->
          Webhook.resolve(
            %{client_id: "unknown"},
            resolver: {TestResolver, :by_client_id, []}
          )
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

  describe "resolve/2 with built-in :host resolver" do
    setup do
      Process.delete(:mock_repo_profile)
      :ok
    end

    test "resolves tenant by host when repo returns a profile" do
      profile = %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-host-1",
        domain: "acme.example.com",
        is_active: true
      }

      Process.put(:mock_repo_profile, profile)

      assert {:ok, found} =
               Webhook.resolve(%{host: "acme.example.com"},
                 resolver: :host,
                 repo: MockRepo
               )

      assert found.tenant_id == "tenant-host-1"
    end

    test "returns unresolved when repo returns nil" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        Process.put(:mock_repo_profile, nil)

        assert {:error, :unresolved} =
                 Webhook.resolve(%{host: "unknown.example.com"},
                   resolver: :host,
                   repo: MockRepo
                 )
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when host is unresolved" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        Process.put(:mock_repo_profile, nil)

        assert_raise ArgumentError, ~r/unable to resolve/, fn ->
          Webhook.resolve(%{host: "no-match.example.com"},
            resolver: :host,
            repo: MockRepo
          )
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

  describe "resolve/2 with built-in :domain resolver" do
    setup do
      Process.delete(:mock_repo_profile)
      :ok
    end

    test "resolves tenant by domain when repo returns a profile" do
      profile = %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-domain-2",
        domain: "widgets.example.com",
        is_active: true
      }

      Process.put(:mock_repo_profile, profile)

      assert {:ok, found} =
               Webhook.resolve(%{domain: "widgets.example.com"},
                 resolver: :domain,
                 repo: MockRepo
               )

      assert found.tenant_id == "tenant-domain-2"
    end

    test "returns unresolved when repo returns nil for domain" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        Process.put(:mock_repo_profile, nil)

        assert {:error, :unresolved} =
                 Webhook.resolve(%{domain: "nope.example.com"},
                   resolver: :domain,
                   repo: MockRepo
                 )
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end
  end

  describe "resolve/2 error cases" do
    test "raises for unknown resolver type" do
      assert_raise ArgumentError, ~r/unknown webhook resolver/, fn ->
        Webhook.resolve(%{host: "x.com"}, resolver: :unknown_resolver)
      end
    end

    test "raises when :host used without repo configured" do
      # No repo override, and Config.repo/0 returns nil
      assert_raise ArgumentError, ~r/no repo configured/, fn ->
        Webhook.resolve(%{host: "x.com"}, resolver: :host)
      end
    end
  end

  describe "execute/2" do
    test "executes function in tenant context" do
      profile = %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-exec-789",
        domain: "example.com",
        is_active: true
      }

      caller = self()

      Webhook.execute(profile, fn ->
        assert Tenant.current_tenant_id() == "tenant-exec-789"
        send(caller, {:executed, Tenant.current_tenant_id()})
      end)

      assert_received {:executed, "tenant-exec-789"}
      assert is_nil(Tenant.current_tenant_id())
    end

    test "clears context even on exception" do
      profile = %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-exec-err",
        domain: "example.com",
        is_active: true
      }

      catch_error(
        Webhook.execute(profile, fn ->
          raise "boom"
        end)
      )

      assert is_nil(Tenant.current_tenant_id())
    end
  end
end
