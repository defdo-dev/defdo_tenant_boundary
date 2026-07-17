defmodule Defdo.Tenant.Boundary.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()
  @organization "defdo"
  @source_url "https://github.com/defdo-dev/defdo_tenant_boundary"

  def project do
    [
      app: :defdo_tenant_boundary,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Defdo.Tenant.Boundary",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Defdo.Tenant.Boundary.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:defdo_tenant, "~> 0.10.3", organization: @organization},
      {:oban, "~> 2.17"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  def docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Task: ~r/^Defdo\.Tenant\.Boundary\.Task$/,
        Oban: ~r/^Defdo\.Tenant\.Boundary\.(Oban|Worker)$/,
        PubSub: ~r/^Defdo\.Tenant\.Boundary\.PubSub/,
        GenServer: ~r/^Defdo\.Tenant\.Boundary\.GenServer/,
        Webhook: ~r/^Defdo\.Tenant\.Boundary\.Webhook/,
        Cache: ~r/^Defdo\.Tenant\.Boundary\.Cache/,
        Storage: ~r/^Defdo\.Tenant\.Boundary\.Storage/
      ],
      source_url_pattern: "#{@source_url}/blob/main/%{path}#L%{line}"
    ]
  end

  defp package do
    [
      organization: @organization,
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md VERSION AGENTS.md),
      description:
        "Cross-process tenant boundary wrappers for the Defdo ecosystem — Task, Oban, Worker, GenServer, PubSub, Webhook, Cache, Storage.",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
