defmodule Francis.Websocket do
  @moduledoc false
  # Helper functions for WebSocket handlers to reduce complexity in generated modules

  @doc """
  Formats a WebSocket response for the WebSock protocol.
  """
  def format_response({:reply, {type, msg}}, state) when type in [:text, :binary, :ping, :pong],
    do: {:push, [{type, msg}], state}

  def format_response({:reply, msg}, state) when is_binary(msg),
    do: {:push, [{:text, msg}], state}

  def format_response({:reply, msg}, state) when is_map(msg) or is_list(msg),
    do: {:push, [{:text, Jason.encode!(msg)}], state}

  def format_response(:noreply, state), do: {:ok, state}
  def format_response(:ok, state), do: {:ok, state}

  @doc """
  Sets up the heartbeat timer if configured.
  """
  def setup_heartbeat(state) do
    case Map.get(state, :heartbeat_interval) do
      interval when is_integer(interval) and interval > 0 ->
        timer = Process.send_after(self(), :__francis_heartbeat__, interval)
        Map.put(state, :heartbeat_timer, timer)

      _ ->
        Map.put(state, :heartbeat_timer, nil)
    end
  end

  @doc """
  Reschedules the heartbeat timer and returns a ping frame.
  """
  def handle_heartbeat(state) do
    case Map.get(state, :heartbeat_timer) do
      timer when is_reference(timer) ->
        Process.cancel_timer(timer)
        interval = Map.get(state, :heartbeat_interval)
        new_timer = Process.send_after(self(), :__francis_heartbeat__, interval)
        {:push, [{:ping, <<>>}], Map.put(state, :heartbeat_timer, new_timer)}

      _ ->
        {:ok, state}
    end
  end

  @doc """
  Cancels the heartbeat timer during termination.
  """
  def cancel_heartbeat(state) do
    case Map.get(state, :heartbeat_timer) do
      timer when is_reference(timer) -> Process.cancel_timer(timer)
      _ -> :ok
    end
  end

  @doc """
  Safely calls a handler for :join event, returning {:ok, state} on error.
  """
  def call_join(handler, state) do
    handler.(:join, state) |> format_response(state)
  rescue
    _e in [MatchError, FunctionClauseError] -> {:ok, state}
  end

  @doc """
  Safely calls a handler for :close event, returning :ok on error.
  """
  def call_close(handler, event, state) do
    handler.(event, state)
    :ok
  rescue
    _e in [MatchError, FunctionClauseError] -> :ok
  end
end
