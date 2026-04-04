defmodule Francis.WatcherTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @tmp_dir Path.join(System.tmp_dir!(), "francis_watcher_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    cwd = File.cwd!()
    File.cd!(@tmp_dir)

    on_exit(fn ->
      File.cd!(cwd)
      File.rm_rf!(@tmp_dir)
    end)

    :ok
  end

  test "starts and initializes successfully" do
    {:ok, pid} = Francis.Watcher.start_link([])
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "detects and recompiles modified files" do
    # Create an initial .ex file
    File.mkdir_p!("lib")
    file_path = "lib/test_module.ex"

    File.write!(file_path, """
    defmodule WatcherTestModule do
      def hello, do: :world
    end
    """)

    {:ok, pid} = Francis.Watcher.start_link([])

    # Wait for initial scan
    Process.sleep(200)

    # Modify the file
    File.write!(file_path, """
    defmodule WatcherTestModule do
      def hello, do: :updated
    end
    """)

    # Wait for watcher to detect the change
    Process.sleep(300)

    assert WatcherTestModule.hello() == :updated

    GenServer.stop(pid)
  end

  test "handles deleted files gracefully" do
    File.mkdir_p!("lib")
    file_path = "lib/deleteme.ex"

    File.write!(file_path, """
    defmodule DeleteMeModule do
      def hello, do: :bye
    end
    """)

    {:ok, pid} = Francis.Watcher.start_link([])
    Process.sleep(200)

    # Delete the file
    File.rm!(file_path)

    # Watcher should not crash
    Process.sleep(200)
    assert Process.alive?(pid)

    GenServer.stop(pid)
  end

  test "handles syntax errors gracefully" do
    File.mkdir_p!("lib")
    file_path = "lib/syntax_error.ex"

    File.write!(file_path, """
    defmodule SyntaxOk do
      def hello, do: :ok
    end
    """)

    {:ok, pid} = Francis.Watcher.start_link([])
    Process.sleep(200)

    # Write invalid syntax
    log =
      capture_log(fn ->
        File.write!(file_path, """
        defmodule SyntaxBad do
          def hello, do:
        end
        """)

        Process.sleep(300)
      end)

    assert Process.alive?(pid)
    assert log =~ "Failed to recompile"

    GenServer.stop(pid)
  end

  test "excludes _build and deps directories" do
    File.mkdir_p!("_build/dev/lib")
    File.mkdir_p!("deps/some_dep/lib")
    File.mkdir_p!("lib")

    File.write!("_build/dev/lib/compiled.ex", """
    defmodule ShouldNotCompile do
      def hello, do: :bad
    end
    """)

    File.write!("deps/some_dep/lib/dep.ex", """
    defmodule ShouldNotCompileDep do
      def hello, do: :bad
    end
    """)

    {:ok, pid} = Francis.Watcher.start_link([])
    Process.sleep(200)

    # These modules should NOT have been compiled
    refute Code.ensure_loaded?(ShouldNotCompile)
    refute Code.ensure_loaded?(ShouldNotCompileDep)

    GenServer.stop(pid)
  end
end
