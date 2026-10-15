---
name: francis-thinking
description: Invoke on ANY Francis task — routes, WebSocket, SSE, streaming, real-time, chat, Plug middleware, auth, CORS, static assets, deploy, Dockerfile, JSON API, uploads, sessions, `use Francis`, `ws/2`, `sse/2`, `socket.transport`, `Francis.Plug`, `Francis.HTML`, `Francis.Static`, `bandit_opts`, or contributing to the framework itself. Contains the unified event model, all API details, gotchas, and red flags.
license: MIT
metadata:
  author: francis-build
  version: "1.0.0"
---

<EXTREMELY-IMPORTANT>
Invoke this skill BEFORE doing ANYTHING else on a Francis task — including exploring the codebase.

Francis macros generate hidden modules at compile time. Exploring first means you won't know what to look for, and you'll miss critical safety rules (HTML escaping, SSE directionality, redirect safety).
</EXTREMELY-IMPORTANT>

## The Rule

```
Francis task → Read this skill FIRST → Then explore → Then write code
```

Even "where is the route defined?" needs this skill first — `get/ws/sse` macros generate hidden modules; grepping for the handler won't find them.

---

## STOP: The One Footgun That Causes XSS

```elixir
# WRONG — html/2 does NOT escape. XSS vulnerability:
html(conn, "<p>Hello #{user_input}</p>")

# WRONG — safe_html/2 escapes the ENTIRE string, including your <p> tags:
safe_html(conn, "<p>Hello #{user_input}</p>")
# renders: &lt;p&gt;Hello user input&lt;/p&gt;  — raw text, not HTML

# RIGHT — escape only the interpolation, keep your trusted markup:
html(conn, "<p>Hello #{Francis.HTML.escape(user_input)}</p>")

# RIGHT — safe_html/2 is for rendering untrusted content as escaped plain text:
safe_html(conn, user_input)
```

---

## The Unified Event Model

All three transports share the same shape:

```
HTTP:   fn conn         -> response
WS/SSE: fn event, socket -> reply
```

**Return value dispatch (HTTP handlers):**

| Return value | What Francis sends |
|---|---|
| Binary string | 200, no content-type set (use `text/2` to force `text/plain`) |
| Map or list | 200 JSON (`application/json`) |
| `Plug.Conn` struct | Sent as-is (full control) |
| `{:error, reason}` | Calls error handler |

Status is 200 for route macros, 404 for `unmatched/1`. Return `Plug.Conn` to override either.

**Reply value dispatch (WS/SSE handlers):**

| Return value | What Francis sends |
|---|---|
| `{:reply, binary}` | Text frame / SSE `data:` line |
| `{:reply, map \| list}` | JSON-encoded text frame / SSE `data:` line |
| `{:reply, {type, payload}}` | Typed WS frame: `type` in `:text`, `:binary`, `:ping`, `:pong` |
| `:noreply` or `:ok` | Nothing sent |

`{:reply, {:binary, bytes}}` is the only way to send binary WebSocket frames.

---

## HTTP Routes

```elixir
defmodule MyApp do
  use Francis

  get("/", fn _conn -> "hello" end)
  get("/users/:id", fn conn -> "user #{conn.params["id"]}" end)
  post("/users", fn conn -> conn.body_params end)
  put("/users/:id", fn conn -> %{updated: conn.params["id"]} end)
  delete("/users/:id", fn conn -> %{deleted: conn.params["id"]} end)
  patch("/users/:id", fn conn -> conn.body_params end)

  unmatched(fn _conn -> "not found" end)
end
```

**`unmatched/1` must be declared last** — it shadows any routes declared after it.

**Accessing data:**
- Path params + query string: `conn.params["id"]`
- Request body: `conn.body_params` — requires a matching `content-type` header (`application/json`, `application/x-www-form-urlencoded`, `multipart/form-data`). Without it, `body_params` is `%{}`. Body params are also merged into `conn.params` after parsing.

**Response helpers** (auto-imported via `Francis.ResponseHandlers`):
```elixir
json(conn, %{ok: true})
json(conn, 201, %{id: 1})
text(conn, "hello")
html(conn, "<h1>Trusted static HTML only</h1>")
safe_html(conn, user_input)         # escapes the whole string as plain text
safe_html(conn, 201, user_input)
redirect(conn, "/new")              # relative paths only
redirect(conn, 301, "/new")
```

**HEAD requests** — no `head/2` macro. `Plug.Head` (installed by default) converts HEAD requests to GET automatically.

---

## WebSockets

