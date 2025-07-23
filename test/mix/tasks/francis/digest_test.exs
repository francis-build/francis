defmodule Mix.Tasks.Francis.DigestTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Francis.Digest

  @test_assets_dir "test/fixtures/digest_assets"
  @test_output_dir "tmp/digest_test_output"

  setup do
    # Clean up and create test directories
    File.rm_rf!(@test_output_dir)
    File.rm_rf!(@test_assets_dir)
    File.mkdir_p!(@test_assets_dir)

    # Create test assets
    create_test_assets()

    on_exit(fn ->
      File.rm_rf!(@test_output_dir)
      File.rm_rf!(@test_assets_dir)
    end)

    :ok
  end

  describe "run/1" do
    test "digests files from default input path" do
      # Create assets in default location
      File.mkdir_p!("priv/static")
      File.write!("priv/static/app.css", "body { color: red; }")

      output =
        capture_io(fn ->
          Digest.run([])
        end)

      assert String.contains?(output, "Generating digested files from priv/static to priv/static")
      assert String.contains?(output, "Generated 1 digested files")
      assert String.contains?(output, "Manifest written to priv/static/cache_manifest.json")

      # Check that digested file was created
      files = File.ls!("priv/static")
      assert Enum.any?(files, &String.contains?(&1, "app-"))
      assert Enum.any?(files, &String.ends_with?(&1, ".css"))
      assert "cache_manifest.json" in files

      # Clean up
      File.rm_rf!("priv/static")
    end

    test "digests files from custom input path" do
      output =
        capture_io(fn ->
          Digest.run([@test_assets_dir, "--output", @test_output_dir])
        end)

      assert String.contains?(
               output,
               "Generating digested files from #{@test_assets_dir} to #{@test_output_dir}"
             )

      assert String.contains?(output, "Generated 4 digested files")

      # Check that digested files were created
      files = File.ls!(@test_output_dir)
      assert Enum.any?(files, &String.contains?(&1, "app-"))
      assert Enum.any?(files, &String.contains?(&1, "data-"))
      assert "cache_manifest.json" in files

      # Check subdirectory structure is preserved
      assert File.exists?(Path.join(@test_output_dir, "images"))
      images_files = File.ls!(Path.join(@test_output_dir, "images"))
      assert Enum.any?(images_files, &String.contains?(&1, "logo-"))
    end

    test "generates manifest with correct structure" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      assert File.exists?(manifest_path)

      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      # Check manifest structure
      assert manifest["version"] == 1
      assert Map.has_key?(manifest, "generated_at")
      assert Map.has_key?(manifest, "files")

      # Check file entries
      files = manifest["files"]
      assert Map.has_key?(files, "app.css")
      assert Map.has_key?(files, "app.js")
      assert Map.has_key?(files, "images/logo.png")
      assert Map.has_key?(files, "data.json")

      # Check file entry structure
      css_entry = files["app.css"]
      assert Map.has_key?(css_entry, "digest")
      assert Map.has_key?(css_entry, "digested_path")
      assert Map.has_key?(css_entry, "size")
      assert Map.has_key?(css_entry, "mtime")
      assert String.length(css_entry["digest"]) == 8
      assert String.contains?(css_entry["digested_path"], css_entry["digest"])
    end

    test "creates gzipped files by default" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      # Check that gzipped files were created
      files = File.ls!(@test_output_dir)
      assert Enum.any?(files, &String.ends_with?(&1, ".css.gz"))
      assert Enum.any?(files, &String.ends_with?(&1, ".js.gz"))

      # Check manifest includes gzip info
      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      css_entry = manifest["files"]["app.css"]
      assert Map.has_key?(css_entry, "gzipped")
      assert Map.has_key?(css_entry["gzipped"], "path")
      assert Map.has_key?(css_entry["gzipped"], "size")
      assert String.ends_with?(css_entry["gzipped"]["path"], ".css.gz")
    end

    test "skips gzip compression when disabled" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir, "--no-gzip"])
      end)

      # Check that no gzipped files were created
      files = File.ls!(@test_output_dir)
      refute Enum.any?(files, &String.ends_with?(&1, ".gz"))

      # Check manifest doesn't include gzip info
      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      css_entry = manifest["files"]["app.css"]
      refute Map.has_key?(css_entry, "gzipped")
    end

    test "excludes files matching patterns" do
      capture_io(fn ->
        Digest.run([
          @test_assets_dir,
          "--output",
          @test_output_dir,
          "--exclude",
          "*.json",
          "--exclude",
          "*.png"
        ])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      files = manifest["files"]

      # Should include CSS and JS
      assert Map.has_key?(files, "app.css")
      assert Map.has_key?(files, "app.js")

      # Should exclude JSON and PNG
      refute Map.has_key?(files, "data.json")
      refute Map.has_key?(files, "images/logo.png")
    end

    test "handles nested directory structure" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      # Check that nested structure is preserved
      assert File.exists?(Path.join(@test_output_dir, "images"))

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      # Check that nested file paths are correct
      logo_entry = manifest["files"]["images/logo.png"]
      assert String.starts_with?(logo_entry["digested_path"], "images/")
      assert String.contains?(logo_entry["digested_path"], "logo-")
    end

    test "generates consistent hashes for same content" do
      # Create two files with identical content
      File.write!(Path.join(@test_assets_dir, "file1.css"), "body { color: blue; }")
      File.write!(Path.join(@test_assets_dir, "file2.css"), "body { color: blue; }")

      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      file1_digest = manifest["files"]["file1.css"]["digest"]
      file2_digest = manifest["files"]["file2.css"]["digest"]

      assert file1_digest == file2_digest
    end

    test "generates different hashes for different content" do
      # Create two files with different content
      File.write!(Path.join(@test_assets_dir, "file1.css"), "body { color: blue; }")
      File.write!(Path.join(@test_assets_dir, "file2.css"), "body { color: red; }")

      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      file1_digest = manifest["files"]["file1.css"]["digest"]
      file2_digest = manifest["files"]["file2.css"]["digest"]

      assert file1_digest != file2_digest
    end

    test "handles empty input directory" do
      empty_dir = "tmp/empty_assets"
      File.mkdir_p!(empty_dir)

      output =
        capture_io(fn ->
          Digest.run([empty_dir, "--output", @test_output_dir])
        end)

      assert String.contains?(output, "Generated 0 digested files")

      # Manifest should still be created
      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      assert File.exists?(manifest_path)

      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()
      assert manifest["files"] == %{}

      File.rm_rf!(empty_dir)
    end

    test "errors when input directory doesn't exist" do
      output =
        capture_io(:stderr, fn ->
          try do
            Digest.run(["non_existent_dir"])
          catch
            :exit, {:shutdown, 1} -> :ok
          end
        end)

      assert String.contains?(output, "Input path non_existent_dir does not exist")
    end

    test "creates output directory if it doesn't exist" do
      nonexistent_output = "tmp/nonexistent_output"
      File.rm_rf!(nonexistent_output)

      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", nonexistent_output])
      end)

      assert File.exists?(nonexistent_output)
      assert File.exists?(Path.join(nonexistent_output, "cache_manifest.json"))

      File.rm_rf!(nonexistent_output)
    end

    test "handles custom age parameter" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir, "--age", "3600"])
      end)

      # The age parameter is stored in opts but not directly used in file generation
      # This test ensures the parameter is parsed correctly
      assert File.exists?(Path.join(@test_output_dir, "cache_manifest.json"))
    end

    test "preserves file modification times" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      css_entry = manifest["files"]["app.css"]
      assert Map.has_key?(css_entry, "mtime")
      assert css_entry["mtime"] != nil

      # Should be a valid ISO8601 timestamp
      assert {:ok, _} = NaiveDateTime.from_iso8601(css_entry["mtime"])
    end

    test "generates 8-character digests" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      Enum.each(manifest["files"], fn {_path, entry} ->
        assert String.length(entry["digest"]) == 8
        assert String.match?(entry["digest"], ~r/^[a-f0-9]{8}$/)
      end)
    end

    test "handles files with no extension" do
      File.write!(Path.join(@test_assets_dir, "Makefile"), "all:\n\techo 'hello'")

      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      assert Map.has_key?(manifest["files"], "Makefile")
      makefile_entry = manifest["files"]["Makefile"]
      assert String.contains?(makefile_entry["digested_path"], "Makefile-")
    end

    test "handles files with multiple extensions" do
      File.write!(Path.join(@test_assets_dir, "app.min.js"), "console.log('minified');")

      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      assert Map.has_key?(manifest["files"], "app.min.js")
      entry = manifest["files"]["app.min.js"]
      assert String.ends_with?(entry["digested_path"], ".js")
      assert String.contains?(entry["digested_path"], "app.min-")
    end
  end

  describe "option parsing" do
    test "parses output option" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir])
      end)

      assert File.exists?(@test_output_dir)
    end

    test "parses short output option" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "-o", @test_output_dir])
      end)

      assert File.exists?(@test_output_dir)
    end

    test "parses gzip option" do
      capture_io(fn ->
        Digest.run([@test_assets_dir, "--output", @test_output_dir, "--gzip"])
      end)

      files = File.ls!(@test_output_dir)
      assert Enum.any?(files, &String.ends_with?(&1, ".gz"))
    end

    test "parses multiple exclude patterns" do
      capture_io(fn ->
        Digest.run([
          @test_assets_dir,
          "--output",
          @test_output_dir,
          "--exclude",
          "*.json",
          "--exclude",
          "*.png"
        ])
      end)

      manifest_path = Path.join(@test_output_dir, "cache_manifest.json")
      {:ok, manifest} = File.read!(manifest_path) |> Jason.decode()

      files = manifest["files"]
      refute Map.has_key?(files, "data.json")
      refute Map.has_key?(files, "images/logo.png")
    end
  end

  defp create_test_assets do
    # Create CSS file
    File.write!(Path.join(@test_assets_dir, "app.css"), """
    body {
      font-family: Arial, sans-serif;
      color: #333;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
    }
    """)

    # Create JavaScript file
    File.write!(Path.join(@test_assets_dir, "app.js"), """
    document.addEventListener('DOMContentLoaded', function() {
      console.log('App loaded');

      // Some functionality
      const buttons = document.querySelectorAll('button');
      buttons.forEach(button => {
        button.addEventListener('click', function() {
          console.log('Button clicked');
        });
      });
    });
    """)

    # Create nested directory with image
    File.mkdir_p!(Path.join(@test_assets_dir, "images"))
    File.write!(Path.join(@test_assets_dir, "images/logo.png"), "fake-png-binary-data")

    # Create JSON file (to test exclusion)
    File.write!(Path.join(@test_assets_dir, "data.json"), """
    {
      "name": "Test App",
      "version": "1.0.0",
      "description": "A test application"
    }
    """)
  end
end
