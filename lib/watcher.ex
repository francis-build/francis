defmodule Francis.Watcher do
  @moduledoc """
  Watcher mode for development that checks modified time of your files and recompiles them.

  **Security note:** This module calls `Code.eval_file/1` on modified `.ex` and `.exs` files.
  Only enable in trusted development environments via `config :francis, dev: true`.
  """
  use GenServer
  require Logger

  @excluded_dirs ~w(_build deps .elixir_ls .git)
  @check_interval 100

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{files: %{}})
  end

  @impl true
  def init(state) do
    Logger.debug("Development watch mode enabled")
    Code.put_compiler_option(:ignore_module_conflict, true)
    Process.send_after(self(), :check, @check_interval)
    {:ok, state}
  end

  # sobelow_skip ["RCE.CodeModule"]
  @impl true
  def handle_info(:check, %{files: files} = state) do
    files =
      "./**/*.{ex,exs}"
      |> Path.wildcard()
      |> Enum.reject(&excluded?/1)
      |> Enum.reduce(files, fn path, files ->
        case File.stat(path) do
          {:ok, %{mtime: new_mtime}} ->
            case Map.get(files, path) do
              mtime when not is_nil(mtime) and new_mtime != mtime ->
                recompile(path)

              _ ->
                nil
            end

            Map.put(files, path, new_mtime)

          {:error, _} ->
            Map.delete(files, path)
        end
      end)

    Process.send_after(self(), :check, @check_interval)
    {:noreply, %{state | files: files}}
  end

  defp excluded?(path) do
    Enum.any?(@excluded_dirs, fn dir ->
      String.starts_with?(path, "./#{dir}/")
    end)
  end

  defp recompile(path) do
    Code.eval_file(path)
  rescue
    e ->
      Logger.warning("Failed to recompile #{path}: #{inspect(e)}")
  end
end