```elixir
ws("/chat/:room", fn
  :join, socket ->
    {:reply, %{type: "welcome", room: socket.params["room"]}}

  {:received, msg}, socket ->
    {:reply, "[#{socket.params["room"]}] #{msg}"}

  {:close, _reason}, _socket ->
    :ok
end)

ws("/live", handler_fn, heartbeat_interval: 10_000, timeout: 120_000)
```

**Events:**
- `:join` — client connected
- `{:received, message}` — client sent a text message over the wire
- `{:close, reason}` — connection closed

**`:join`, `{:close, _}` and `{:info, _}` are optional** — succeed silently if the handler has no clause for them (also when it delegates unchanged, e.g. `fn e, s -> MyApp.Socket.handle(e, s) end`). A `FunctionClauseError` raised deeper in your code is a real error and is not swallowed. Easy to lose cleanup logic on close.

**Socket state:**
```elixir
%{
  id: "64-character hex string (32 random bytes)",
  transport: pid,
  path: "/chat/general",
  params: %{"room" => "general"}
}
```

**`send(socket.transport, msg)` for WS is delivered to the handler as `{:info, msg}` first.** If the handler has no `{:info, _}` clause, frame-shaped messages (binary, map, list, `{type, payload}`) go straight to the client and anything else is logged and dropped. They never reach `{:received, _}`, which only gets client frames. Store `socket.transport` to broadcast from other processes.

**Options:**
- `:heartbeat_interval` (default: 30_000 ms) — ping frames; `nil` to disable
- `:timeout` (default: 60_000 ms) — idle connection timeout
- `:max_frame_size` (default: 65_536 bytes) — memory protection

Handlers are compiled inline in the router, so aliases, imports and module attributes from the router work inside `ws`/`sse` handlers.

---

## Server-Sent Events (SSE)

SSE is **server→client only**. The SSE client has no upstream channel. All events the handler receives come from other processes via `send(socket.transport, msg)`.

```elixir
sse("/events", fn
  :join, socket ->
    {:reply, %{event: "connected", data: %{id: socket.id}}}

  {:received, msg}, socket ->
    {:reply, msg}

  {:close, _reason}, _socket ->
    :ok
end)

sse("/stream", handler_fn, keepalive_interval: 30_000)
```

**`send(socket.transport, msg)` for SSE routes through the handler's `{:received, msg}` clause** — WS uses `{:info, msg}` for the same thing, because its `{:received, _}` is taken by client frames. You can transform or filter messages before they reach the client. Multi-line data is split into one `data:` line per line, and line breaks are stripped from `event`/`id`, so relayed text cannot inject events.

Real close reasons include `:chunk_failed` (client disconnected) and `:keepalive_failed`. Use `{:close, _}` to clean up subscriptions.

**SSE event formats:**
```elixir
{:reply, "plain text"}
# => data: plain text\n\n

{:reply, %{status: "ok"}}
# => data: {"status":"ok"}\n\n

{:reply, %{event: "user_joined", data: %{name: "Alice"}, id: "42", retry: 5000}}
# => id: 42\nevent: user_joined\ndata: {...}\nretry: 5000\n\n
```

**Options:**
- `:keepalive_interval` (default: 15_000 ms) — comment line to keep connection alive; `nil` to disable

**WS vs SSE — critical difference:**

| | WS `send(socket.transport, msg)` | SSE `send(socket.transport, msg)` |
|---|---|---|
| Routes through handler? | Yes — `{:info, msg}`; forwarded as-is if unmatched | Yes — delivered to `{:received, msg}` |
| `{:received, _}` source | Client text frames over the wire | Other processes only |

---

## Plug Composition

Plugs run **before route handlers**, in declaration order. Auth plugs must come before route macros.

```elixir
defmodule MyApp do
  use Francis
  import Plug.BasicAuth

  plug Francis.Plug.SecureHeaders
  plug Francis.Plug.CSP
  plug :basic_auth, username: "admin", password: "secret"

  get("/", fn _ -> "authenticated" end)
end
```

**Router forwarding** for scoped middleware:
```elixir
defmodule Public do
  use Francis
  get("/", fn _ -> "public" end)
end

defmodule Private do
  use Francis
  import Plug.BasicAuth
  plug :basic_auth, username: "admin", password: "secret"
  get("/", fn _ -> "private" end)
end

defmodule Main do
  use Francis
  forward("/public", to: Public)
  forward("/private", to: Private)
  unmatched(fn _ -> "not found" end)
end
```

`forward/2` and `plug/1-2` are from `Plug.Router`/`Plug.Builder` — see Plug docs for full options.

---

## Security

