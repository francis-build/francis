defmodule Mix.Tasks.Francis.ReleaseTest do
  # These tests need to run synchronously because they rely on the current working directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Francis.Release

  @tmp_dir Path.join(System.tmp_dir!(), "francis_release_test")
  @dockerfile Path.join(@tmp_dir, "Dockerfile")
  @dockerignore Path.join(@tmp_dir, ".dockerignore")

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

  test "generates Dockerfile and .dockerignore with default options" do
    output =
      capture_io(fn ->
        Release.run([])
      end)
      |> strip_ansi()

    assert output =~ "* creating Dockerfile"
    assert output =~ "* creating .dockerignore"

    assert File.exists?(@dockerfile)
    assert File.exists?(@dockerignore)
    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "EXPOSE 4000"
    assert dockerfile =~ "mix release"
    assert dockerfile =~ "CMD [\"bin/francis\", \"start\"]"
    dockerignore = File.read!(@dockerignore)
    assert dockerignore =~ ".git"
    assert dockerignore =~ "_build"
  end

  test "generates Dockerfile with custom port" do
    capture_io(fn ->
      Release.run(["--port", "1234"])
    end)

    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "EXPOSE 1234"
  end

  test "generates Dockerfile with custom port using alias" do
    capture_io(fn ->
      Release.run(["-p", "5678"])
    end)

    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "EXPOSE 5678"
  end

  test "generates Dockerfile with custom elixir and otp versions" do
    capture_io(fn ->
      Release.run(["--elixir-version", "1.17.0", "--otp-version", "26.2.1"])
    end)

    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "ARG ELIXIR_VERSION=1.17.0"
    assert dockerfile =~ "ARG OTP_VERSION=26.2.1"

    assert dockerfile =~
             "hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
  end

  test "generates Dockerfile with only custom elixir version" do
    capture_io(fn ->
      Release.run(["--elixir-version", "1.16.2"])
    end)

    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "ARG ELIXIR_VERSION=1.16.2"
    assert dockerfile =~ "ARG OTP_VERSION=27.3.4"
  end

  test "generates Dockerfile with only custom otp version" do
    capture_io(fn ->
      Release.run(["--otp-version", "25.3.0"])
    end)

    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "ARG ELIXIR_VERSION=1.18.4"
    assert dockerfile =~ "ARG OTP_VERSION=25.3.0"
  end

  test "does not raise on unknown options and ignores them" do
    capture_io(fn ->
      Release.run(["--unknown", "foo"])
    end)

    assert File.exists?(@dockerfile)
    assert File.exists?(@dockerignore)
  end

  test "raises on invalid elixir version format" do
    assert_raise Mix.Error, ~r/Invalid Elixir version format/, fn ->
      capture_io(fn ->
        Release.run(["--elixir-version", "1.18\"; RUN malicious #"])
      end)
    end
  end

  test "raises on invalid otp version format" do
    assert_raise Mix.Error, ~r/Invalid OTP version format/, fn ->
      capture_io(fn ->
        Release.run(["--otp-version", "bad-version"])
      end)
    end
  end

  test "accepts valid two-segment version" do
    capture_io(fn ->
      Release.run(["--elixir-version", "1.18"])
    end)

    dockerfile = File.read!(@dockerfile)
    assert dockerfile =~ "ARG ELIXIR_VERSION=1.18"
  end

  defp strip_ansi(str) do
    Regex.replace(~r/\e\[[\d;]*m/, str, "")
  end
end
