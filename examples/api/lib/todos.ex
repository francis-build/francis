defmodule Api.Todos do
  @moduledoc """
  The Todos context manages the todo items in the application.
  """
  alias Api.Repo
  alias Api.Todo

  @doc """
  Lists all todo items.
  """
  @spec list_todos() :: [Todo.t()]
  def list_todos, do: Repo.all(Todo)

  @doc """
  Gets a todo item by ID.
  """
  @spec get_todo!(integer) :: Todo.t()
  def get_todo!(id), do: Repo.get!(Todo, id)

  @doc """
  Creates a new todo item with the given attributes.
  """
  @spec create_todo(map) :: {:ok, Todo.t()} | {:error, Ecto.Changeset.t()}
  def create_todo(attrs), do: Repo.insert(Todo.changeset(%Todo{}, attrs))

  @doc """
  Updates an existing todo item with the given attributes.
  """
  @spec update_todo(Todo.t(), map) :: {:ok, Todo.t()} | {:error, Ecto.Changeset.t()}
  def update_todo(%Todo{} = todo, attrs), do: todo |> Todo.changeset(attrs) |> Repo.update()

  @doc """
  Deletes a todo item.
  """
  @spec delete_todo(Todo.t()) :: {:ok, Todo.t()} | {:error, Ecto.Changeset.t()}
  def delete_todo(%Todo{} = todo), do: Repo.delete(todo)
end
