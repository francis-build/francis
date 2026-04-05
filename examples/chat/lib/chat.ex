defmodule Chat do
  use Francis, bandit_opts: [port: 4000]

  require Logger

  plug(Francis.Plug.SecureHeaders)
  plug(Francis.Plug.CSP, directives: %{"connect-src" => "'self' ws://localhost:4000"})

  ws("/chat/:room", fn
    :join, %{params: %{"room" => room}, id: id} = _socket ->
      Logger.info("Client #{id} joined room '#{room}'")

      {:reply,
       %{type: "welcome", message: "You are connected to room #{room}", room: room, id: id}}

    {:close, reason}, %{params: %{"room" => room}, id: id} = _socket ->
      Logger.info("Client #{id} left room '#{room}': #{inspect(reason)}")
      :ok

    {:received, message}, %{params: %{"room" => room}} = _socket ->
      Logger.info("Chat message in room '#{room}': #{inspect(message)}")
      escaped = Francis.HTML.escape(message)
      {:reply, "[#{room}] #{escaped}"}
  end)

  get(
    "/",
    fn conn ->
      html(conn, """
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>Francis WebSocket Chat Example</title>
        </head>
        <body>
          <h1>Francis WebSocket Chat Example</h1>
          <p>Connect to the websocket endpoints using wscat:</p>
          <ul>
            <li><code>websocat ws://localhost:4000/chat/:room</code> - Connect to a chat room</li>
          </ul>
        </body>
      </html>
      """)
    end
  )

  unmatched(fn _ -> "Not found" end)
end
