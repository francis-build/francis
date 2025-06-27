defmodule Francis.Plug.Router do
  @moduledoc """
  Module that imports required macros from Francis and Plug.Router
  """
  alias Plug.Conn.WrapperError
  alias Plug.Router.Utils

  defmacro __before_compile__(_env) do
    quote location: :keep do
      plug(:match)
      plug(:dispatch)
    end
  end

  defmacro __using__(opts) do
    quote location: :keep do
      import Francis
      require Logger

      @plug_router_to %{}
      @before_compile Plug.Router
      @before_compile Francis.Plug.Router

      use Plug.Builder, unquote(opts)
      import Plug.Router, except: [get: 2, post: 2, put: 2, delete: 2, patch: 2, head: 2]

      @doc false
      def match(conn, _opts) do
        do_match(conn, conn.method, Utils.decode_path_info!(conn), conn.host)
      rescue
        err ->
          Logger.error("Failed to match route: #{conn.method} #{conn.request_path}")
          conn |> send_resp(404, "Not Found") |> halt()
      end

      @doc false
      def dispatch(%Plug.Conn{} = conn, opts) do
        {path, fun} = Map.fetch!(conn.private, :plug_route)

        try do
          :telemetry.span(
            [:plug, :router_dispatch],
            %{conn: conn, route: path, router: __MODULE__},
            fn ->
              conn = fun.(conn, opts)
              {conn, %{conn: conn, route: path, router: __MODULE__}}
            end
          )
        catch
          kind, reason -> WrapperError.reraise(conn, kind, reason, __STACKTRACE__)
        end
      end
    end
  end
end
