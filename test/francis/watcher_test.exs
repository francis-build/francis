defmodule Francis.WatcherTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  @moduletag :tmp_dir

  defp write_module(path, mod, value) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule #{inspect(mod)} do\n  def value, do: #{inspect(value)}\nend\n")
  end

  # mtime has one-second resolution, so push it forward to guarantee a change
  defp bump_mtime(path, seconds) do
    now = :calendar.datetime_to_gregorian_seconds(:calendar.local_time())
    File.touch!(path, :calendar.gregorian_seconds_to_datetime(now + seconds))
  end

  defp unique_module(name),
    do: Module.concat(__MODULE__, "#{name}#{System.unique_integer([:positive])}")

  # Retries the assertion until it passes or the deadline expires, re-raising the last failure
  defp eventually(fun, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_eventually(fun, deadline)
  end

  defp do_eventually(fun, deadline) do
    fun.()
  rescue
    error in [ExUnit.AssertionError, UndefinedFunctionError] ->
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        do_eventually(fun, deadline)
      else
        reraise error, __STACKTRACE__
      end
  end

  test "re-evaluates changed files under lib/ only", %{tmp_dir: tmp_dir} do
    lib_mod = unique_module("Lib")
    deps_mod = unique_module("Deps")
    lib_file = Path.join(tmp_dir, "lib/watched.ex")
    deps_file = Path.join(tmp_dir, "deps/dep/lib/dep.ex")
    mix_file = Path.join(tmp_dir, "mix.exs")

    write_module(lib_file, lib_mod, 1)
    write_module(deps_file, deps_mod, 1)
    write_module(mix_file, deps_mod, 1)

    pid = start_supervised!({Francis.Watcher, root: tmp_dir, interval: 10})
    assert Map.keys(:sys.get_state(pid).files) == [lib_file]

    write_module(lib_file, lib_mod, 2)
    bump_mtime(lib_file, 5)
    write_module(deps_file, deps_mod, 2)
    bump_mtime(deps_file, 5)
    write_module(mix_file, deps_mod, 2)
    bump_mtime(mix_file, 5)

    eventually(fn -> assert lib_mod.value() == 2 end)
    refute Code.ensure_loaded?(deps_mod)
    assert Map.keys(:sys.get_state(pid).files) == [lib_file]
  end

  test "watches apps/*/lib in umbrella projects", %{tmp_dir: tmp_dir} do
    app_mod = unique_module("App")
    app_file = Path.join(tmp_dir, "apps/my_app/lib/my_app.ex")
    write_module(app_file, app_mod, 1)

    pid = start_supervised!({Francis.Watcher, root: tmp_dir, interval: 10})
    assert Map.keys(:sys.get_state(pid).files) == [app_file]

    write_module(app_file, app_mod, 2)
    bump_mtime(app_file, 5)

    eventually(fn -> assert app_mod.value() == 2 end)
  end

  test "warns when there is nothing to watch", %{tmp_dir: tmp_dir} do
    log =
      capture_log(fn ->
        start_supervised!({Francis.Watcher, root: tmp_dir, interval: 10})
      end)

    assert log =~ "found no files to watch"
  end

  test "a file that fails to compile does not crash the watcher", %{tmp_dir: tmp_dir} do
    mod = unique_module("Broken")
    file = Path.join(tmp_dir, "lib/broken.ex")
    write_module(file, mod, 1)

    pid = start_supervised!({Francis.Watcher, root: tmp_dir, interval: 10})

    log =
      capture_log(fn ->
        capture_io(:stderr, fn ->
          File.write!(file, "defmodule #{inspect(mod)} do\n  def value, do: (\n")
          bump_mtime(file, 5)
          broken_mtime = File.stat!(file).mtime

          eventually(fn -> assert :sys.get_state(pid).files[file] == broken_mtime end)
          # One more full cycle so the eval of the broken file has completed
          _ = :sys.get_state(pid)
        end)
      end)

    assert log =~ "failed to reload #{file}"
    assert Process.alive?(pid)

    write_module(file, mod, 3)
    bump_mtime(file, 10)

    eventually(fn -> assert mod.value() == 3 end)
    assert Process.alive?(pid)
  end
end
