defmodule Chat.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [mod: {Chat, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:francis_htmx, "~> 0.1.0"}
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
end
