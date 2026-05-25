# phoenix_embed

Shows how to embed a Francis router inside a Phoenix application.

Phoenix's `forward/2` macro accepts any Plug, and `use Francis` builds a
Plug under the hood — so the integration needs exactly **one line** in the
Phoenix router and a normal Francis module.

## How it works

### 1. Phoenix router (`lib/phoenix_embed_web/router.ex`)

```elixir
forward "/api", PhoenixEmbedWeb.FrancisApi
```

Phoenix strips the `/api` prefix before dispatching, so Francis routes are
relative: a client hits `GET /api/items` and Francis sees `GET /items`.

### 2. Francis module (`lib/phoenix_embed_web/francis_api.ex`)

```elixir
defmodule PhoenixEmbedWeb.FrancisApi do
  use Francis

  get "/items", fn _conn -> @items end

  get "/items/:id", fn conn ->
    id = String.to_integer(conn.params["id"])
    case Enum.find(@items, &(&1.id == id)) do
      nil  -> json(conn, 404, %{error: "not found"})
      item -> item
    end
  end

  unmatched(fn conn -> json(conn, 404, %{error: "not found"}) end)
end
```

`use Francis` also injects `use Application`, but that only matters when
Francis runs standalone. Here Phoenix owns the server and `start/2` is
never called.

## Running

```bash
mix deps.get
mix phx.server
```

```bash
# list all items
curl http://localhost:4000/api/items

# get a single item
curl http://localhost:4000/api/items/2

# 404 from Francis
curl http://localhost:4000/api/items/99

# 200 from Phoenix (the normal home page is still served)
curl http://localhost:4000/
```
