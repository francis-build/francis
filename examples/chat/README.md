# Francis WebSocket Chat Example

A simple example demonstrating WebSocket functionality in Francis.

## Prerequisites

Install `wscat` (WebSocket cat) to connect to the server:

```bash
# Using npm
npm install -g wscat

# Using Homebrew (macOS)
brew install wscat

# Or using your system's package manager
```

## Running the Example

1. Start the server:

```bash
cd examples/chat
mix deps.get
mix francis.server
```

The server will start on `http://localhost:4000`

## WebSocket Endpoints

### Echo Server (`/echo`)

Echoes back whatever message you send:

```bash
wscat -c ws://localhost:4000/echo
```

Once connected, type any message and press Enter. The server will echo it back with an "Echo: " prefix.

Example:
```
> Hello, World!
< Echo: Hello, World!
```

### Chat Server with Rooms (`/chat/:room`)

A multi-room chat server where the room name is specified in the URL. Messages are only broadcast to clients in the same room.

Connect to different rooms:

```bash
# Join the "general" room
wscat -c ws://localhost:4000/chat/general

# Join the "dev" room
wscat -c ws://localhost:4000/chat/dev

# Join the "random" room
wscat -c ws://localhost:4000/chat/random
```

Example conversation in the "general" room:
```
> Hello everyone!
< [general] Message received: Hello everyone!
```

## Testing with Multiple Clients and Rooms

You can test the room functionality by opening multiple terminal windows:

**Terminal 1** - Join "general" room:
```bash
wscat -c ws://localhost:4000/chat/general
```

**Terminal 2** - Also join "general" room:
```bash
wscat -c ws://localhost:4000/chat/general
```

**Terminal 3** - Join "dev" room:
```bash
wscat -c ws://localhost:4000/chat/dev
```

When you send a message from Terminal 1:
- Terminal 2 will receive it (same room)
- Terminal 3 will NOT receive it (different room)

This demonstrates that messages are isolated by room.

## Code Explanation

The example demonstrates:

1. **Simple Echo**: The `/echo` endpoint receives a message and replies with an echo
2. **Multi-Room Chat**: The `/chat/:room` endpoint shows how to handle URL parameters and broadcast messages within rooms
3. **Room Registry**: A GenServer (`Chat.RoomRegistry`) tracks connections by room and handles broadcasting
4. **Socket State**: Each connection has a unique `id` that can be used to track connections

### Room Extraction

The room name is extracted from the websocket path (e.g., `/chat/general` → `"general"`):

```elixir
defp extract_room_from_path(path) do
  case String.split(path, "/") do
    ["", "chat", room | _] -> room
    _ -> "default"
  end
end
```

### Room Registry

The `Chat.RoomRegistry` GenServer:
- Tracks all connections organized by room
- Monitors transport processes to detect disconnections
- Broadcasts messages only to clients in the same room
- Automatically cleans up when connections close

The websocket handler receives:
- `message`: The text message from the client
- `socket`: A map containing:
  - `:id` - Unique connection identifier
  - `:transport` - Process that can be used to send messages
  - `:path` - The websocket path (e.g., `/chat/general`)

The handler can return:
- `{:reply, response}` - Sends a response back to the client
- `:noreply` - No response sent

## Next Steps

For a production chat application, you would:

1. Maintain a registry of all connected clients (using `:gproc`, `Registry`, or similar)
2. Store messages in a database or message queue
3. Implement authentication and authorization
4. Add message formatting and validation
5. Handle reconnection and error cases
