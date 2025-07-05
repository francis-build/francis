defmodule Francis.StaticTest do
  use ExUnit.Case, async: true

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
end
