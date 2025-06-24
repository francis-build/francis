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
  """
  import Plug.Conn

  defmacro __using__(opts \\ []) do
    quote location: :keep do
      use Application

      use Plug.ErrorHandler
      use Francis.Plug.Router

      require Logger

      import Francis.ResponseHandlers

      def start, do: start(:normal, [])

      static = Keyword.get(unquote(opts), :static)
      parser = Keyword.get(unquote(opts), :parser)

      if static, do: plug(Plug.Static, static)

      if parser,
        do: plug(Plug.Parsers, parser),
        else: plug(Plug.Parsers, parsers: [:urlencoded, :multipart, :json], json_decoder: Jason)

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
        case Keyword.get(unquote(opts), :error_handler) do
          nil ->
            Logger.error("Unhandled error: #{inspect(reason)}")

            conn
            |> put_status(500)
            |> send_resp(500, "Internal Server Error")
            |> halt()

          handler ->
            Keyword.get(unquote(opts), :error_handler).(conn, reason)
        end
      rescue
        e in FunctionClauseError ->
          Logger.error("Unhandled error: #{inspect(e)}")
          send_resp(conn, 500, "Internal Server Error")

        e ->
          Logger.error("Error occurred: #{inspect(e)}")
          send_resp(conn, 500, "Internal Server Error")
      end
    end
  end

  @doc """
  Defines a GET route

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    get "/hello", fn conn ->
      "Hello World!"
    end
  end
  ```
  """
  @spec get(String.t(), (Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) :: Macro.t()
  defmacro get(path, handler) do
    quote location: :keep do
      Plug.Router.get(unquote(path), do: handle_response(unquote(handler), var!(conn)))
    end
  end

  @doc """
  Defines a POST route

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    post "/hello", fn conn ->
      "Hello World!"
    end
  end
  ```
  """
  @spec post(String.t(), (Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) :: Macro.t()
  defmacro post(path, handler) do
    quote location: :keep do
      Plug.Router.post(unquote(path), do: handle_response(unquote(handler), var!(conn)))
    end
  end

  @doc """
  Defines a PUT route

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    put "/hello", fn conn ->
      "Hello World!"
    end
  end
  ```
  """
  @spec put(String.t(), (Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) :: Macro.t()
  defmacro put(path, handler) do
    quote location: :keep do
      Plug.Router.put(unquote(path), do: handle_response(unquote(handler), var!(conn)))
    end
  end

  @doc """
  Defines a DELETE route

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    delete "/hello", fn conn ->
      "Hello World!"
    end
  end
  ```
  """
  @spec delete(String.t(), (Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) :: Macro.t()
  defmacro delete(path, handler) do
    quote location: :keep do
      Plug.Router.delete(unquote(path), do: handle_response(unquote(handler), var!(conn)))
    end
  end

  @doc """
  Defines a PATCH route

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    patch "/hello", fn conn ->
      "Hello World!"
    end
  end
  ```
  """
  @spec patch(String.t(), (Plug.Conn.t() -> binary() | map() | Plug.Conn.t())) :: Macro.t()
  defmacro patch(path, handler) do
    quote location: :keep do
      Plug.Router.patch(unquote(path), do: handle_response(unquote(handler), var!(conn)))
    end
  end

  @doc """
  Defines a WebSocket route that sends text type responses.

  The handler function receives the message and the socket state, and it can return a binary or a map.
  The state includes:
  - `:transport` - The transport process that can be used to send messages back to the client using `send/2`
  - `:id` - A unique identifier for the WebSocket connection that can be used to track the connection
  - `:path` - The path of the WebSocket connection to identify the route that triggered the connection

  ## Examples

  ```elixir
  defmodule Example.Router do
    use Francis

    ws "/hello", fn _, socket ->
      "Hello World!"
    end
  end
  ```
  """

  @spec ws(String.t(), (binary(), %{id: binary(), transport: pid(), path: binary()} ->
                          {:reply, binary() | map() | {atom(), any()}} | :noreply)) :: Macro.t()
  defmacro ws(path, handler, opts \\ []) do
    module_name = generate_ws_module_name(path)
    handler_ast = build_ws_handler_ast(module_name, handler)

    Code.compile_quoted(handler_ast)

    quote location: :keep do
      get(unquote(path), fn conn ->
        conn
        |> var!()
        |> WebSockAdapter.upgrade(
          unquote(module_name),
          %{id: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(), path: unquote(path)},
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
        require WebSockAdapter
        require Logger

        def init(opts) do
          {:ok, Map.put(opts, :transport, self())}
        end

        def handle_in(message, state) do
          unquote(build_handle_in_ast(handler))
        end

        def handle_info(msg, state) do
          format_ws_response({:reply, msg}, state)
        end

        def terminate(reason, state) do
          Logger.info("WS Handler terminated: #{inspect(reason)} ")
          :ok
        end

        unquote_splicing(build_format_response_ast())
      end
    end
  end

  defp build_handle_in_ast(handler) do
    quote do
      try do
        message
        |> elem(0)
        |> then(&unquote(handler).(&1, state))
        |> format_ws_response(state)
      rescue
        e ->
          Logger.error("WS Handler error: #{inspect(e)} ")
          {:stop, :error, e}
      end
    end
  end

  defp build_format_response_ast do
    [
      quote do
        defp format_ws_response({:reply, {type, msg}}, state), do: {:push, [{type, msg}], state}
      end,
      quote do
        defp format_ws_response({:reply, msg}, state) when is_binary(msg),
          do: {:push, [{:text, msg}], state}
      end,
      quote do
        defp format_ws_response({:reply, msg}, state) when is_map(msg) or is_list(msg),
          do: {:push, [{:text, Jason.encode!(msg)}], state}
      end,
      quote do
        defp format_ws_response(:noreply, state), do: {:ok, state}
      end
    ]
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
end
