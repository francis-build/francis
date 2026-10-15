defmodule Francis.Websocket do
  @moduledoc """
  `WebSock` implementation backing the `Francis.ws/3` macro.

  Every WebSocket route shares this module; the route's handler function is
  carried in the connection state. It is not intended for direct use by
  application code.
  """
  @behaviour WebSock

  require Logger

  alias Francis.Handler

  @default_heartbeat_interval 30_000
  @default_timeout 60_000
  @default_max_frame_size 65_536

  @doc """
  Upgrades `conn` to a WebSocket connection driven by `handler`.
  """
  @spec upgrade(Plug.Conn.t(), function(), Keyword.t()) :: Plug.Conn.t()
  def upgrade(conn, handler, opts) do
    state = %{
      id: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(),
      path: conn.request_path,
      params: conn.params,
      handler: handler,
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, @default_heartbeat_interval)
    }

    conn
    |> WebSockAdapter.upgrade(__MODULE__, state,
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_frame_size: Keyword.get(opts, :max_frame_size, @default_max_frame_size)
    )
    |> Plug.Conn.halt()
  end

  @impl true
  def init(state) do
    state =
      state
      |> Map.put(:transport, self())
      |> setup_heartbeat()

    send(self(), :__francis_join__)
    {:ok, state}
  end

  @impl true
  def handle_control({_payload, [opcode: :ping]}, state), do: {:ok, state}
  def handle_control({_payload, [opcode: :pong]}, state), do: {:ok, state}

  @impl true
  def handle_in({message, _opts}, state) do
    state.handler.({:received, message}, state)
    |> format_response(state)
  rescue
    e ->
      Logger.error("WS Handler error: #{inspect(e)}")
      {:stop, :error, state}
  end

  @impl true
  def handle_info(:__francis_join__, state) do
    case Handler.call_optional(state.handler, :join, state) do
      {:ok, result} -> format_response(result, state)
      :unmatched -> {:ok, state}
    end
  end

  def handle_info(:__francis_heartbeat__, state), do: handle_heartbeat(state)

  # Process messages go to the handler as `{:info, msg}` first; when it has no
  # clause for them, frame-shaped messages are pushed to the client as before.
  def handle_info(msg, state) do
    case Handler.call_optional(state.handler, {:info, msg}, state) do
      {:ok, result} -> format_response(result, state)
      :unmatched -> forward(msg, state)
    end
  rescue
    e ->
      Logger.error("WS Handler error: #{inspect(e)}")
      {:stop, :error, state}
  end

  @impl true
  def terminate(reason, state) do
    cancel_heartbeat(state)
    Handler.call_optional(state.handler, {:close, reason}, state)
    :ok
  end

  @doc """
  Formats a handler return value for the WebSock protocol.
  """
  def format_response({:reply, {type, msg}}, state) when type in [:text, :binary, :ping, :pong],
    do: {:push, [{type, msg}], state}

  def format_response({:reply, msg}, state) when is_binary(msg),
    do: {:push, [{:text, msg}], state}

  def format_response({:reply, msg}, state) when is_map(msg) or is_list(msg),
    do: {:push, [{:text, Jason.encode!(msg)}], state}

  def format_response(:noreply, state), do: {:ok, state}
  def format_response(:ok, state), do: {:ok, state}

  defp forward(msg, state) do
    format_response({:reply, msg}, state)
  rescue
    FunctionClauseError ->
      Logger.warning("WS dropped unhandled message: #{inspect(msg)}")
      {:ok, state}
  end

  defp setup_heartbeat(%{heartbeat_interval: interval} = state)
       when is_integer(interval) and interval > 0 do
    timer = Process.send_after(self(), :__francis_heartbeat__, interval)
    Map.put(state, :heartbeat_timer, timer)
  end

  defp setup_heartbeat(state), do: Map.put(state, :heartbeat_timer, nil)

  defp handle_heartbeat(%{heartbeat_timer: timer, heartbeat_interval: interval} = state)
       when is_reference(timer) do
    Process.cancel_timer(timer)
    new_timer = Process.send_after(self(), :__francis_heartbeat__, interval)
    {:push, [{:ping, <<>>}], Map.put(state, :heartbeat_timer, new_timer)}
  end

  defp handle_heartbeat(state), do: {:ok, state}

  defp cancel_heartbeat(%{heartbeat_timer: timer}) when is_reference(timer),
    do: Process.cancel_timer(timer)

  defp cancel_heartbeat(_state), do: :ok
end
