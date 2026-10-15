defmodule FrancisConfigTest do
  use ExUnit.Case

  @moduletag :e2e

  # `bandit_opts` is documented in the README as a `config/config.exs` key, but
  # unlike every other key it used to be read straight from the `use Francis`
  # macro opts, so application config was silently ignored. It went unnoticed
  # because the documented example uses port 4000, which is also Bandit's
  # default — and it breaks runtime-injected ports (e.g. ex_tauri's `PORT`),
  # where the value cannot be known at compile time.
  @tag :capture_log
  test "bandit_opts from application config are honoured when the macro sets none" do
    port = Enum.random(20_001..22_000)

    previous = Application.get_env(:francis, :bandit_opts)
    Application.put_env(:francis, :bandit_opts, port: port)

    on_exit(fn ->
      if previous do
        Application.put_env(:francis, :bandit_opts, previous)
      else
        Application.delete_env(:francis, :bandit_opts)
      end
    end)

    mod = Module.concat(Elixir, "ConfigTestMod#{System.unique_integer([:positive])}")

    content =
      quote do
        use Francis

        get("/", fn _ -> "configured" end)
      end

    Module.create(mod, content, Macro.Env.location(__ENV__))
    start_supervised!(mod)

    assert Req.get!("http://localhost:#{port}/").body == "configured"
  end

  @tag :capture_log
  test "macro bandit_opts still win over application config" do
    macro_port = Enum.random(22_001..24_000)
    config_port = Enum.random(24_001..26_000)

    previous = Application.get_env(:francis, :bandit_opts)
    Application.put_env(:francis, :bandit_opts, port: config_port)

    on_exit(fn ->
      if previous do
        Application.put_env(:francis, :bandit_opts, previous)
      else
        Application.delete_env(:francis, :bandit_opts)
      end
    end)

    mod =
      Support.RouteTester.generate_module(
        quote do
          get("/", fn _ -> "macro" end)
        end,
        bandit_opts: [port: macro_port]
      )

    start_supervised!(mod)

    assert Req.get!("http://localhost:#{macro_port}/").body == "macro"
  end

  @tag :capture_log
  test "PORT env var is used when no port is configured" do
    port = Enum.random(20_001..22_000)
    restore_env("PORT", System.get_env("PORT"))
    System.put_env("PORT", to_string(port))

    mod = Support.RouteTester.generate_module(quote(do: get("/", fn _ -> "from env" end)))
    start_supervised!(mod)

    assert Req.get!("http://localhost:#{port}/").body == "from env"
  end

  test "an explicit port wins over the PORT env var" do
    restore_env("PORT", System.get_env("PORT"))
    System.put_env("PORT", "1")

    assert Francis.put_env_port(port: 4321) == [port: 4321]
    assert Francis.put_env_port([]) == [port: 1]
  end

  test "error_handler from application config is used at runtime" do
    defmodule ConfigErrorHandler do
      def handle(conn, {:error, :boom}), do: Plug.Conn.send_resp(conn, 418, "from config")
    end

    restore_app_env(:error_handler)
    Application.put_env(:francis, :error_handler, &ConfigErrorHandler.handle/2)

    mod = Support.RouteTester.generate_module(quote(do: get("/", fn _ -> {:error, :boom} end)))

    response = Req.get!("/", plug: mod, retry: false)
    assert response.status == 418
    assert response.body == "from config"
  end

  test "static: false disables static serving even when app config sets it" do
    restore_app_env(:static)
    Application.put_env(:francis, :static, from: "priv/static", at: "/")

    assert Francis.resolve_configuration(:static, false, [from: "x"], []) == false
    assert Francis.get_configuration(:static, [static: false], []) == false
  end

  describe "errors raised before a route runs" do
    @tag :capture_log
    test "malformed JSON renders the 400 page instead of 500" do
      port = Enum.random(22_001..24_000)

      mod =
        Support.RouteTester.generate_module(quote(do: post("/", fn conn -> conn.body_params end)),
          bandit_opts: [port: port]
        )

      start_supervised!(mod)

      response =
        Req.post!("http://localhost:#{port}/",
          retry: false,
          body: "{not json",
          headers: [{"content-type", "application/json"}]
        )

      assert response.status == 400
      assert response.body =~ "Bad Request"
    end

    @tag :capture_log
    test "custom error handlers receive the exception, not Plug's wrapper map" do
      port = Enum.random(24_001..26_000)

      defmodule PipelineErrorHandler do
        def handle(conn, %Plug.Parsers.ParseError{}),
          do: Plug.Conn.send_resp(conn, 422, "bad json")
      end

      mod =
        Support.RouteTester.generate_module(quote(do: post("/", fn conn -> conn.body_params end)),
          error_handler: &PipelineErrorHandler.handle/2,
          bandit_opts: [port: port]
        )

      start_supervised!(mod)

      response =
        Req.post!("http://localhost:#{port}/",
          retry: false,
          body: "{not json",
          headers: [{"content-type", "application/json"}]
        )

      assert response.status == 422
      assert response.body == "bad json"
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