```elixir
plug Francis.Plug.SecureHeaders
plug Francis.Plug.SecureHeaders, headers: %{"x-frame-options" => "SAMEORIGIN"}

plug Francis.Plug.CSP
plug Francis.Plug.CSP,
  directives: %{"script-src" => "'self' https://cdn.example.com"},
  report_only: true
```

`redirect/2` and `redirect/3` accept relative paths only. Absolute URLs raise `ArgumentError`. Protocol-relative URLs (`//evil.com`) are converted to `/`.

---

## Error Handling

```elixir
defmodule MyApp do
  use Francis, error_handler: &__MODULE__.handle_error/2

  get("/risky", fn _ -> {:error, :unavailable} end)

  def handle_error(conn, {:error, :unavailable}),
    do: Plug.Conn.send_resp(conn, 503, "Service unavailable")

  def handle_error(conn, _),
    do: Plug.Conn.send_resp(conn, 500, "Internal error")
end
```

The error handler receives `{:error, reason}` tuples, exceptions (raised in routes or earlier in the pipeline, e.g. `Plug.Parsers.ParseError`), or `{kind, reason}` for throws and exits. The default page uses the exception status (`plug_status`): 400 for malformed JSON, 500 otherwise. If the error handler itself raises, Francis logs both errors and renders the default page.

---

## Configuration

Keys valid in both `use Francis` opts and `config.exs`: `bandit_opts`, `static`, `log_level`, `error_handler`, `parser`.

`dev: true` is **only read from `config.exs`**, never from `use Francis` opts. If both locations set the same key, `use` opts win and a warning is logged.

`bandit_opts` is read at boot and `error_handler` per error (`runtime.exs` works for both). `static`, `parser`, `log_level` are compile-time (`Application.compile_env`). Without a `:port` in `bandit_opts`, the `PORT` env var is used. `static: false` disables static serving.

```elixir
config :francis,
  bandit_opts: [port: 4000],
  static: [from: "priv/static", at: "/"],
  parser: [parsers: [:json, :urlencoded, :multipart], json_decoder: Jason],
  error_handler: &MyApp.Errors.handle/2,
  log_level: :info,
  dev: true
```

Note: the outer key is singular `:parser`; the inner `Plug.Parsers` key is plural `:parsers`.

---

## Static Assets & Digestion

```elixir
use Francis, static: [from: "priv/static", at: "/"]
```

```bash
mix francis.digest                    # hash all assets, write cache_manifest.json
mix francis.digest --clean            # remove old digested files, then re-digest
mix francis.digest --gzip false
mix francis.digest --exclude '*.json'
mix francis.digest --age 86400        # cache-control max-age in seconds (default: 31536000)
```

```elixir
Francis.Static.static_path("app.css")  # => "/app-a1b2c3d4.css"
```

---

## Mix Tasks

```bash
mix francis.server
iex -S mix francis.server

mix francis.new my_app
mix francis.new my_app --sup
mix francis.new my_app --sup MyApp

mix francis.release --port 8080 --elixir-version 1.18.4 --otp-version 27.3.4
```

---

## Testing

```elixir
defmodule MyAppTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts MyApp.init([])

  test "GET /" do
    conn = conn(:get, "/") |> MyApp.call(@opts)
    assert conn.status == 200
    assert conn.resp_body == "hello"
  end

  test "POST /users" do
    conn =
      conn(:post, "/users", Jason.encode!(%{name: "Alice"}))
      |> put_req_header("content-type", "application/json")
      |> MyApp.call(@opts)

    assert conn.status == 201
    assert %{"name" => "Alice"} = Jason.decode!(conn.resp_body)
  end
end
```

Always prefix mix commands with `unbuffer`: `unbuffer mix test`

---

## Gotchas & Red Flags

| Situation | Correct approach |
|---|---|
| Rendering user input in HTML | `html(conn, "<p>#{Francis.HTML.escape(input)}</p>")` |
| Rendering untrusted text | `safe_html(conn, input)` — escapes entire string; do NOT wrap in markup |
| SSE pushing from handler | SSE is server→client; push via `send(socket.transport, msg)` from another process |
| WS broadcasting from another process | `send(socket.transport, msg)` → `{:info, msg}` clause, or straight to the client if unmatched |
| Forgetting `:close` handler | Silent success — add `{:close, _}` to clean up subscriptions and ETS entries |
| Absolute URL in `redirect` | Francis raises `ArgumentError` — relative paths only |
| `dev: true` not working | Only valid in `config.exs`, not in `use Francis` opts |
| Auth inside a route handler | Move to a `plug` before routes, or scope with `forward/2` |
| `body_params` is `%{}` | Caller must send a matching `content-type` header |
| `unmatched/1` not catching routes | Must be declared **last** — shadows everything after it |
