defmodule Chat.Room do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end

  def join(transport) do
    Agent.update(__MODULE__, &MapSet.put(&1, transport))
  end

  def leave(transport) do
    Agent.update(__MODULE__, &MapSet.delete(&1, transport))
  end

  def broadcast(message) do
    Agent.get(__MODULE__, & &1)
    |> Enum.each(fn transport ->
      send(transport, message)
    end)
  end
end
