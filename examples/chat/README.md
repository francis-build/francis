# Francis WebSocket Chat Example

A minimal websocket chat application built with Francis to showcase how easy it is to build real-time applications.

## Features

- Real-time messaging using WebSockets
- Broadcasts messages to all connected clients
- Clean, minimal UI
- Less than 100 lines of code total

## Running the Example

```bash
# Install dependencies
mix deps.get

# Start the server
mix run --no-halt
```

Then open http://localhost:4000 in multiple browser tabs to test the chat.

## How It Works

The example demonstrates:

1. **WebSocket Route** - Using Francis's `ws/2` macro to define a WebSocket endpoint
2. **Broadcasting** - A simple Agent-based room that tracks connected clients and broadcasts messages
3. **Static Assets** - Serving CSS from `priv/static`
4. **Minimal UI** - Plain HTML with vanilla JavaScript for WebSocket client

## Key Files

- `lib/chat/router.ex` - Defines the HTTP and WebSocket routes
- `lib/chat/room.ex` - Manages connected clients and message broadcasting
- `lib/chat.ex` - Application supervisor
- `priv/static/css/chat.css` - Minimal styling

## Code Highlights

The entire WebSocket handler is just a few lines:

```elixir
ws "/chat", fn message, socket ->
  # Join the room when first message is received
  Chat.Room.join(socket.transport)

  # Broadcast message to all connected clients
  Chat.Room.broadcast(message)

  :noreply
end
```

That's it! Francis handles all the WebSocket protocol details for you.
