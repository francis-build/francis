# Francis

[![Hex version badge](https://img.shields.io/hexpm/v/francis.svg)](https://hex.pm/packages/francis)
[![License badge](https://img.shields.io/hexpm/l/francis.svg)](https://github.com/francis-build/francis/blob/main/LICENSE)
[![Elixir CI](https://github.com/francis-build/francis/actions/workflows/elixir.yaml/badge.svg)](https://github.com/francis-build/francis/actions/workflows/elixir.yaml)

Simple boilerplate killer using Plug and Bandit inspired by [Sinatra](https://sinatrarb.com) for Ruby.

Focused on reducing time to build as it offers automatic request parsing, automatic response parsing, easy DSL to build quickly new endpoints and websocket listeners.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed by adding `francis` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:francis, "~> 0.1.0"}
  ]
end
```

You can also use the Francis generator to create all the initial project files. You need to install the francis tasks first.

```bash
mix archive.install hex francis
```

Then you can create a new project with:

```bash
mix francis.new my_app
```

You can also create a project with a supervisor structure:

```bash
mix francis.new my_app --sup
mix francis.new my_app --sup MyApp
```

Use `mix help francis.new` to see all the available options.

## Usage

To start the server up you can run `mix francis.server` or if you need a iex console you can run with `iex -S mix francis.server`.

## Deployment

To create the Dockerfile that can be used for deployment you can run:

```bash
mix francis.release
```

## Static Asset Management

Francis provides utilities for managing static assets, including content-based hashing for cache busting.

### Digest Task

The `mix francis.digest` task generates digested versions of static files with content-based hashes in their filenames:

```bash
mix francis.digest
mix francis.digest priv/static
mix francis.digest priv/static --output priv/static
```

Options:
- `--output` - The output path for generated files (defaults to input path)
- `--age` - Cache control max age in seconds (defaults to 31536000, 1 year)
- `--gzip` - Generate gzipped files (defaults to true)
- `--exclude` - File patterns to exclude (e.g., `--exclude '*.txt' --exclude '*.json'`)

### Static Module

The `Francis.Static` module provides functions to work with digested assets:

```elixir
# Get the digested path for an asset
Francis.Static.static_path("app.css")
# => "/app-a1b2c3d4.css"

# Check if an asset exists in the manifest
Francis.Static.exists?("app.css")
# => true

# Get all assets from the manifest
Francis.Static.all()
# => %{"app.css" => %{"digest" => "a1b2c3d4", ...}, ...}
```

## Configuration

You can configure Francis in your `config/config.exs` file. The following options are available:

- `dev` - If set to `true`, it will enable the development mode which will automatically reload the server when you change your code. Defaults to `false`.
- `bandit_opts` - Options to be passed to Bandit
- `static` - Configure Plug.Static to serve static files
- `parser` - Overrides the default configuration for Plug.Parsers
- `error_handler` - Defines a custom error handler for the server
- `log_level` - Sets the log level for Plug.Logger (default is `:info`)

```elixir
import Config

config :francis,
  dev: false,
  bandit_opts: [port: 4000],
  static: [from: "priv/static", at: "/"],
  parser: [parsers: [:json, :urlencoded], pass: ["*/*"]],
  error_handler: &Example.error/2,
  log_level: :info
```

You can also set the values in `use` macro:

```elixir
defmodule Example do
  use Francis,
    bandit_opts: [port: 4000],
    static: [from: "priv/static", at: "/"],
    parser: [parsers: [:json, :urlencoded], pass: ["*/*"]],
    error_handler: &Example.error/2,
    log_level: :info
end
```

Note: The `dev` option can only be set in your `config/config.exs` file, not in the `use` macro.

## Error Handling

By default, Francis will return a 500 error with the message "Internal Server Error" if you return a tuple `{:error, any()}` or an exception is raised during the request handling.

### Unmatched Routes

If a request does not match any defined route, you can use the `unmatched/1` macro to define a custom response:

```elixir
unmatched(fn _conn -> "not found" end)
```

### Custom Error Responses

For more advanced error handling, you can setup a custom error handler by providing the function that will handle the errors of your application:

```elixir
defmodule Example do
  use Francis, error_handler: &__MODULE__.error/2

  get("/", fn _ -> {:error, :custom_error} end)

  def error(conn, {:error, :custom_error}) do
    # Return a custom response
    Plug.Conn.send_resp(conn, 502, "Custom error response")
  end
end
```

If you do not handle errors explicitly, Francis will catch them and return a 500 response.

## Example of a router

```elixir
defmodule Example do
  use Francis

  get("/", fn _ -> "<html>world</html>" end)
  get("/:name", fn %{params: %{"name" => name}} -> "hello #{name}" end)
  post("/", fn conn -> conn.body_params end)

  ws("/ws", fn {:received, "ping"}, _socket -> {:reply, "pong"} end)

  unmatched(fn _ -> "not found" end)
end
```

And in your `mix.exs` file add that this module should be the one used for
startup:

```elixir
def application do
  [
    extra_applications: [:logger],
    mod: {Example, []}
  ]
end
```

This will ensure that Mix knows what module should be the entrypoint.

## WebSocket Support

Francis provides a simple DSL for WebSocket endpoints using the `ws/2` and `ws/3` macros.

### Basic Usage

```elixir
defmodule Example do
  use Francis

  # Simple echo server
  ws("/echo", fn {:received, message}, _socket ->
    {:reply, message}
  end)
end
```

### Events

The handler receives different event types that can be pattern matched:

- `:join` - Sent when a client connects
- `{:close, reason}` - Sent when the connection closes
- `{:received, message}` - Regular WebSocket text messages from the client

### Socket State

The socket state map includes:
- `:id` - A unique identifier for the WebSocket connection
- `:transport` - The transport process for sending messages
- `:path` - The actual request path of the WebSocket connection
- `:params` - A map of path parameters extracted from the route

### Full Example with Lifecycle Events

```elixir
defmodule Chat do
  use Francis
  require Logger

  ws("/chat/:room", fn
    :join, socket ->
      room = socket.params["room"]
      {:reply, %{type: "welcome", room: room, id: socket.id}}

    {:close, reason}, socket ->
      Logger.info("Client #{socket.id} left: #{inspect(reason)}")
      :ok

    {:received, message}, socket ->
      room = socket.params["room"]
      {:reply, "[#{room}] #{message}"}
  end)
end
```

### Options

- `:timeout` - The timeout for the WebSocket connection in milliseconds (default: 60_000)
- `:heartbeat_interval` - The interval in milliseconds between ping frames (default: 30_000). Set to `nil` to disable.

```elixir
ws("/ws", fn {:received, msg}, _socket -> {:reply, msg} end, heartbeat_interval: 10_000)
```

## Example of a router with Static serving

With the `static` option, you are able to setup the options for `Plug.Static` to serve static assets easily.

```elixir
defmodule Example do
  use Francis, static: [from: "priv/static", at: "/"]
end
```

## Response Helpers

Francis provides convenient helper functions for common response types through the `Francis.ResponseHandlers` module, which is automatically imported when you `use Francis`.

### Redirect

```elixir
get("/old", fn conn -> redirect(conn, "/new") end)
get("/old", fn conn -> redirect(conn, 301, "/new") end)
```

### JSON

```elixir
get("/api/data", fn conn -> json(conn, %{message: "success"}) end)
get("/api/data", fn conn -> json(conn, 201, %{id: 123, created: true}) end)
```

### Text

```elixir
get("/text", fn conn -> text(conn, "Hello, World!") end)
get("/text", fn conn -> text(conn, 201, "Resource created") end)
```

### HTML

```elixir
get("/", fn conn -> html(conn, "<h1>Hello, World!</h1>") end)
get("/", fn conn -> html(conn, 201, "<h1>Created</h1>") end)
```

**Warning:** The `html/2` and `html/3` functions do not escape HTML content. Only use with trusted, static HTML content to avoid XSS vulnerabilities.

## Example of a router with Plugs

With the `plugs` option you are able to apply a list of plugs that happen
between before dispatching the request.

In the following example we're adding the `Plug.BasicAuth` plug to setup basic
authentication on all routes

```elixir
defmodule Example do
  import Plug.BasicAuth

  use Francis

  plug(:basic_auth, username: "test", password: "test")

  get("/", fn _ -> "<html>world</html>" end)
  get("/:name", fn %{params: %{"name" => name}} -> "hello #{name}" end)

  ws("/ws", fn {:received, "ping"}, _socket -> {:reply, "pong"} end)

  unmatched(fn _ -> "not found" end)
end
```
## Example of multiple routers
You can also define multiple routers in your application by using the `forward/2` function provided by [Plug](https://hexdocs.pm/plug/Plug.Router.html#forward/2) .

For example, you can have an authenticated router and a public router.

```elixir
defmodule Public do
  use Francis
  get("/", fn _ -> "ok" end)
end

defmodule Private do
  use Francis
  import Plug.BasicAuth
  plug(:basic_auth, username: "test", password: "test")
  get("/", fn _ -> "hello" end)
end

defmodule TestApp do
  use Francis

  forward("/path1", to: Public)
  forward("/path2", to: Private)

  unmatched(fn _ -> "not found" end)
end
```

Check the folder [examples](https://github.com/francis-build/francis/tree/main/examples) to see examples of how to use Francis.
