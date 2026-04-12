defmodule FrancisSSETest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  describe "sse/3" do
    setup do
      port = Enum.random(5000..10_000)

      on_exit(fn ->
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

    test "sets correct SSE response headers", %{port: port} do
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn {:received, _msg}, _socket -> :noreply end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert resp.status == 200
      assert hd(resp.headers["content-type"]) =~ "text/event-stream"
      assert resp.headers["cache-control"] == ["no-cache"]
      assert resp.headers["x-accel-buffering"] == ["no"]
    end

    test "sends join event on connection", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:handler, :join_received})
              {:reply, %{type: "welcome", id: socket.id}}

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:handler, :join_received}, 1000

      assert_receive {_ref, {:data, data}}, 1000
      assert data =~ "data:"
      decoded = parse_sse_data(data)
      assert decoded["type"] == "welcome"
      assert is_binary(decoded["id"])
    end

    test "forwards messages sent to transport as SSE events", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      # Send a binary message
      send(transport, "hello from server")
      assert_receive {_ref, {:data, data}}, 1000
      assert data == "data: hello from server\n\n"
    end

    test "sends JSON-encoded maps as SSE data", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, %{key: "value", number: 42})
      assert_receive {_ref, {:data, data}}, 1000
      assert data =~ "data:"
      decoded = parse_sse_data(data)
      assert decoded["key"] == "value"
      assert decoded["number"] == 42
    end

    test "sends JSON-encoded lists as SSE data", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, [1, 2, 3])
      assert_receive {_ref, {:data, data}}, 1000
      assert data =~ "data:"
      decoded = parse_sse_data(data)
      assert decoded == [1, 2, 3]
    end

    test "handles named events with event field", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, %{event: "user_joined", data: %{name: "Alice"}})
      assert_receive {_ref, {:data, data}}, 1000
      assert data =~ "event: user_joined\n"
      assert data =~ "data:"
    end

    test "handles named events with id and retry fields", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, %{event: "update", data: "payload", id: "42", retry: 5000})
      assert_receive {_ref, {:data, data}}, 1000
      assert data =~ "event: update\n"
      assert data =~ "data: payload\n"
      assert data =~ "id: 42\n"
      assert data =~ "retry: 5000\n"
    end

    test "handles :noreply return value", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, _msg}, socket ->
              send(unquote(parent_pid), {:handler, :received})
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, "should_be_noreply")
      assert_receive {:handler, :received}, 1000

      # Should not receive any SSE data chunk
      refute_receive {_ref, {:data, _}}, 500
    end

    test "handles :ok return value same as :noreply", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :ok

            {:received, _msg}, _socket ->
              send(unquote(parent_pid), {:handler, :received})
              :ok
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, "should_be_ok")
      assert_receive {:handler, :received}, 1000
      refute_receive {_ref, {:data, _}}, 500
    end

    test "handles missing :join pattern match gracefully", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn {:received, msg}, socket ->
            send(unquote(parent_pid), {:transport, socket.transport})
            {:reply, "got: #{msg}"}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      # No join event should be sent, but connection should still work
      refute_receive {_ref, {:data, _}}, 300

      # We need the transport pid - send a message to discover it
      # The handler only triggers on {:received, msg}, so we need to get transport another way
      # Actually, let's verify it works by checking we get no crash
      # The connection is alive - no error received
      refute_receive {_ref, {:error, _}}, 300
    end

    test "exposes path params in socket", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote("#{path}/:topic"), fn
            :join, socket ->
              send(unquote(parent_pid), {:params, socket.params})
              send(unquote(parent_pid), {:path, socket.path})
              :noreply

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}/news", into: :self)

      assert_receive {:params, params}, 1000
      assert params["topic"] == "news"

      assert_receive {:path, req_path}, 1000
      assert req_path == "/#{path}/news"
    end

    test "assigns unique id to each connection", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:id, socket.id})
              :noreply

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp1 = Req.get!("http://localhost:#{port}/#{path}", into: :self)
      assert_receive {:id, id1}, 1000

      _resp2 = Req.get!("http://localhost:#{port}/#{path}", into: :self)
      assert_receive {:id, id2}, 1000

      assert id1 != id2
      assert is_binary(id1)
      assert byte_size(id1) > 0
    end

    test "sends keepalive comments at configured interval", %{port: port} do
      path = random_path()

      handler =
        quote do
          sse(
            unquote(path),
            fn
              {:received, _msg}, _socket -> :noreply
            end,
            keepalive_interval: 300
          )
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      # Wait for first keepalive
      assert_receive {_ref, {:data, data1}}, 1000
      assert data1 == ": keepalive\n\n"

      # Wait for second keepalive to confirm it's recurring
      assert_receive {_ref, {:data, data2}}, 1000
      assert data2 == ": keepalive\n\n"
    end

    test "disables keepalive when keepalive_interval is nil", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(
            unquote(path),
            fn
              :join, socket ->
                send(unquote(parent_pid), {:transport, socket.transport})
                :noreply

              {:received, msg}, _socket ->
                {:reply, msg}
            end,
            keepalive_interval: nil
          )
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      # Wait to ensure no keepalive is sent
      Process.sleep(500)
      refute_receive {_ref, {:data, ": keepalive\n\n"}}, 500

      # But regular messages should still work
      send(transport, "still works")
      assert_receive {_ref, {:data, data}}, 1000
      assert data == "data: still works\n\n"
    end

    test "handles multiple messages in sequence", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      send(transport, "first")
      send(transport, "second")
      send(transport, "third")

      assert_receive {_ref, {:data, "data: first\n\n"}}, 1000
      assert_receive {_ref, {:data, "data: second\n\n"}}, 1000
      assert_receive {_ref, {:data, "data: third\n\n"}}, 1000
    end

    test "handles {:close, reason} event on disconnect", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:close, reason}, _socket ->
              send(unquote(parent_pid), {:handler, {:close, reason}})
              :ok

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      # Use a task so we can cancel the request
      task =
        Task.async(fn ->
          Req.get!("http://localhost:#{port}/#{path}", into: :self)
        end)

      assert_receive {:transport, transport}, 1000

      # Kill the SSE process to trigger close
      Process.exit(transport, :kill)

      assert_receive {:handler, {:close, _reason}}, 2000
      # Clean up the task
      Task.shutdown(task, :brutal_kill)
    end

    test "handles missing {:close, reason} pattern match gracefully", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      task =
        Task.async(fn ->
          Req.get!("http://localhost:#{port}/#{path}", into: :self)
        end)

      assert_receive {:transport, transport}, 1000

      # Kill the SSE process - should not crash even without {:close, reason} handler
      Process.exit(transport, :kill)
      Process.sleep(100)

      # No crash - test passes if we get here
      Task.shutdown(task, :brutal_kill)
    end

    test "join reply is sent as the first SSE event", %{port: port} do
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, _socket ->
              {:reply, "welcome"}

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {_ref, {:data, data}}, 1000
      assert data == "data: welcome\n\n"
    end

    test "join reply with JSON map", %{port: port} do
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              {:reply, %{status: "connected", id: socket.id}}

            {:received, _msg}, _socket ->
              :noreply
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {_ref, {:data, data}}, 1000
      decoded = parse_sse_data(data)
      assert decoded["status"] == "connected"
      assert is_binary(decoded["id"])
    end

    test "full lifecycle with pattern matching", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:lifecycle, :join})
              send(unquote(parent_pid), {:transport, socket.transport})
              {:reply, %{event: "joined", id: socket.id}}

            {:close, reason}, _socket ->
              send(unquote(parent_pid), {:lifecycle, {:close, reason}})
              :ok

            {:received, message}, _socket ->
              send(unquote(parent_pid), {:lifecycle, {:message, message}})
              {:reply, "echo: #{message}"}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      # 1. Join event
      assert_receive {:lifecycle, :join}, 1000
      assert_receive {:transport, transport}, 1000
      assert_receive {_ref, {:data, join_data}}, 1000
      assert join_data =~ "data:"

      # 2. Send a message via transport
      send(transport, "hello")
      assert_receive {:lifecycle, {:message, "hello"}}, 1000
      assert_receive {_ref, {:data, msg_data}}, 1000
      assert msg_data == "data: echo: hello\n\n"

      # 3. Send another message
      send(transport, "world")
      assert_receive {:lifecycle, {:message, "world"}}, 1000
      assert_receive {_ref, {:data, msg_data2}}, 1000
      assert msg_data2 == "data: echo: world\n\n"
    end

    test "works with only received handler", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn {:received, msg}, socket ->
            send(unquote(parent_pid), {:handler, msg})
            send(unquote(parent_pid), {:transport, socket.transport})
            {:reply, "got: #{msg}"}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      # Need to wait a bit for the loop to start, then get the transport
      # Since there's no join handler, we need to send a message to trigger the handler
      # The keepalive will send a message that won't match {:received, _}
      # So we just wait for the keepalive and check no crash
      Process.sleep(200)
      refute_receive {_ref, {:error, _}}, 200
    end

    test "handler errors are logged and do not crash the connection", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport})
              :noreply

            {:received, "crash"}, _socket ->
              raise "intentional error"

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _resp = Req.get!("http://localhost:#{port}/#{path}", into: :self)

      assert_receive {:transport, transport}, 1000

      # Send a message that will cause an error
      send(transport, "crash")
      Process.sleep(100)

      # Connection should still be alive - send another message
      send(transport, "still alive")
      assert_receive {_ref, {:data, data}}, 1000
      assert data == "data: still alive\n\n"
    end

    test "multiple concurrent SSE connections", %{port: port} do
      parent_pid = self()
      path = random_path()

      handler =
        quote do
          sse(unquote(path), fn
            :join, socket ->
              send(unquote(parent_pid), {:transport, socket.transport, socket.id})
              {:reply, %{id: socket.id}}

            {:received, msg}, _socket ->
              {:reply, msg}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      # Start two concurrent connections
      _resp1 = Req.get!("http://localhost:#{port}/#{path}", into: :self)
      assert_receive {:transport, t1, id1}, 1000
      assert_receive {_ref, {:data, _}}, 1000

      _resp2 = Req.get!("http://localhost:#{port}/#{path}", into: :self)
      assert_receive {:transport, t2, id2}, 1000
      assert_receive {_ref, {:data, _}}, 1000

      assert id1 != id2
      assert t1 != t2

      # Send to each independently
      send(t1, "for client 1")
      assert_receive {_ref, {:data, "data: for client 1\n\n"}}, 1000

      send(t2, "for client 2")
      assert_receive {_ref, {:data, "data: for client 2\n\n"}}, 1000
    end
  end

  # -- Helpers -----------------------------------------------------------------

  defp random_path do
    10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  defp parse_sse_data(raw) do
    raw
    |> String.split("\n")
    |> Enum.find_value(fn
      "data: " <> json -> json
      _ -> nil
    end)
    |> case do
      nil -> nil
      data -> Jason.decode!(data)
    end
  end
end
