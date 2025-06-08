defmodule Api.Router do
  use Francis
  alias Api.Todos

  # List all todos
  get("/todos", fn _ ->
    Todos.list_todos()
  end)

  # Get a single todo by ID
  get("/todos/:id", fn %{params: %{"id" => id}} ->
    try do
      Todos.get_todo!(String.to_integer(id))
    rescue
      Ecto.NoResultsError -> {:status, 404, %{error: "Not found"}}
    end
  end)

  # Create a new todo
  post("/todos", fn %{body: attrs} ->
    case Todos.create_todo(attrs) do
      {:ok, todo} -> {:status, 201, todo}
      {:error, changeset} -> {:status, 422, %{errors: changeset.errors}}
    end
  end)

  # Update a todo
  put("/todos/:id", fn %{params: %{"id" => id}, body: attrs} ->
    try do
      todo = Todos.get_todo!(String.to_integer(id))

      case Todos.update_todo(todo, attrs) do
        {:ok, updated} -> updated
        {:error, changeset} -> {:status, 422, %{errors: changeset.errors}}
      end
    rescue
      Ecto.NoResultsError -> {:status, 404, %{error: "Not found"}}
    end
  end)

  # Delete a todo
  delete("/todos/:id", fn %{params: %{"id" => id}} ->
    try do
      todo = Todos.get_todo!(String.to_integer(id))

      case Todos.delete_todo(todo) do
        {:ok, _} -> {:status, 204, ""}
        {:error, _} -> {:status, 422, %{error: "Could not delete"}}
      end
    rescue
      Ecto.NoResultsError -> {:status, 404, %{error: "Not found"}}
    end
  end)

  get("/", fn _ -> "ok" end)
  unmatched(fn _ -> "not found" end)
end
