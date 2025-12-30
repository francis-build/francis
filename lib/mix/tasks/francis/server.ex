defmodule Mix.Tasks.Francis.Server do
  @moduledoc """
  Starts the Francis server.

  ## Command line options

  Task accepts the same command-line options as `mix run`.

  The `--no-halt` flag is automatically added.
  """
  use Mix.Task

  alias Mix.Tasks.Run

  @shortdoc "Starts Francis server"

  @impl true
  def run(args), do: Run.run(args ++ run_args())

  defp iex_running?, do: Code.ensure_loaded?(IEx) and IEx.started?()

  defp run_args, do: if(iex_running?(), do: [], else: ["--no-halt"])
end
