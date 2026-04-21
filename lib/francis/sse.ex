defmodule Francis.SSE do
  @moduledoc false

  def format_message(msg) when is_binary(msg) do
    escaped = String.replace(msg, "\n", "\ndata: ")
    "data: #{escaped}\n\n"
  end

  def format_message(msg) when is_map(msg) or is_list(msg) do
    format_message(Jason.encode!(msg))
  end

  def send_event(conn, msg) do
    Plug.Conn.chunk(conn, format_message(msg))
  end

  def call_join(handler, conn, state) do
    case handler.(:join, state) do
      {:reply, msg} ->
        case send_event(conn, msg) do
          {:ok, conn} -> {:ok, conn, state}
          {:error, _} -> {:ok, conn, state}
        end

      _ ->
        {:ok, conn, state}
    end
  rescue
    _e in [MatchError, FunctionClauseError] -> {:ok, conn, state}
  end

  def call_close(handler, event, state) do
    handler.(event, state)
    :ok
  rescue
    _e in [MatchError, FunctionClauseError] -> :ok
  end
end
