defmodule McpServer do
  @moduledoc """
  A minimal MCP (Model Context Protocol) server built with Francis SSE.

  Demonstrates how to use the `sse/3` macro to implement the MCP SSE transport:
  - `GET  /sse`      – SSE stream (server → client)
  - `POST /message`  – JSON-RPC endpoint (client → server)

  ## How it works

  1. A client opens an SSE connection to `/sse`.
  2. The server sends an `endpoint` event with the POST URL.
  3. The client sends JSON-RPC requests to `/message?session_id=<id>`.
  4. The server processes the request and pushes the response over the SSE stream.

  ## Running

      cd examples/mcp_server
      mix deps.get
      mix run --no-halt

  ## Testing with curl

      # Terminal 1 – open the SSE stream
      curl -N http://localhost:4000/sse

      # Terminal 2 – send an initialize request (use the session_id from terminal 1)
      curl -X POST http://localhost:4000/message?session_id=<SESSION_ID> \\
        -H "Content-Type: application/json" \\
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"demo","version":"0.1.0"},"capabilities":{}}}'

      # Send a tools/list request
      curl -X POST http://localhost:4000/message?session_id=<SESSION_ID> \\
        -H "Content-Type: application/json" \\
        -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

      # Call the echo tool
      curl -X POST http://localhost:4000/message?session_id=<SESSION_ID> \\
        -H "Content-Type: application/json" \\
        -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"message":"Hello MCP!"}}}'
  """

  use Francis, bandit_opts: [port: 4000]

  require Logger

  # ── SSE Endpoint ───────────────────────────────────────────────────────────

  sse("/sse", fn
    :join, socket ->
      # Register this SSE connection so the POST endpoint can find it
      McpServer.Sessions.register(socket.id, socket.transport)

      Logger.info("MCP session #{socket.id} connected")

      # The MCP SSE transport spec requires sending the POST endpoint URL
      # as the first event with event type "endpoint"
      {:reply, %{event: "endpoint", data: "/message?session_id=#{socket.id}"}}

    {:close, _reason}, socket ->
      McpServer.Sessions.unregister(socket.id)
      Logger.info("MCP session #{socket.id} disconnected")
      :ok

    {:received, request}, socket ->
      # Messages arrive here from the POST endpoint via send(transport, msg)
      case McpServer.Handler.handle_request(request, socket) do
        :ok -> :noreply
        response -> {:reply, response}
      end
  end)

  # ── JSON-RPC POST Endpoint ────────────────────────────────────────────────

  post("/message", fn conn ->
    session_id = conn.params["session_id"]

    case McpServer.Sessions.lookup(session_id) do
      {:ok, transport} ->
        # Forward the JSON-RPC request to the SSE process
        send(transport, conn.body_params)
        json(conn, 202, %{status: "accepted"})

      :error ->
        json(conn, 404, %{error: "unknown session"})
    end
  end)

  # ── Index Page ─────────────────────────────────────────────────────────────

  get("/", fn conn ->
    html(conn, """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Francis MCP Server (SSE)</title>
      </head>
      <body>
        <h1>Francis MCP Server</h1>
        <p>This is a minimal <strong>Model Context Protocol</strong> server using SSE transport.</p>
        <h2>Endpoints</h2>
        <ul>
          <li><code>GET /sse</code> – SSE stream (server → client)</li>
          <li><code>POST /message?session_id=ID</code> – JSON-RPC (client → server)</li>
        </ul>
        <h2>Available tools</h2>
        <ul>
          <li><code>echo</code> – Echoes back a message</li>
          <li><code>add</code> – Adds two numbers</li>
        </ul>
      </body>
    </html>
    """)
  end)

  unmatched(fn _ -> "Not found" end)
end
