defmodule PhoenixEmbedWeb.FrancisApi do
  @moduledoc """
  A Francis router embedded inside a Phoenix application.

  Phoenix forwards requests to this module via:

      forward "/api", PhoenixEmbedWeb.FrancisApi

  Francis is a Plug under the hood, so it drops straight into the Phoenix
  router with no extra setup.  Phoenix strips the "/api" prefix before
  dispatching, so routes here are relative — `/items` is reached at
  `GET /api/items` from the outside world.

  Note: `use Francis` also injects `use Application`, but that only matters
  when Francis runs standalone.  Here Phoenix owns the server, and `start/2`
  is never called.
  """

  use Francis

  # A simple in-memory store so the example has something to demo.
  # In a real app you would talk to Ecto / a GenServer / etc.
  @items [
    %{id: 1, name: "Elixir"},
    %{id: 2, name: "Phoenix"},
    %{id: 3, name: "Francis"}
  ]

  get("/items", fn _conn ->
    @items
  end)

  get("/items/:id", fn conn ->
    id = String.to_integer(conn.params["id"])

    case Enum.find(@items, &(&1.id == id)) do
      nil -> json(conn, 404, %{error: "not found"})
      item -> item
    end
  end)

  unmatched(fn conn -> json(conn, 404, %{error: "not found"}) end)
end
