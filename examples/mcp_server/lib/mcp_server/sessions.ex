defmodule McpServer.Sessions do
  @moduledoc """
  Simple ETS-based session registry that maps MCP session IDs to SSE transport PIDs.
  """

  @table __MODULE__

  def start do
    :ets.new(@table, [:named_table, :public, :set])
  end

  def register(session_id, transport_pid) do
    ensure_table()
    :ets.insert(@table, {session_id, transport_pid})
  end

  def unregister(session_id) do
    ensure_table()
    :ets.delete(@table, session_id)
  end

  def lookup(session_id) do
    ensure_table()

    case :ets.lookup(@table, session_id) do
      [{^session_id, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> start()
      _ -> :ok
    end
  end
end
