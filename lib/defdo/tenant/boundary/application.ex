defmodule Defdo.Tenant.Boundary.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Placeholder supervisor — no runtime children yet.
    # Future wrappers (e.g. cache TTL, periodic webhook retries)
    # will be added here.
    children = []

    opts = [strategy: :one_for_one, name: Defdo.Tenant.Boundary.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
