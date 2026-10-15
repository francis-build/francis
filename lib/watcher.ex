defmodule Francis.Watcher do
  @moduledoc """
  Watcher mode for development that checks modified time of your files and recompiles them.

  Only `lib/**/*.ex` and, for umbrella projects, `apps/*/lib/**/*.ex` under the current
  working directory are watched, so `deps/`, `_build/`, `mix.exs`, config and test files are
  never evaluated.

  A file that fails to evaluate (e.g. a syntax error in a half-finished save) is logged and
  skipped until it is saved again; the watcher keeps running.

  ## Options

    * `:root` - project directory to watch (defaults to `File.cwd!/0`)
    * `:interval` - polling interval in milliseconds (defaults to `500`)
  """
  use GenServer
  require Logger

  @interval 500
  @patterns ["lib/**/*.ex", "apps/*/lib/**/*.ex"]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    Logger.debug("Development watch mode enabled")
    Code.put_compiler_option(:ignore_module_conflict, true)

    root = Keyword.get(opts, :root, File.cwd!())
    files = scan(root)

    if files == %{} do
      Logger.warning(
        "Francis.Watcher found no files to watch under #{root} (#{Enum.join(@patterns, ", ")})"
      )
    end

    state = %{
      files: files,
      root: root,
      interval: Keyword.get(opts, :interval, @interval)
    }

    Process.send_after(self(), :check, state.interval)
    {:ok, state}
  end

  def handle_info(:check, %{files: files, root: root, interval: interval} = state) do
    new_files = scan(root)

    for {path, mtime} <- new_files,
        old_mtime = Map.get(files, path),
        not is_nil(old_mtime) and old_mtime != mtime do
      eval_file(path)
    end

    Process.send_after(self(), :check, interval)
    {:noreply, %{state | files: new_files}}
  end

  # The new mtime is recorded either way, so a broken file is retried only on its next save
  # sobelow_skip ["RCE.CodeModule"]
  defp eval_file(path) do
    Code.eval_file(path)
  rescue
    error ->
      Logger.error("Francis.Watcher failed to reload #{path}:\n" <> Exception.message(error))
  end

  defp scan(root) do
    @patterns
    |> Enum.flat_map(&(root |> Path.join(&1) |> Path.wildcard()))
    |> Enum.reduce(%{}, fn path, acc ->
      case File.stat(path) do
        {:ok, %File.Stat{mtime: mtime}} -> Map.put(acc, path, mtime)
        {:error, _} -> acc
      end
    end)
  end
end
