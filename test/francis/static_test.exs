defmodule Francis.StaticTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Francis.Digest.Manifest

  @test_manifest_path "tmp/test_cache_manifest.json"
  @test_manifest %{
    "version" => 1,
    "generated_at" => "2023-01-01T00:00:00Z",
    "files" => %{
      "app.css" => %{
        "digest" => "a1b2c3d4",
        "digested_path" => "app-a1b2c3d4.css",
        "size" => 1024,
        "mtime" => "2023-01-01T00:00:00",
        "gzipped" => %{
          "path" => "app-a1b2c3d4.css.gz",
          "size" => 512
        }
      },
      "app.js" => %{
        "digest" => "e5f6g7h8",
        "digested_path" => "app-e5f6g7h8.js",
        "size" => 2048,
        "mtime" => "2023-01-01T00:00:00"
      },
      "images/logo.png" => %{
        "digest" => "i9j0k1l2",
        "digested_path" => "images/logo-i9j0k1l2.png",
        "size" => 4096,
        "mtime" => "2023-01-01T00:00:00"
      }
    }
  }

  setup do
    File.mkdir_p!(Path.dirname(@test_manifest_path))
    File.write!(@test_manifest_path, Jason.encode!(@test_manifest))

    on_exit(fn ->
      File.rm_rf!(@test_manifest_path)
    end)

    :ok
  end

  describe "static_path/2" do
    test "returns digested path for existing asset" do
      assert Francis.Static.static_path("app.css", "/", @test_manifest_path) ==
               "/app-a1b2c3d4.css"

      assert Francis.Static.static_path("app.js", "/", @test_manifest_path) == "/app-e5f6g7h8.js"

      assert Francis.Static.static_path("images/logo.png", "/", @test_manifest_path) ==
               "/images/logo-i9j0k1l2.png"
    end

    test "returns original path for non-existing asset" do
      assert Francis.Static.static_path("nonexistent.css", "/", @test_manifest_path) ==
               "/nonexistent.css"
    end

    test "returns original path when manifest doesn't exist" do
      assert Francis.Static.static_path("nonexistent.json", "/", "missing_cache_manifest.json") ==
               "/nonexistent.json"
    end

    test "prepends base path to digested path" do
      assert Francis.Static.static_path("app.css", "/assets", @test_manifest_path) ==
               "/assets/app-a1b2c3d4.css"

      assert Francis.Static.static_path("nonexistent.css", "/css", @test_manifest_path) ==
               "/css/nonexistent.css"

      assert Francis.Static.static_path("images/logo.png", "/assets", @test_manifest_path) ==
               "/assets/images/logo-i9j0k1l2.png"

      assert Francis.Static.static_path("images/logo.png", "/assets") ==
               "/assets/images/logo.png"
    end

    test "default manifest is used by default" do
      default_manifest_path = "priv/static/cache_manifest.json"
      File.mkdir_p!(Path.dirname(default_manifest_path))
      File.write!(default_manifest_path, Jason.encode!(@test_manifest))

      on_exit(fn ->
        File.rm_rf!(default_manifest_path)
      end)

      assert Francis.Static.static_path("app.css") ==
               "/app-a1b2c3d4.css"

      assert Francis.Static.static_path("app.js") == "/app-e5f6g7h8.js"

      assert Francis.Static.static_path("images/logo.png") ==
               "/images/logo-i9j0k1l2.png"

      assert Francis.Static.static_path("app.css", "/assets") ==
               "/assets/app-a1b2c3d4.css"

      assert Francis.Static.static_path("nonexistent.css", "/css") ==
               "/css/nonexistent.css"

      assert Francis.Static.static_path("images/logo.png", "/assets") ==
               "/assets/images/logo-i9j0k1l2.png"
    end
  end

  describe "exists?/2" do
    test "returns true for existing assets" do
      assert Francis.Static.exists?("app.css", @test_manifest_path) == true
      assert Francis.Static.exists?("app.js", @test_manifest_path) == true
      assert Francis.Static.exists?("images/logo.png", @test_manifest_path) == true
    end

    test "returns false for non-existing assets" do
      assert Francis.Static.exists?("nonexistent.css", @test_manifest_path) == false
    end

    test "returns false when manifest doesn't exist" do
      assert Francis.Static.exists?("app.css", "nonexistent.json") == false
    end
  end

  describe "all/1" do
    test "returns all assets from manifest" do
      assets = Francis.Static.all(@test_manifest_path)

      assert Map.has_key?(assets, "app.css")
      assert Map.has_key?(assets, "app.js")
      assert Map.has_key?(assets, "images/logo.png")

      assert assets["app.css"]["digest"] == "a1b2c3d4"
      assert assets["app.js"]["digest"] == "e5f6g7h8"
      assert assets["images/logo.png"]["digest"] == "i9j0k1l2"
    end

    test "returns empty map when manifest doesn't exist" do
      assert Francis.Static.all("nonexistent.json") == %{}
    end
  end

  describe "cache_control/1" do
    test "returns the cache_control recorded in the manifest" do
      path = "tmp/test_cache_control_manifest.json"
      File.write!(path, Jason.encode!(%{"cache_control" => "public, max-age=60, immutable"}))
      on_exit(fn -> File.rm_rf!(path) end)

      assert Francis.Static.cache_control(path) == "public, max-age=60, immutable"
    end

    test "returns nil when manifest doesn't exist" do
      assert Francis.Static.cache_control("nonexistent.json") == nil
    end
  end

  describe "load_manifest/1 caching" do
    @tag :tmp_dir
    test "caches the decoded manifest and reloads when the file changes", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "cache_manifest.json")
      key = {Francis.Static, path}
      on_exit(fn -> :persistent_term.erase(key) end)

      File.write!(path, Jason.encode!(@test_manifest))
      assert Francis.Static.static_path("app.css", "/", path) == "/app-a1b2c3d4.css"
      assert {_version, %{"files" => _}} = :persistent_term.get(key)

      # A cached entry is served without touching the file contents again
      File.chmod!(path, 0o000)
      assert Francis.Static.static_path("app.css", "/", path) == "/app-a1b2c3d4.css"
      File.chmod!(path, 0o644)

      redigested =
        put_in(@test_manifest, ["files", "app.css", "digested_path"], "app-ffffffffffff.css")

      File.write!(path, Jason.encode!(redigested))
      File.touch!(path, System.os_time(:second) + 10)

      assert Francis.Static.static_path("app.css", "/", path) == "/app-ffffffffffff.css"
    end

    @tag :tmp_dir
    test "reloads a same-size manifest rewritten within the same second", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "cache_manifest.json")
      on_exit(fn -> :persistent_term.erase({Francis.Static, path}) end)

      write = fn digest ->
        Manifest.write(path, [
          %{
            logical_path: "app.css",
            digest: digest,
            digested_path: "app-#{digest}.css",
            size: 1,
            mtime: nil
          }
        ])
      end

      write.("aaaaaaaaaaaa")
      assert Francis.Static.static_path("app.css", "/", path) == "/app-aaaaaaaaaaaa.css"
      %File.Stat{mtime: mtime, size: size} = File.stat!(path, time: :posix)

      write.("bbbbbbbbbbbb")
      # Pin the rewrite to the same second, as a fast redeploy would
      File.touch!(path, mtime)
      assert %File.Stat{mtime: ^mtime, size: ^size} = File.stat!(path, time: :posix)

      assert Francis.Static.static_path("app.css", "/", path) == "/app-bbbbbbbbbbbb.css"
    end
  end
end
