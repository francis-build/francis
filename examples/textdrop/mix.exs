defmodule TextDrop.MixProject do
  use Mix.Project

  def project do
    [
      app: :text_drop,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [mod: {TextDrop, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
        {:pdf_extractor, "~> 0.2.1"}
    ] ++ deps(Mix.env())
  end

  defp deps(:prod) do
    [
        {:francis, "~> 0.1.22"}
    ]
  end

  defp deps(_) do
    [
        {:francis, path: "../../"}
    ]
  end

  defp aliases() do
    [
      "assets.deploy": ["francis.digest"],
    ]
  end
end
