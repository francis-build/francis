defmodule Api.RouterTest do
  use ExUnit.Case, async: true

  alias Api.Repo
  alias Api.Todos

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "GET /todos returns all todos" do
    todo = Todos.create_todo(%{"title" => "Test", "completed" => false}) |> elem(1)
    assert Todos.list_todos() == [todo]
  end

  test "GET /todos/:id returns a todo" do
    {:ok, todo} = Todos.create_todo(%{"title" => "Test", "completed" => false})
    assert Todos.get_todo!(todo.id).id == todo.id
  end

  test "POST /todos creates a todo" do
    {:ok, todo} = Todos.create_todo(%{"title" => "New", "completed" => false})
    assert todo.title == "New"
    assert todo.completed == false
  end

  test "PUT /todos/:id updates a todo" do
    {:ok, todo} = Todos.create_todo(%{"title" => "Old", "completed" => false})
    {:ok, updated} = Todos.update_todo(todo, %{"title" => "Updated"})
    assert updated.title == "Updated"
  end

  test "DELETE /todos/:id deletes a todo" do
    {:ok, todo} = Todos.create_todo(%{"title" => "Delete", "completed" => false})
    {:ok, _} = Todos.delete_todo(todo)
    assert_raise Ecto.NoResultsError, fn -> Todos.get_todo!(todo.id) end
  end
end
