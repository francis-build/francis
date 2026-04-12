defmodule McpServer.Handler do
  @moduledoc """
  Handles MCP JSON-RPC requests and returns JSON-RPC responses.

  Implements a minimal subset of the MCP spec:
  - `initialize` – handshake with capabilities
  - `notifications/initialized` – client acknowledgment (no response)
  - `tools/list` – list available tools
  - `tools/call` – invoke a tool
  """

  @server_info %{name: "francis-mcp-server", version: "0.1.0"}
  @protocol_version "2025-03-26"

  def handle_request(%{"method" => "initialize", "id" => id}, _socket) do
    jsonrpc_response(id, %{
      protocolVersion: @protocol_version,
      serverInfo: @server_info,
      capabilities: %{
        tools: %{listChanged: false}
      }
    })
  end

  def handle_request(%{"method" => "notifications/initialized"}, _socket) do
    # Notification – no response needed, but we still need to return something
    # that the SSE handler can skip
    :ok
  end

  def handle_request(%{"method" => "tools/list", "id" => id}, _socket) do
    jsonrpc_response(id, %{
      tools: [
        %{
          name: "echo",
          description: "Echoes back the provided message",
          inputSchema: %{
            type: "object",
            properties: %{
              message: %{type: "string", description: "The message to echo back"}
            },
            required: ["message"]
          }
        },
        %{
          name: "add",
          description: "Adds two numbers together",
          inputSchema: %{
            type: "object",
            properties: %{
              a: %{type: "number", description: "First number"},
              b: %{type: "number", description: "Second number"}
            },
            required: ["a", "b"]
          }
        }
      ]
    })
  end

  def handle_request(
        %{"method" => "tools/call", "id" => id, "params" => %{"name" => name} = params},
        _socket
      ) do
    args = Map.get(params, "arguments", %{})
    call_tool(name, args, id)
  end

  def handle_request(%{"method" => method, "id" => id}, _socket) do
    jsonrpc_error(id, -32601, "Method not found: #{method}")
  end

  def handle_request(_request, _socket) do
    # Malformed request or notification we don't handle
    :ok
  end

  # ── Tool implementations ──────────────────────────────────────────────────

  defp call_tool("echo", %{"message" => message}, id) do
    jsonrpc_response(id, %{
      content: [%{type: "text", text: message}]
    })
  end

  defp call_tool("add", %{"a" => a, "b" => b}, id) when is_number(a) and is_number(b) do
    jsonrpc_response(id, %{
      content: [%{type: "text", text: "#{a + b}"}]
    })
  end

  defp call_tool(name, _args, id) do
    jsonrpc_error(id, -32602, "Unknown tool or invalid arguments: #{name}")
  end

  # ── JSON-RPC helpers ───────────────────────────────────────────────────────

  defp jsonrpc_response(id, result) do
    %{jsonrpc: "2.0", id: id, result: result}
  end

  defp jsonrpc_error(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
