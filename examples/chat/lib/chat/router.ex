defmodule Chat.Router do
  use Francis, static: [from: "priv/static", at: "/assets", gzip: true], bandit_opts: [port: 4000]
  import FrancisHtmx

  get "/", fn _conn ->
    html("""
    <!DOCTYPE html>
    <html>
    <head>
      <title>Francis Chat</title>
      <link rel="stylesheet" href="/assets/css/chat.css">
    </head>
    <body>
      <div class="container">
        <h1>Francis WebSocket Chat</h1>
        <div id="messages"></div>
        <form id="chat-form">
          <input type="text" id="message-input" placeholder="Type a message..." autocomplete="off">
          <button type="submit">Send</button>
        </form>
      </div>
      <script>
        const ws = new WebSocket('ws://localhost:4000/chat');
        const messages = document.getElementById('messages');
        const form = document.getElementById('chat-form');
        const input = document.getElementById('message-input');

        ws.onmessage = (event) => {
          const div = document.createElement('div');
          div.className = 'message';
          div.textContent = event.data;
          messages.appendChild(div);
          messages.scrollTop = messages.scrollHeight;
        };

        form.onsubmit = (e) => {
          e.preventDefault();
          if (input.value.trim()) {
            ws.send(input.value);
            input.value = '';
          }
        };

        ws.onopen = () => {
          // Send join message to register with the room
          ws.send('__join__');
          const div = document.createElement('div');
          div.className = 'system';
          div.textContent = 'Connected to chat';
          messages.appendChild(div);
        };

        ws.onclose = () => {
          const div = document.createElement('div');
          div.className = 'system';
          div.textContent = 'Disconnected from chat';
          messages.appendChild(div);
        };
      </script>
    </body>
    </html>
    """)
  end

  ws "/chat", fn message, socket ->
    case message do
      "__join__" ->
        # Register this client in the room
        Chat.Room.join(socket.transport)
        :noreply

      _ ->
        # Broadcast message to all connected clients
        Chat.Room.broadcast(message)
        :noreply
    end
  end

  unmatched(fn _ -> "Not found" end)
end
