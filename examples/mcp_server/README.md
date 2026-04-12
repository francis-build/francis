# MCP Server (SSE Transport)

A minimal [Model Context Protocol](https://modelcontextprotocol.io/) server
built with Francis SSE, demonstrating the SSE transport.

## Running

```bash
cd examples/mcp_server
mix deps.get
mix run --no-halt
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/sse` | SSE stream — server pushes JSON-RPC responses |
| `POST` | `/message?session_id=ID` | Client sends JSON-RPC requests |

## Testing with curl

```bash
# Terminal 1 – open the SSE stream
curl -N http://localhost:4000/sse

# Terminal 2 – initialize (replace <SESSION_ID> with the id from terminal 1)
curl -X POST "http://localhost:4000/message?session_id=<SESSION_ID>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"demo","version":"0.1.0"},"capabilities":{}}}'

# List tools
curl -X POST "http://localhost:4000/message?session_id=<SESSION_ID>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# Call the echo tool
curl -X POST "http://localhost:4000/message?session_id=<SESSION_ID>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"message":"Hello MCP!"}}}'

# Call the add tool
curl -X POST "http://localhost:4000/message?session_id=<SESSION_ID>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"add","arguments":{"a":21,"b":21}}}'
```

## Available Tools

- **echo** – Echoes back the provided message
- **add** – Adds two numbers together
