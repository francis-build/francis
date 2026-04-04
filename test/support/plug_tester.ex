defmodule Support.PlugTester do
  @moduledoc """
  Plug to test Francis plug applying order
  """
  import Plug.Conn
  def init(opts), do: opts

  def call(%{assigns: assigns} = conn, to_assign: to_assign) do
    case Map.get(assigns, :plug_assigned) do
      nil -> assign(conn, :plug_assigned, [to_assign])
      value -> assign(conn, :plug_assigned, value ++ [to_assign])
    end
  end
end
