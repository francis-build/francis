defmodule FrancisRuntimeConfigTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  describe "static: false" do
    @tag :tmp_dir
    test "disables static serving even when application config enables it", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "static file")
      restore_app_env(:static)
      Application.put_env(:francis, :static, from: tmp_dir, at: "/")

      served = Support.RouteTester.generate_module(quote(do: unmatched(fn _ -> "fallback" end)))

      disabled =
        Support.RouteTester.generate_module(quote(do: unmatched(fn _ -> "fallback" end)),
          static: false
        )

      capture_log(fn ->
        assert Req.get!("/hello.txt", plug: served, retry: false).body == "static file"
        assert Req.get!("/hello.txt", plug: disabled, retry: false).body == "fallback"
      end)
    end
  end

  describe "PORT environment variable" do
    test "a value that is not a port number fails with a message naming PORT" do
      restore_env("PORT", System.get_env("PORT"))

      for value <- ["abc", "80a", "70000"] do
        System.put_env("PORT", value)

        assert_raise ArgumentError, ~r/PORT environment variable/, fn ->
          Francis.put_env_port([])
        end
      end
    end

    test "surrounding whitespace is ignored" do
      restore_env("PORT", System.get_env("PORT"))
      System.put_env("PORT", " 4001\n")

      assert Francis.put_env_port([]) == [port: 4001]
    end
  end

  describe "error_handler" do
    test "logs the original error when the custom handler itself raises" do
      defmodule RaisingErrorHandler do
        def handle(_conn, _reason), do: raise("handler bug")
      end

      mod =
        Support.RouteTester.generate_module(quote(do: get("/", fn _ -> {:error, :original} end)),
          error_handler: &RaisingErrorHandler.handle/2
        )

      log =
        capture_log(fn ->
          assert Req.get!("/", plug: mod, retry: false).status == 500
        end)

      assert log =~ "handler bug"
      assert log =~ "while handling {:error, :original}"
    end

    test "does not log the both-set warning on every error" do
      defmodule QuietErrorHandler do
        def handle(conn, _reason), do: Plug.Conn.send_resp(conn, 503, "macro")
      end

      restore_app_env(:error_handler)
      Application.put_env(:francis, :error_handler, &QuietErrorHandler.handle/2)

      mod =
        Support.RouteTester.generate_module(quote(do: get("/", fn _ -> {:error, :x} end)),
          error_handler: &QuietErrorHandler.handle/2
        )

      log =
        capture_log(fn ->
          assert Req.get!("/", plug: mod, retry: false).body == "macro"
        end)

      refute log =~ "Both application configuration and macro option"
    end
  end

  defp restore_env(key, nil), do: on_exit(fn -> System.delete_env(key) end)
  defp restore_env(key, value), do: on_exit(fn -> System.put_env(key, value) end)

  defp restore_app_env(key) do
    previous = Application.fetch_env(:francis, key)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:francis, key, value)
        :error -> Application.delete_env(:francis, key)
      end
    end)
  end
end
