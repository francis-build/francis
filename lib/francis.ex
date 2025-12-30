defmodule Francis do
  @moduledoc """
  Module responsible for starting the Francis server and to wrap the Plug functionality

  This module performs multiple tasks:
    * Uses the Application module to start the Francis server
    * Defines the Francis.Router which uses Francis.Plug.Router, :match and :dispatch
    * Defines the macros get, post, put, delete, patch and ws to define routes for each operation
    * Setups Plug.Static with the given options
    * Sets up Plug.Parsers with the default configuration of:
      * ```elixir
        plug(Plug.Parsers,
          parsers: [:urlencoded, :multipart, :json],
          json_decoder: Jason
        )
        ```
    * Defines a default error handler that returns a 500 status code and a generic error message. You can override this by passing the function name on `:error_handler` option to the `use Francis` macro which will override the default error handler.

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

      static = get_configuration(:static, unquote(opts), from: "priv/static", at: "/")

      parser =
        get_configuration(:parser, unquote(opts),
          parsers: [:urlencoded, :multipart, :json],
          json_decoder: Jason
        )

      log_level = get_configuration(:log_level, unquote(opts), :info)

      if static, do: plug(Plug.Static, static)

      plug(Plug.Parsers, parser)

      plug(Plug.Logger, log: log_level)
      plug(Plug.Head)

      def start(_type, _args) do
        dev = Application.get_env(:francis, :dev, false)
        watcher_spec = if dev, do: [{Francis.Watcher, []}], else: []

        children =
          [
            {Bandit, [plug: __MODULE__] ++ Keyword.get(unquote(opts), :bandit_opts, [])}
          ] ++ watcher_spec

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
        error_handler = Keyword.get(unquote(opts), :error_handler)

        case error_handler do
          nil ->
            Logger.error("Unhandled error: #{inspect(reason)}")
            internal_server_error(conn)

          handler ->
            handler.(conn, reason)
        end
      rescue
        e ->
          Logger.error("Unhandled error: #{inspect(e)}")
          internal_server_error(conn)
      end

      defp internal_server_error(conn) do
        conn |> put_status(500) |> send_resp(500, "Internal Server Error") |> halt()
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

  Messages sent via `send(socket.transport, message)` are automatically forwarded to the client.

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
        # Broadcast to self (will be forwarded to client)
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
          (event :: :join | {:close, term()} | {:received, binary()},
           socket :: %{id: binary(), transport: pid(), path: binary(), params: map()} ->
             {:reply, binary() | map() | {atom(), any()}} | :noreply | :ok),
          Keyword.t()
        ) :: Macro.t()
  defmacro ws(path, handler, opts \\ []) do
    module_name = generate_ws_module_name(path)
    handler_ast = build_ws_handler_ast(module_name, handler)

    Code.compile_quoted(handler_ast)

    quote location: :keep do
      get(unquote(path), fn conn ->
        socket_state = %{
          id: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(),
          path: conn.request_path,
          params: conn.params
        }

        heartbeat_interval = Keyword.get(unquote(opts), :heartbeat_interval, 30_000)

        conn
        |> var!()
        |> WebSockAdapter.upgrade(
          unquote(module_name),
          Map.put(socket_state, :heartbeat_interval, heartbeat_interval),
          timeout: Keyword.get(unquote(opts), :timeout, 60_000)
        )
        |> halt()
      end)
    end
  end

  # Private helper functions for WebSocket macro
  defp generate_ws_module_name(path) do
    path
    |> URI.parse()
    |> Map.get(:path)
    |> String.split("/")
    |> Enum.map_join(".", &Macro.camelize/1)
    |> then(&Module.concat([__MODULE__, &1]))
  end

  defp build_ws_handler_ast(module_name, handler) do
    quote do
      defmodule unquote(module_name) do
        require Logger

        def init(opts) do
          state =
            opts
            |> Map.put(:transport, self())
            |> Francis.Websocket.setup_heartbeat()

          send(self(), :__francis_join__)
          {:ok, state}
        end

        def handle_control({_payload, [opcode: :ping]}, state), do: {:ok, state}
        def handle_control({_payload, [opcode: :pong]}, state), do: {:ok, state}

        def handle_in({message, _opts}, state) do
          unquote(handler).({:received, message}, state)
          |> Francis.Websocket.format_response(state)
        rescue
          e ->
            Logger.error("WS Handler error: #{inspect(e)}")
            {:stop, :error, state}
        end

        def handle_info(:__francis_join__, state),
          do: Francis.Websocket.call_join(unquote(handler), state)

        def handle_info(:__francis_heartbeat__, state),
          do: Francis.Websocket.handle_heartbeat(state)

        def handle_info(msg, state), do: Francis.Websocket.format_response({:reply, msg}, state)

        def terminate(reason, state) do
          Francis.Websocket.cancel_heartbeat(state)
          Francis.Websocket.call_close(unquote(handler), {:close, reason}, state)
          :ok
        end
      end
    end
  end

  @doc """
  Defines an action for umatched routes and returns 404
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
    opts = Keyword.get(opts, key)
    config = Application.get_env(:francis, key)

    if opts && config do
      Logger.warning(
        "Both application configuration and macro option provided for #{key}. Using macro option."
      )

      opts
    else
      opts || config || default
    end
  end
end
