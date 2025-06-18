defmodule ReadmeTest do
  use ExUnit.Case, async: true

  @app Mix.Project.config()[:app]

  test "version in README.md always matches the minor #{@app} version" do
    app_version = Mix.Project.config()[:version] |> Version.parse!() |> Map.put(:patch, 0)

    assert File.read!(Path.join(__DIR__, "../README.md")) =~
             ~s'{:#{@app}, "~> #{Version.to_string(app_version)}"}'
  end
end
