# Francis

[![Hex version badge](https://img.shields.io/hexpm/v/francis.svg)](https://hex.pm/packages/francis)
[![License badge](https://img.shields.io/hexpm/l/repo_example.svg)](https://github.com/francis-build/francis/blob/master/LICENSE.md)
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

Use `mix help francis.new` to see all the available options.

## Usage

To start the server up you can run `mix francis.server` or if you need a iex console you can run with `iex -S mix francis.server`.

## Deployment

To create the Dockerfile that can be used for deployment you can run:

```bash
mix francis.release
```

## Dev mode

If you want to have a watcher that will reload the server when you change your code you can use the `dev` configuration option:

```elixir
import Config

config :francis, dev: true
```

It defaults to `false`

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

  get("/", fn _ -> {:error, :potato} end)

  def error(conn,{:error, :failed}) do
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

  ws("ws", fn "ping" -> "pong" end)

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

## Example of a router with Static serving

With the `static` option, you are able to setup the options for `Plug.Static` to serve static assets easily.

```elixir
defmodule Example do
  use Francis, static: [from: "priv/static", at: "/"]
end
```

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

  ws("ws", fn "ping", _socket -> "pong" end)

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
