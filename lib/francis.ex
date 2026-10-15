defmodule Francis do
  @moduledoc """
  Module responsible for starting the Francis server and to wrap the Plug functionality

  This module performs multiple tasks:
    * Uses the Application module to start the Francis server
    * Defines the Francis.Router which uses Francis.Plug.Router, :match and :dispatch
    * Defines the macros get, post, put, delete, patch, ws and sse to define routes for each operation
    * Setups Plug.Static with the given options
    * Sets up Plug.Parsers with the default configuration of:
      * ```elixir
        plug(Plug.Parsers,
          parsers: [:urlencoded, :multipart, :json],
          json_decoder: Jason
        )
        ```
    * Defines a default error handler that renders an HTML error page with the status of the raised exception (500 for `{:error, _}` and exceptions without a `plug_status`). You can override this by passing the function name on `:error_handler` option to the `use Francis` macro which will override the default error handler.

  You can also set the following options:
    * :bandit_opts - Options to be passed to Bandit
    * :static - Configure Plug.Static to serve static files
    * :parser - Overrides the default configuration for Plug.Parsers
    * :error_handler - Defines a custom error handler for the server
    * :log_level - Sets the log level for Plug.Logger (default is `:info`)
  """
  require Logger
  import Plug.Conn

  defmacro __using__(opts \\ []) do
    quote location: :keep do
      use Application

      use Plug.ErrorHandler
      use Francis.Plug.Router

      require Logger

      import Francis.ResponseHandlers

      def start, do: start(:normal, [])

      # Plugs are built at compile time, so these keys are read with
      # compile_env: Mix recompiles the router when they change, and a
      # runtime.exs override fails loudly at boot instead of being ignored.
      static =
        Francis.resolve_configuration(
          :static,
          Keyword.get(unquote(opts), :static),
          Application.compile_env(:francis, :static),
          from: "priv/static",
          at: "/",
          gzip: true
        )

      parser =
        Francis.resolve_configuration(
          :parser,
          Keyword.get(unquote(opts), :parser),
          Application.compile_env(:francis, :parser),
          parsers: [:urlencoded, :multipart, :json],
          json_decoder: Jason
        )

      log_level =
        Francis.resolve_configuration(
          :log_level,
          Keyword.get(unquote(opts), :log_level),
          Application.compile_env(:francis, :log_level),
          :info
        )

      if static, do: plug(Plug.Static, static)

      plug(Plug.Parsers, parser)

      plug(Plug.Logger, log: log_level)
      plug(Plug.Head)

      def start(_type, _args) do
        dev = Application.get_env(:francis, :dev, false)
        watcher_spec = if dev, do: [{Francis.Watcher, []}], else: []

        # Read at runtime so values injected after compilation (e.g. a `PORT`
        # set in runtime.exs) are honoured.
        bandit_opts =
          :bandit_opts
          |> Francis.get_configuration(unquote(opts), [])
          |> Francis.put_env_port()

        children = [{Bandit, [plug: __MODULE__] ++ bandit_opts}] ++ watcher_spec

        Supervisor.start_link(children, strategy: :one_for_one)
      end

      defoverridable(start: 2)

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start, opts},
          type: :supervisor,
          restart: :permanent,
          shutdown: 5000,
          modules: [__MODULE__]
        }
      end

      @spec handle_response(
              (Plug.Conn.t() -> binary() | map() | Plug.Conn.t()),
              Plug.Conn.t(),
              integer()
            ) :: Plug.Conn.t()
      def handle_response(handler, conn, status \\ 200) do
        case handler.(conn) do
          res when is_struct(res, Plug.Conn) ->
            res

          res when is_binary(res) ->
            conn
            |> send_resp(status, res)
            |> halt()

          res when is_map(res) or is_list(res) ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(status, Jason.encode!(res))
            |> halt()

          {:error, res} ->
            handle_errors(conn, {:error, res})
        end
      rescue
        e -> handle_errors(conn, e)
      end

      @spec handle_errors(Plug.Conn.t(), any()) :: Plug.Conn.t()
      @impl true
      def handle_errors(conn, reason) do
        # Read per error so runtime.exs works; the macro option wins. No
        # "both set" warning here, as it would be logged on every error.
        error_handler =
          Keyword.get(unquote(opts), :error_handler) ||
            Application.get_env(:francis, :error_handler)

        Francis.handle_error(conn, reason, error_handler)
      end
    end
  end

  @http_methods [:get, :post, :put, :delete, :patch]

  for method <- @http_methods do
    @doc """
    Defines a #{String.upcase(to_string(method))} route

    ## Examples

    ```elixir
    defmodule Example.Router do
      use Francis

      #{method} "/hello", fn conn ->
        "Hello World!"
      end
    end
    ```
    """
    @spec unquote(method)(String.t(), (Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) ::
            Macro.t()
    defmacro unquote(method)(path, handler) do
      method = unquote(method)

      quote location: :keep do
        Plug.Router.unquote(method)(
          unquote(path),
          do: handle_response(unquote(handler), var!(conn))
        )
      end
    end
  end

  @doc """
  Defines a WebSocket route with a unified event handler.

  The handler function uses pattern matching on events, providing an idiomatic Elixir approach.
  All events flow through a single function with distinct shapes for easy pattern matching.

  ## Events

  The handler receives different event types that can be pattern matched:

  - `:join` - Sent when a client connects. Return `{:reply, message}` to send a welcome message.
  - `{:close, reason}` - Sent when the connection closes. Return `:ok` or `:noreply`.
  - `{:received, message}` - Regular WebSocket text messages from the client.
  - `{:info, message}` - Messages sent to `socket.transport` from other processes
    (e.g. PubSub broadcasts or monitor `:DOWN` messages). Optional.

  When the handler has no `{:info, _}` clause, messages sent via
  `send(socket.transport, message)` are forwarded to the client as-is if they are
  a binary, map, list or `{type, payload}` frame; anything else is logged and dropped.

  ## Return Values

  - `{:reply, response}` - where `response` can be a binary, a map, or a list (maps/lists will be JSON encoded)
  - `:noreply` or `:ok` - to not send a response

  ## Socket State

  The socket state map includes:
  - `:transport` - The transport process that can be used to send messages back to the client using `send/2`
  - `:id` - A unique identifier for the WebSocket connection that can be used to track the connection
  - `:path` - The actual request path of the WebSocket connection (e.g., `/chat/general`)
  - `:params` - A map of path parameters extracted from the route (e.g., `%{"room" => "general"}` for route `/:room`)

  ## Options

  - `:timeout` - The timeout for the WebSocket connection in milliseconds (default: 60_000)
  - `:heartbeat_interval` - The interval in milliseconds between ping frames for heartbeat (default: 30_000). Set to `nil` to disable heartbeat.
  - `:max_frame_size` - The maximum allowed size in bytes for incoming WebSocket frames (default: 65_536). Protects against memory exhaustion from oversized messages.

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    # Simple echo server
    ws "/echo", fn {:received, message}, socket ->
      {:reply, message}
    end

    # Pattern matching on specific messages
    ws "/ping", fn {:received, "ping"}, socket ->
      {:reply, "pong"}
    end

    # Full lifecycle handling with pattern matching
    ws "/chat/:room", fn
      :join, socket ->
        room = socket.params["room"]
        {:reply, %{type: "welcome", room: room, id: socket.id}}

      {:close, reason}, socket ->
        Logger.info("Client \#{socket.id} left: \#{inspect(reason)}")
        :ok

      {:received, message}, socket ->
        room = socket.params["room"]
        # Without an {:info, _} clause, this is forwarded to the client as-is
        send(socket.transport, "Someone said: " <> message)
        {:reply, "[" <> room <> "] " <> message}
    end

    # JSON responses
    ws "/json", fn {:received, message}, socket ->
      {:reply, %{status: "ok", message: message}}
    end

    # No reply needed
    ws "/fire-and-forget", fn {:received, message}, socket ->
      Logger.info("Received: \#{message}")
      :noreply
    end

    # Custom heartbeat interval (ping every 10 seconds)
    ws "/heartbeat", fn {:received, message}, socket ->
      {:reply, message}
    end, heartbeat_interval: 10_000

    # Disable heartbeat
    ws "/no-heartbeat", fn {:received, message}, socket ->
      {:reply, message}
    end, heartbeat_interval: nil
  end
  ```
  """

  @spec ws(
          String.t(),
          (event :: :join | {:close, term()} | {:received, binary()} | {:info, term()},
           socket :: %{id: binary(), transport: pid(), path: binary(), params: map()} ->
             {:reply, binary() | map() | {atom(), any()}} | :noreply | :ok),
          Keyword.t()
        ) :: Macro.t()
  defmacro ws(path, handler, opts \\ []) do
    quote location: :keep do
      get(unquote(path), fn conn ->
        Francis.Websocket.upgrade(conn, unquote(handler), unquote(opts))
      end)
    end
  end

  @doc """
  Defines a Server-Sent Events (SSE) route with a unified event handler.

  The handler function uses pattern matching on events, providing a consistent
  API with the WebSocket macro. SSE connections are unidirectional (server-to-client),
  so the handler receives messages via `send(socket.transport, message)` from other
  processes and forwards them to the client as SSE events.

  ## Events

  The handler receives different event types that can be pattern matched:

  - `:join` - Sent when a client connects. Return `{:reply, message}` to send an initial event.
  - `{:close, reason}` - Sent when the connection closes. Return `:ok` or `:noreply`.
  - `{:received, message}` - Messages sent to `socket.transport` from other processes.

  ## Return Values

  - `{:reply, response}` - where `response` can be:
    - a binary – sent as `data: <string>\\n\\n`
    - a map or list – JSON-encoded as `data: <json>\\n\\n`
    - a map with `:event`, `:data`, and optionally `:id` / `:retry` keys –
      sent with the corresponding SSE fields
  - `:noreply` or `:ok` - to not send an event

  ## Socket State

  The socket state map includes:
  - `:transport` - The transport process PID. Use `send(socket.transport, msg)` to push events.
  - `:id` - A unique identifier for the SSE connection.
  - `:path` - The actual request path (e.g., `/events/news`).
  - `:params` - A map of path parameters extracted from the route.

  ## Options

  - `:keepalive_interval` - Interval in ms between keepalive comments (default: 15_000).
    Set to `nil` to disable keepalive.

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    # Simple event stream
    sse "/events", fn :join, socket ->
      {:reply, %{type: "connected", id: socket.id}}
    end

    # With named events and full lifecycle
    sse "/feed/:topic", fn
      :join, socket ->
        topic = socket.params["topic"]
        {:reply, %{event: "welcome", data: %{topic: topic}}}

      {:close, _reason}, _socket ->
        :ok

      {:received, message}, _socket ->
        {:reply, message}
    end

    # Disable keepalive
    sse "/raw", fn {:received, msg}, _socket ->
      {:reply, msg}
    end, keepalive_interval: nil
  end
  ```
  """

  @spec sse(
          String.t(),
          (event :: :join | {:close, term()} | {:received, term()},
           socket :: %{id: binary(), transport: pid(), path: binary(), params: map()} ->
             {:reply, binary() | map() | list()} | :noreply | :ok),
          Keyword.t()
        ) :: Macro.t()
  defmacro sse(path, handler, opts \\ []) do
    quote location: :keep do
      get(unquote(path), fn conn ->
        Francis.SSE.run(conn, unquote(handler), unquote(opts))
      end)
    end
  end

  @doc """
  Defines a catch-all action for unmatched routes (returns 404).
  """
  @spec unmatched((Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) :: Macro.t()
  defmacro unmatched(handler) do
    quote location: :keep do
      match _ do
        handle_response(unquote(handler), var!(conn), 404)
      end
    end
  end

  @doc """
  Retrieves the configuration for a given key, checking both the macro options and the application environment.
  """
  @spec get_configuration(atom(), Keyword.t(), any()) :: any()
  def get_configuration(key, opts, default) do
    resolve_configuration(
      key,
      Keyword.get(opts, key),
      Application.get_env(:francis, key),
      default
    )
  end

  @doc false
  # `nil` means "not set"; `false` is a real value (e.g. `static: false` disables static serving).
  @spec resolve_configuration(atom(), any(), any(), any()) :: any()
  def resolve_configuration(_key, nil, nil, default), do: default
  def resolve_configuration(_key, nil, config, _default), do: config
  def resolve_configuration(_key, macro, nil, _default), do: macro

  def resolve_configuration(key, macro, _config, _default) do
    Logger.warning(
      "Both application configuration and macro option provided for #{key}. Using macro option."
    )

    macro
  end

  @doc false
  # Falls back to the `PORT` environment variable when no port was configured,
  # so releases and containers can pick the port at boot.
  @spec put_env_port(Keyword.t()) :: Keyword.t()
  def put_env_port(bandit_opts) do
    case {Keyword.has_key?(bandit_opts, :port), System.get_env("PORT", "")} do
      {false, port} when port != "" -> Keyword.put(bandit_opts, :port, parse_port!(port))
      _ -> bandit_opts
    end
  end

  defp parse_port!(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port in 0..65_535 ->
        port

      _ ->
        raise ArgumentError,
              "PORT environment variable must be a port number, got: #{inspect(value)}"
    end
  end

  @doc false
  # Error handling chain: custom handler -> fallback to the generic error page.
  # `Plug.ErrorHandler` hands over `%{kind:, reason:, stack:}` for errors raised
  # outside route handlers (e.g. parsers); these are unwrapped so a custom
  # handler always receives an exception, an `{:error, _}` tuple, or
  # `{kind, reason}` for throws and exits.
  @spec handle_error(Plug.Conn.t(), any(), (Plug.Conn.t(), any() -> Plug.Conn.t()) | nil) ::
          Plug.Conn.t()
  def handle_error(conn, %{kind: :error, reason: reason, stack: _}, handler),
    do: handle_error(conn, reason, handler)

  def handle_error(conn, %{kind: kind, reason: reason, stack: _}, handler),
    do: handle_error(conn, {kind, reason}, handler)

  def handle_error(conn, reason, nil), do: render_error(conn, reason)

  # If the custom error handler itself raises, still render an error page
  # rather than crashing the connection.
  def handle_error(conn, reason, handler) do
    handler.(conn, reason)
  rescue
    e ->
      Logger.error("Error handler raised #{inspect(e)} while handling #{inspect(reason)}")
      render_error(conn, e)
  end

  defp render_error(conn, reason) do
    status = if is_exception(reason), do: Plug.Exception.status(reason), else: 500
    level = if status >= 500, do: :error, else: :warning
    Logger.log(level, "Unhandled error: #{inspect(reason)}")

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, Francis.ErrorPage.render(status))
    |> halt()
  end
end
