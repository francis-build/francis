defmodule Chat do
  use Francis, bandit_opts: [port: 4000]

  require Logger

  ws("/chat/:room", fn
    :join, %{params: %{"room" => room}, id: id} = _socket ->
      Logger.info("Client #{id} joined room '#{room}'")
      {:reply, %{type: "welcome", message: "You are connected to room #{room}", room: room, id: id}}

    {:close, reason}, %{params: %{"room" => room}, id: id} = _socket ->
      Logger.info("Client #{id} left room '#{room}': #{inspect(reason)}")
      :ok

    {:received, message}, %{params: %{"room" => room}} = _socket ->
      Logger.info("Chat message in room '#{room}': #{inspect(message)}")
      {:reply, "[#{room}] #{message}"}
  end)

  get("/", fn _ ->
    """
    <html>
      <head><title>Francis WebSocket Chat Example</title></head>
      <body>
        <h1>Francis WebSocket Chat Example</h1>
        <p>Connect to the websocket endpoints using wscat:</p>
        <ul>
          <li><code>websocat ws://localhost:4000/chat/:room</code> - Connect to a chat room by specifying the room name</li>
        </ul>
      </body>
    </html>
    """
  end)

  unmatched(fn _ -> "Not found" end)
end
