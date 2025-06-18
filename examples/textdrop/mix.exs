defmodule TextDrop.MixProject do
  use Mix.Project

  def project do
    [
      app: :text_drop,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: ["lib"]
    ]
  end

  def application do
    [mod: {TextDrop, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
        {:francis, path: "../../"},
        {:pythonx, "~> 0.4.4"}
    ]
  end
end
