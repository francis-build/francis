defmodule FrancisTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Francis

  describe "get/1" do
    test "returns a response with the given body" do
      handler = quote do: get("/", fn _ -> "test" end)
      mod = Support.RouteTester.generate_module(handler)
      Macro.to_string(mod)

      assert Req.get!("/", plug: mod).body == "test"
    end
  end

  describe "post/1" do
    test "returns a response with the given body" do
      handler = quote do: post("/", fn _ -> "test" end)
      mod = Support.RouteTester.generate_module(handler)

      assert Req.post!("/", plug: mod).body == "test"
    end
  end

  describe "put/1" do
    test "returns a response with the given body" do
      handler = quote do: put("/", fn _ -> "test" end)
      mod = Support.RouteTester.generate_module(handler)

      assert Req.put!("/", plug: mod).body == "test"
    end
  end

  describe "delete/1" do
    test "returns a response with the given body" do
      handler = quote do: delete("/", fn _ -> "test" end)
      mod = Support.RouteTester.generate_module(handler)

      assert Req.delete!("/", plug: mod).body == "test"
    end
  end

  describe "patch/1" do
    test "returns a response with the given body" do
      handler = quote do: patch("/", fn _ -> "test" end)
      mod = Support.RouteTester.generate_module(handler)

      assert Req.patch!("/", plug: mod).body == "test"
    end

    test "setups a HEAD handler" do
      handler = quote do: get("/", fn _ -> "test" end)
      mod = Support.RouteTester.generate_module(handler)

      assert Req.head!("/", plug: mod).status == 200
      assert Req.head!("/", plug: mod).body == ""
    end
  end

  describe "ws/1" do
    setup do
      port = Enum.random(5000..10_000)

      on_exit(fn ->
        # Find the process listening on the port and send SIGINT
        case System.cmd("lsof", ["-ti", ":#{port}"], stderr_to_stdout: true) do
          {pid_str, 0} when pid_str != "" ->
            pid = String.trim(pid_str) |> String.to_integer()
            System.cmd("kill", ["-INT", to_string(pid)])
            Process.sleep(100)

          _ ->
            :ok
        end
      end)

      %{port: port}
    end

    test "returns a response with the given body", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, "test"}, socket ->
            send(unquote(parent_pid), {:handler, "handler_received"})
            send(socket.transport, "late_sent")
            send(socket.transport, %{key: "value"})
            send(socket.transport, [1, 2, 3])
            {:reply, "reply"}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      assert capture_log([level: :info], fn ->
               {:ok, _} = start_supervised(mod)
             end) =~
               "Running #{mod |> Module.split() |> List.last()} with Bandit #{Application.spec(:bandit, :vsn)} at 0.0.0.0:#{port}"

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:handler, "handler_received"}
      assert_receive {:client, "late_sent"}
      assert_receive {:client, %{"key" => "value"}}
      assert_receive {:client, [1, 2, 3]}

      :ok
    end

    @tag :capture_log
    test "does not return a response with the given body", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, "test"}, socket ->
            send(unquote(parent_pid), {:handler, "handler_received"})
            :noreply
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:handler, "handler_received"}
      refute_receive :_, 500

      :ok
    end

    @tag :capture_log
    test "handles :join event", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:handler, :join_received})
              {:reply, %{type: "welcome", id: socket.id}}

            {:received, message}, _socket ->
              {:reply, message}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      _tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Join event should be triggered on connection
      assert_receive {:handler, :join_received}, 1000
      assert_receive {:client, %{"type" => "welcome", "id" => _id}}, 1000

      :ok
    end

    @tag :capture_log
    test "handles {:close, reason} event", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn
            {:close, reason}, _socket ->
              send(unquote(parent_pid), {:handler, {:close, reason}})
              :ok

            {:received, _message}, _socket ->
              :noreply
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Send a close frame to trigger clean WebSocket close
      WebSockex.send_frame(tester_pid, :close)

      # Close event should be triggered
      assert_receive {:handler, {:close, _reason}}, 1000

      :ok
    end

    @tag :capture_log
    test "send to transport is automatically forwarded to client", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, socket ->
            # Messages sent to transport are automatically forwarded
            send(socket.transport, "auto_forward")
            {:reply, message}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "test"})

      # Should receive both the auto-forwarded message and the reply
      assert_receive {:client, "auto_forward"}, 1000
      assert_receive {:client, "test"}, 1000

      :ok
    end

    @tag :capture_log
    test "full lifecycle with pattern matching", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:lifecycle, :join})
              {:reply, %{event: "joined", id: socket.id}}

            {:close, reason}, _socket ->
              send(unquote(parent_pid), {:lifecycle, {:close, reason}})
              :ok

            {:received, message}, socket ->
              send(unquote(parent_pid), {:lifecycle, {:message, message}})
              # Messages sent to transport are auto-forwarded
              send(socket.transport, "broadcast: #{message}")
              {:reply, "echo: #{message}"}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # 1. Join event
      assert_receive {:lifecycle, :join}, 1000
      assert_receive {:client, %{"event" => "joined", "id" => _}}, 1000

      # 2. Send a message
      WebSockex.send_frame(tester_pid, {:text, "hello"})
      assert_receive {:lifecycle, {:message, "hello"}}, 1000
      assert_receive {:client, "echo: hello"}, 1000
      assert_receive {:client, "broadcast: hello"}, 1000

      # 3. Close - send close frame to trigger clean WebSocket close
      WebSockex.send_frame(tester_pid, :close)
      assert_receive {:lifecycle, {:close, _}}, 1000

      :ok
    end

    @tag :capture_log
    test "works with only received handler", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      # Simple handler without lifecycle events
      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            send(unquote(parent_pid), {:handler, message})
            {:reply, "got: #{message}"}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "simple"})
      assert_receive {:handler, "simple"}, 1000
      assert_receive {:client, "got: simple"}, 1000

      :ok
    end

    @tag :capture_log
    test "handles :ok return value same as :noreply", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn
            {:close, _reason}, _socket ->
              :ok

            {:received, message}, _socket ->
              send(unquote(parent_pid), {:handler, message})
              :ok
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:handler, "test"}, 1000
      # Should not receive any reply
      refute_receive {:client, _}, 500

      :ok
    end

    @tag :capture_log
    test "handles missing :join pattern match gracefully", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      # Handler without :join clause - should not crash
      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            send(unquote(parent_pid), {:handler, message})
            {:reply, "got: #{message}"}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Connection should succeed even without :join handler
      # Should be able to send messages
      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:handler, "test"}, 1000
      assert_receive {:client, "got: test"}, 1000

      :ok
    end

    @tag :capture_log
    test "handles missing {:close, reason} pattern match gracefully", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      # Handler with :join but without {:close, reason} clause - should not crash on close
      handler =
        quote do
          ws(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:handler, :join_received})
              {:reply, %{type: "welcome", id: socket.id}}

            {:received, message}, _socket ->
              send(unquote(parent_pid), {:handler, message})
              {:reply, "got: #{message}"}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Join should work
      assert_receive {:handler, :join_received}, 1000
      assert_receive {:client, %{"type" => "welcome", "id" => _id}}, 1000

      # Send a message
      WebSockex.send_frame(tester_pid, {:text, "hello"})
      assert_receive {:handler, "hello"}, 1000
      assert_receive {:client, "got: hello"}, 1000

      # Close should not crash even without {:close, reason} handler
      WebSockex.send_frame(tester_pid, :close)
      # Give it a moment to process the close
      Process.sleep(100)
      # Should not receive any error messages
      refute_receive {:handler, {:close, _}}, 500

      :ok
    end

    @tag :capture_log
    test "responds to client ping with pong", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, message}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Send ping frame from client
      WebSockex.send_frame(tester_pid, {:ping, "test_payload"})

      # Should receive pong response automatically
      assert_receive {:client, {:pong, "test_payload"}}, 1000

      :ok
    end

    @tag :capture_log
    test "sends ping frames at configured heartbeat interval", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      # Use a short interval for testing (500ms)
      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, message}
          end, heartbeat_interval: 500)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Wait for first ping (should arrive within 500ms + some buffer)
      assert_receive {:client, {:ping, _payload}}, 1000

      # Wait for second ping to confirm it's recurring
      assert_receive {:client, {:ping, _payload}}, 1000

      # Clean up
      WebSockex.send_frame(tester_pid, :close)

      :ok
    end

    @tag :capture_log
    test "handles pong frames from client", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, message}
          end, heartbeat_interval: 500)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Wait for server to send ping
      assert_receive {:client, {:ping, _payload}}, 1000

      # Send pong back (WebSockex should handle this automatically, but we can also send manually)
      # The server should handle it gracefully without errors
      WebSockex.send_frame(tester_pid, {:pong, <<>>})

      # Connection should still work
      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:client, "test"}, 1000

      :ok
    end

    @tag :capture_log
    test "disables heartbeat when heartbeat_interval is nil", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, message}
          end, heartbeat_interval: nil)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Wait a bit to ensure no ping frames are sent
      Process.sleep(1000)

      # Should not receive any ping frames
      refute_receive {:client, {:ping, _payload}}, 500

      # But regular messages should still work
      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:client, "test"}, 1000

      :ok
    end

    @tag :capture_log
    test "uses default heartbeat interval when not specified", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      # No heartbeat_interval option - should use default (30_000ms)
      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, message}
          end)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # With default 30s interval, we should receive a ping within 31 seconds
      # But for testing purposes, we'll just verify the connection works
      # and that ping frames will eventually be sent (we can't wait 30s in tests)
      WebSockex.send_frame(tester_pid, {:text, "test"})
      assert_receive {:client, "test"}, 1000

      # Verify no immediate ping (since default is 30s)
      refute_receive {:client, {:ping, _payload}}, 1000

      :ok
    end

    @tag :capture_log
    test "ping/pong frames work alongside regular messages", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, "echo: #{message}"}
          end, heartbeat_interval: 500)
        end

      bandit_opts = [port: port]
      mod = Support.RouteTester.generate_module(handler, bandit_opts: bandit_opts)

      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Send regular message
      WebSockex.send_frame(tester_pid, {:text, "hello"})
      assert_receive {:client, "echo: hello"}, 1000

      # Send ping
      WebSockex.send_frame(tester_pid, {:ping, "ping_payload"})
      assert_receive {:client, {:pong, "ping_payload"}}, 1000

      # Receive server ping
      assert_receive {:client, {:ping, _payload}}, 1000

      # Send another regular message - should still work
      WebSockex.send_frame(tester_pid, {:text, "world"})
      assert_receive {:client, "echo: world"}, 1000

      :ok
    end
  end

  describe "redirect/2" do
    test "redirects to the given path" do
      handler =
        quote do
          get("/", fn conn -> redirect(conn, "/new_path") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod, redirect: false)

      assert response.status == 302
      assert response.headers["location"] == ["/new_path"]
    end

    test "redirects to the given URL" do
      handler =
        quote do
          get("/", fn conn -> redirect(conn, "http://example.com/new_path") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod, redirect: false)

      assert response.status == 302
      assert response.headers["location"] == ["http://example.com/new_path"]
    end
  end

  describe "redirect/3" do
    test "redirects to the given path with custom status" do
      handler =
        quote do
          get("/", fn conn -> redirect(conn, 301, "/new_path") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod, redirect: false)

      assert response.status == 301
      assert response.headers["location"] == ["/new_path"]
    end

    test "redirects to the given URL with custom status" do
      handler =
        quote do
          get("/", fn conn -> redirect(conn, 301, "http://example.com/new_path") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod, redirect: false)

      assert response.status == 301
      assert response.headers["location"] == ["http://example.com/new_path"]
    end
  end

  describe "json/2" do
    test "returns a JSON response with 200 status" do
      handler =
        quote do
          get("/", fn conn -> json(conn, %{message: "success"}) end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 200
      assert response.headers["content-type"] == ["application/json; charset=utf-8"]
      assert response.body == %{"message" => "success"}
    end

    test "returns a JSON response with list data" do
      handler =
        quote do
          get("/", fn conn -> json(conn, [1, 2, 3]) end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 200
      assert response.headers["content-type"] == ["application/json; charset=utf-8"]
      assert response.body == [1, 2, 3]
    end
  end

  describe "json/3" do
    test "returns a JSON response with custom status" do
      handler =
        quote do
          get("/", fn conn -> json(conn, 201, %{id: 123, created: true}) end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 201
      assert response.headers["content-type"] == ["application/json; charset=utf-8"]
      assert response.body == %{"id" => 123, "created" => true}
    end
  end

  describe "text/2" do
    test "returns a text response with 200 status" do
      handler =
        quote do
          get("/", fn conn -> text(conn, "Hello, World!") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 200
      assert response.headers["content-type"] == ["text/plain; charset=utf-8"]
      assert response.body == "Hello, World!"
    end
  end

  describe "text/3" do
    test "returns a text response with custom status" do
      handler =
        quote do
          get("/", fn conn -> text(conn, 201, "Resource created successfully") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 201
      assert response.headers["content-type"] == ["text/plain; charset=utf-8"]
      assert response.body == "Resource created successfully"
    end
  end

  describe "html/2" do
    test "returns an HTML response with 200 status" do
      handler =
        quote do
          get("/", fn conn -> html(conn, "<h1>Hello, World!</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 200
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
      assert response.body == "<h1>Hello, World!</h1>"
    end
  end

  describe "html/3" do
    test "returns an HTML response with custom status" do
      handler =
        quote do
          get("/", fn conn -> html(conn, 201, "<h1>Hello, World!</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.status == 201
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
      assert response.body == "<h1>Hello, World!</h1>"
    end
  end

  describe "unmatched/1" do
    test "returns a response with the given body" do
      handler = quote do: unmatched(fn _ -> "test" end)

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.body == "test"
      assert response.status == 404
    end
  end

  describe "plug usage" do
    test "uses given plug by given order" do
      handler =
        quote do
          plug(Support.PlugTester, to_assign: "plug1")
          plug(Support.PlugTester, to_assign: "plug2")
          get("/", fn %{assigns: %{plug_assgined: plug_assgined}} -> plug_assgined end)
        end

      mod = Support.RouteTester.generate_module(handler)
      assert Req.get!("/", plug: mod).body == ["plug1", "plug2"]
    end
  end

  describe "non matching routes without unmatched handler" do
    test "returns an log error with the method and path of the failed route" do
      mod = Support.RouteTester.generate_module(quote do: get("/", fn _ -> "test" end))

      assert capture_log(fn -> Req.get!("/not_here", plug: mod) end) =~
               "Failed to match route: GET /not_here"
    end
  end

  describe "static configuration" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      static_dir = Path.join(tmp_dir, "static")
      File.mkdir_p!(static_dir)

      css_path = Path.join(static_dir, "app.css")
      File.write!(css_path, "body { color: #333; }\n")

      on_exit(fn -> File.rm(css_path) end)
      %{static_dir: static_dir}
    end

    test "returns a static file", %{static_dir: static_dir} do
      handler = quote do: unmatched(fn _ -> "" end)

      mod =
        Support.RouteTester.generate_module(handler,
          static: [at: "/", from: static_dir]
        )

      assert Req.get!("/app.css", plug: mod).status == 200
    end

    test "returns a 404 for non-existing static file", %{static_dir: static_dir} do
      handler = quote do: unmatched(fn _ -> "" end)

      mod =
        Support.RouteTester.generate_module(handler,
          static: [at: "/", from: static_dir]
        )

      assert Req.get!("/not_found.txt", plug: mod).status == 404
    end
  end

  describe "error_handler option" do
    test "invokes custom error handler on error" do
      handler =
        quote do
          get("/", fn _ -> {:error, :fail} end)
        end

      defmodule ErrorHandler do
        import Plug.Conn
        def error(conn, {:error, :fail}), do: send_resp(conn, 502, "custom error")
      end

      mod = Support.RouteTester.generate_module(handler, error_handler: &ErrorHandler.error/2)

      response = Req.get!("/", plug: mod, retry: false)
      assert response.status == 502
      assert response.body == "custom error"
    end

    test "invokes default error handler on error" do
      handler =
        quote do
          get("/", fn _ -> {:error, :fail} end)
        end

      mod = Support.RouteTester.generate_module(handler)

      log =
        capture_log(fn ->
          response = Req.get!("/", plug: mod, retry: false)
          assert response.status == 500
          assert response.body == "Internal Server Error"
        end)

      assert log =~ "Unhandled error: {:error, :fail}"
    end

    test "handles exceptions with custom error handler" do
      handler =
        quote do
          get("/", fn _ -> raise "test exception" end)
        end

      defmodule CustomErrorHandler do
        import Plug.Conn

        def handle_errors(conn, _assigns) do
          send_resp(conn, 500, "Custom Error Handler: Exception occurred")
        end
      end

      mod =
        Support.RouteTester.generate_module(handler,
          error_handler: &CustomErrorHandler.handle_errors/2
        )

      response = Req.get!("/", plug: mod, retry: false)
      assert response.status == 500
      assert response.body == "Custom Error Handler: Exception occurred"
    end

    test "handles exceptions with default error handler" do
      handler =
        quote do
          get("/", fn _ -> raise "test exception" end)
        end

      mod = Support.RouteTester.generate_module(handler)

      log =
        capture_log(fn ->
          response = Req.get!("/", plug: mod, retry: false)

          assert response.status == 500
          assert response.body == "Internal Server Error"
        end)

      assert log =~ "Unhandled error: %RuntimeError{message: \"test exception\"}"
    end

    test "handles unmatched errors gracefully" do
      handler =
        quote do
          get("/", fn _ -> {:error, :fail} end)
        end

      defmodule ErrorHandlerUnmatched do
        import Plug.Conn
        def error(conn, {:error, :no_match}), do: send_resp(conn, 404, "custom not found error")
      end

      log =
        capture_log(fn ->
          mod =
            Support.RouteTester.generate_module(handler,
              error_handler: &ErrorHandlerUnmatched.error/2
            )

          response = Req.get!("/", plug: mod, retry: false)
          assert response.status == 500
          assert response.body == "Internal Server Error"
        end)

      assert log =~ "Unhandled error:"
    end
  end

  describe "get_configuration/3" do
    setup do
      # Clean up any config before and after
      on_exit(fn ->
        Application.delete_env(:francis, :test_key)
      end)

      :ok
    end

    test "returns the option value if present and no app config" do
      assert Francis.get_configuration(:test_key, [test_key: "opt_val"], "default") == "opt_val"
    end

    test "returns the app config value if no option present" do
      Application.put_env(:francis, :test_key, "app_val")
      assert Francis.get_configuration(:test_key, [], "default") == "app_val"
    end

    test "returns the option value and logs warning if both option and app config present" do
      Application.put_env(:francis, :test_key, "app_val")

      log =
        capture_log(fn ->
          assert Francis.get_configuration(:test_key, [test_key: "opt_val"], "default") ==
                   "opt_val"
        end)

      assert log =~
               "Both application configuration and macro option provided for test_key. Using macro option."
    end

    test "returns the default if neither option nor app config present" do
      assert Francis.get_configuration(:test_key, [], "default") == "default"
    end
  end
end
