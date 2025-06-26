defmodule Api.Router do
  use Francis, error_handler: &__MODULE__.error/2

  alias Api.Todos

  get("/todos", fn _ ->
    Todos.list_todos()
  end)

  get("/todos/:id", fn %{params: %{"id" => id}} ->
    Todos.get_todo!(String.to_integer(id))
  end)

  post("/todos", fn %{params: attrs} ->
    with {:ok, created} <- Todos.create_todo(attrs) do
      json(conn, 201, created)
    end
  end)

  put("/todos/:id", fn %{params: attrs} = conn ->
    with todo <- Todos.get_todo!(id),
         {:ok, updated} <- Todos.update_todo(todo, attrs) do
      json(conn, 204, updated)
    end
  end)

  delete("/todos/:id", fn %{params: %{"id" => id}} = conn ->
    with todo <- Todos.get_todo!(String.to_integer(id)),
         {:ok, _} <- Todos.delete_todo(todo) do
      text(conn, 204, "")
    end
  end)

  def error(conn, %Ecto.NoResultsError{}), do: text(conn, 404, "Not Found")

  def error(conn, {:error, %Ecto.Changeset{errors: errors}}) do
    errors = Enum.map(errors, fn {field, {message, _}} -> %{field: field, message: message} end)
    json(conn, 422, %{errors: errors})
  end
end
