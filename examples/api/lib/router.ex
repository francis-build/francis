defmodule Api.Router do
  use Francis, error_handler: &__MODULE__.error/2
  alias Api.Todos

  get("/todos", fn _ -> Todos.list_todos() end)

  get("/todos/:id", fn %{params: %{"id" => id}} -> Todos.get_todo!(String.to_integer(id)) end)

  post("/todos", fn %{params: attrs} ->
    with {:ok, created} <- Todos.create_todo(attrs) do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(201, Jason.encode!(created))
    end
  end)

  put("/todos/:id", fn %{params: attrs} = conn ->
    with todo <- Todos.get_todo!(id),
         {:ok, updated} <- Todos.update_todo(todo, attrs) do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(204, Jason.encode!(updated))
    end
  end)

  delete("/todos/:id", fn conn ->
    %{params: %{"id" => id}} = conn
    todo = Todos.get_todo!(String.to_integer(id))

    with {:ok, _} <- Todos.delete_todo(todo) do
      send_resp(conn, 204, "")
    end
  end)

  unmatched(fn _ -> "not found" end)

  def error(conn, %Ecto.NoResultsError{}), do: send_resp(conn, 404, "")

  def error(conn, {:error, %Ecto.Changeset{errors: errors}}) do
    errors = Enum.map(errors, fn {field, {message, _}} -> %{field: field, message: message} end)

    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(422, Jason.encode!(%{errors: errors}))
  end
end
