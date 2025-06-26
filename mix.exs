defmodule Francis.MixProject do
  use Mix.Project

  @version "0.1.22"
  @description "Boilerplate killer using Plug with Bandit to quickly build endpoints and websocket listeners"
  @scm_url "https://github.com/francis-build/francis"

  def project do
    [
      name: "Francis",
      app: :francis,
      version: @version,
      description: @description,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      source_url: @scm_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: dialyzer(),
      escript: escript()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp package do
    [
      files: [
        "lib",
        "test",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      maintainers: ["Filipe Cabaço"],
      licenses: ["MIT"],
      links: %{"GitHub" => @scm_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      formatters: ["html", "epub"],
      source_ref: "v#{@version}"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:websock, "~> 0.5"},
      {:websock_adapter, "~> 0.5"},
      {:phoenix_html, "~> 4.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:req, "~> 0.5", only: [:test]},
      {:websockex, "~> 0.4", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp escript do
    [main_module: Mix.Tasks.Francis.New]
  end

  defp dialyzer do
    [
      list_unused_filters: true,
      plt_add_deps: :apps_tree,
      plt_add_apps: [:ex_unit, :iex, :mix],
      plt_file:
        {:no_warn, "priv/plts/elixir-#{System.version()}-erlang-otp-#{System.otp_release()}.plt"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
