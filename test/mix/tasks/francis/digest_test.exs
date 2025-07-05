defmodule Mix.Tasks.Francis.DigestTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @test_assets_dir "test/fixtures/assets"
  @test_output_dir "tmp/digest_test"

  setup do
    File.rm_rf!(@test_output_dir)
    File.mkdir_p!(@test_assets_dir)

    # Create test assets
    File.write!(Path.join(@test_assets_dir, "app.css"), "body { color: red; }")
    File.write!(Path.join(@test_assets_dir, "app.js"), "console.log('hello');")

    # Create subdirectory with assets
    File.mkdir_p!(Path.join(@test_assets_dir, "images"))
    File.write!(Path.join(@test_assets_dir, "images/logo.png"), "fake-png-data")

    on_exit(fn ->
      File.rm_rf!(@test_output_dir)
      File.rm_rf!(@test_assets_dir)
    end)

    :ok
  end

  test "digest task generates digested files" do
    capture_io(fn ->
      Mix.Tasks.Francis.Digest.run([@test_assets_dir, "--output", @test_output_dir])
    end)

    # Check that digested files were created
    files = File.ls!(@test_output_dir)
    assert Enum.any?(files, &String.contains?(&1, "app-"))
    assert Enum.any?(files, &String.contains?(&1, ".css"))
    assert Enum.any?(files, &String.contains?(&1, ".js"))

    # Check that manifest was created
    manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
    assert File.exists?(manifest_path)

    # Check manifest content
    {:ok, manifest} = Francis.Digest.load_manifest(manifest_path)
    assert manifest["version"] == 1
    assert Map.has_key?(manifest["files"], "app.css")
    assert Map.has_key?(manifest["files"], "app.js")
    assert Map.has_key?(manifest["files"], "images/logo.png")
  end

  test "digest task with gzip compression" do
    capture_io(fn ->
      Mix.Tasks.Francis.Digest.run([@test_assets_dir, "--output", @test_output_dir, "--gzip"])
    end)

    # Check that gzipped files were created
    files = File.ls!(@test_output_dir)
    assert Enum.any?(files, &String.ends_with?(&1, ".gz"))

    # Check manifest includes gzip info
    manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
    {:ok, manifest} = Francis.Digest.load_manifest(manifest_path)

    css_info = manifest["files"]["app.css"]
    assert Map.has_key?(css_info, "gzipped")
    assert Map.has_key?(css_info["gzipped"], "size")
  end

  test "digest task without gzip compression" do
    capture_io(fn ->
      Mix.Tasks.Francis.Digest.run([@test_assets_dir, "--output", @test_output_dir, "--no-gzip"])
    end)

    # Check that no gzipped files were created
    files = File.ls!(@test_output_dir)
    refute Enum.any?(files, &String.ends_with?(&1, ".gz"))

    # Check manifest doesn't include gzip info
    manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
    {:ok, manifest} = Francis.Digest.load_manifest(manifest_path)

    css_info = manifest["files"]["app.css"]
    refute Map.has_key?(css_info, "gzipped")
  end

  test "digest task with exclude patterns" do
    # Create files to exclude
    File.write!(Path.join(@test_assets_dir, "README.txt"), "readme content")
    File.write!(Path.join(@test_assets_dir, "config.json"), "{}")

    capture_io(fn ->
      Mix.Tasks.Francis.Digest.run([
        @test_assets_dir,
        "--output",
        @test_output_dir,
        "--exclude",
        "*.txt",
        "--exclude",
        "*.json"
      ])
    end)

    # Check manifest doesn't include excluded files
    manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
    {:ok, manifest} = Francis.Digest.load_manifest(manifest_path)

    refute Map.has_key?(manifest["files"], "README.txt")
    refute Map.has_key?(manifest["files"], "config.json")
    assert Map.has_key?(manifest["files"], "app.css")
  end

  test "digest task handles non-existent input directory" do
    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.Francis.Digest.run(["non_existent_dir"])
      end)

    assert String.contains?(output, "does not exist")
  end

  test "digest produces consistent hashes for same content" do
    # Create two identical files
    File.write!(Path.join(@test_assets_dir, "file1.css"), "body { color: blue; }")
    File.write!(Path.join(@test_assets_dir, "file2.css"), "body { color: blue; }")

    capture_io(fn ->
      Mix.Tasks.Francis.Digest.run([@test_assets_dir, "--output", @test_output_dir])
    end)

    manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
    {:ok, manifest} = Francis.Digest.load_manifest(manifest_path)

    file1_digest = manifest["files"]["file1.css"]["digest"]
    file2_digest = manifest["files"]["file2.css"]["digest"]

    assert file1_digest == file2_digest
  end
end
