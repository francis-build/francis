defmodule Chat.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: ["lib"]
    ]
  end

  def application do
    [mod: {Chat, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:francis, path: "../../"}
    ]
  end
end
