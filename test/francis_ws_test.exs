defmodule WsDeepHelper do
  @moduledoc false
  def only_ok(:ok), do: "ok"
end

defmodule WsDelegatingSocket do
  @moduledoc false
  # Only handles client frames; :join, {:info, _} and {:close, _} must count as unmatched.
  def handle({:received, msg}, socket) do
    send(socket.transport, "forwarded:" <> msg)
    {:reply, msg}
  end
end

defmodule FrancisWsTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  @moduletag :e2e

  defmodule Deep.Helper do
    def greet(name), do: "hello " <> name
  end

  setup do
    %{port: Enum.random(26_001..29_999)}
  end

  defp connect(port, path) do
    start_supervised!(
      {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: self()}}
    )
  end

  describe "ws/3 handler compilation" do
    @tag :capture_log
    test "handler can use aliases from the router module", %{port: port} do
      handler =
        quote do
          alias FrancisWsTest.Deep.Helper

          ws("alias", fn {:received, name}, _socket -> {:reply, Helper.greet(name)} end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      tester = connect(port, "alias")
      WebSockex.send_frame(tester, {:text, "francis"})

      assert_receive {:client, "hello francis"}, 2000
    end

    @tag :capture_log
    test "routes named after Francis modules do not replace them", %{port: port} do
      handler =
        quote do
          ws("static", fn {:received, msg}, _socket -> {:reply, msg} end)
          ws("websocket", fn {:received, msg}, _socket -> {:reply, "ws:" <> msg} end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      assert Francis.Static.static_path("app.css", "/", "missing.json") == "/app.css"

      tester = connect(port, "websocket")
      WebSockex.send_frame(tester, {:text, "x"})

      assert_receive {:client, "ws:x"}, 2000
    end

    @tag :capture_log
    test "routers with the same ws path keep their own handlers", %{port: port} do
      router_a =
        Support.RouteTester.generate_module(
          quote(do: ws("same", fn {:received, _}, _ -> {:reply, "a"} end)),
          bandit_opts: [port: port]
        )

      router_b =
        Support.RouteTester.generate_module(
          quote(do: ws("same", fn {:received, _}, _ -> {:reply, "b"} end)),
          bandit_opts: [port: port + 1]
        )

      start_supervised!(router_a)
      start_supervised!(router_b)

      WebSockex.send_frame(connect(port, "same"), {:text, "?"})
      assert_receive {:client, "a"}, 2000

      tester_b =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port + 1}/same", parent_pid: self()}},
          id: :tester_b
        )

      WebSockex.send_frame(tester_b, {:text, "?"})
      assert_receive {:client, "b"}, 2000
    end
  end

  describe "ws/3 process messages" do
    @tag :capture_log
    test "messages sent to the transport reach an {:info, msg} clause", %{port: port} do
      parent = self()

      handler =
        quote do
          ws("info", fn
            :join, socket ->
              send(unquote(parent), {:transport, socket.transport})
              :noreply

            {:info, {:new_message, body}}, _socket ->
              {:reply, %{type: "message", body: body}}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      connect(port, "info")
      assert_receive {:transport, transport}, 2000

      send(transport, {:new_message, "hi"})
      assert_receive {:client, %{"type" => "message", "body" => "hi"}}, 2000
    end

    @tag :capture_log
    test "unhandled non-frame messages are dropped without closing the socket", %{port: port} do
      parent = self()

      handler =
        quote do
          ws("drop", fn
            :join, socket ->
              send(unquote(parent), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      tester = connect(port, "drop")
      assert_receive {:transport, transport}, 2000

      send(transport, {:some, :tuple})
      send(transport, :an_atom)
      send(transport, "still forwarded")
      assert_receive {:client, "still forwarded"}, 2000

      WebSockex.send_frame(tester, {:text, "alive"})
      assert_receive {:client, "alive"}, 2000
    end
  end

  describe "ws/3 optional events" do
    test "a FunctionClauseError raised inside the join handler is not swallowed", %{port: port} do
      handler =
        quote do
          ws("deep", fn
            :join, _socket -> {:reply, WsDeepHelper.only_ok(:not_ok)}
            {:received, msg}, _socket -> {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      Process.flag(:trap_exit, true)

      log =
        capture_log(fn ->
          {:ok, tester} =
            Support.WsTester.start_link(%{url: "ws://localhost:#{port}/deep", parent_pid: self()})

          assert_receive {:EXIT, ^tester, _reason}, 2000
          Process.sleep(300)
        end)

      assert log =~ "FunctionClauseError"
      assert log =~ "WsDeepHelper.only_ok/1"
    end

    @tag :capture_log
    test "a handler that delegates to another function may leave events unmatched", %{
      port: port
    } do
      handler =
        quote do
          ws("delegate", fn event, socket -> WsDelegatingSocket.handle(event, socket) end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      tester = connect(port, "delegate")
      WebSockex.send_frame(tester, {:text, "hi"})

      assert_receive {:client, "hi"}, 2000
      assert_receive {:client, "forwarded:hi"}, 2000
    end
  end
end
