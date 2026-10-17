defmodule TextDrop.MixProject do
  use Mix.Project

  def project do
    [
      app: :text_drop,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [mod: {TextDrop, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:pdf_extractor, "~> 0.10"}
    ] ++ deps(Mix.env())
  end

  defp deps(:prod) do
    [
      {:francis, "~> 0.4"}
    ]
  end

  defp deps(_) do
    [
      {:francis, path: "../../"}
    ]
  end

  defp aliases() do
    [
      "assets.deploy": ["francis.digest"]
    ]
  end
end
