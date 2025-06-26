defmodule Api.RouterTest do
  use ExUnit.Case, async: true

  alias Api.Todo
  alias Api.Todos

  setup do
    Api.Repo.delete_all(Todo)
    :ok
  end

  describe "GET /todos" do
    test "returns all todos" do
      Todos.create_todo(%{"title" => "Test", "completed" => false})
      response = Req.get!("/todos", plug: Api.Router)

      assert response.status == 200
      assert is_list(response.body)
      assert length(response.body) == 1
      assert hd(response.body)["title"] == "Test"
      assert hd(response.body)["completed"] == false
    end
  end

  describe "GET /todos/:id" do
    test "returns a todo" do
      todo_attrs = %{"title" => "Test", "completed" => false}
      {:ok, %{id: id}} = Todos.create_todo(todo_attrs)
      response = Req.get!("/todos/#{id}", plug: Api.Router)

      assert response.status == 200
      assert response.body["id"] == id
      assert response.body["title"] == "Test"
      assert response.body["completed"] == false
    end

    test "returns 404 for non-existent todo" do
      response = Req.get!("/todos/999999", plug: Api.Router)
      assert response.status == 404
      assert response.body == "Not Found"
    end
  end

  describe "POST /todos" do
    test "creates a todo" do
      todo_attrs = %{"title" => "New Todo", "completed" => false}

      response = Req.post!("/todos", plug: Api.Router, json: todo_attrs)

      assert response.status == 201
      assert response.body["title"] == "New Todo"
      assert response.body["completed"] == false
      assert is_integer(response.body["id"])
    end

    test "returns 422 for invalid data" do
      # Missing required title (assuming title is required)
      todo_attrs = %{"completed" => false}

      response = Req.post!("/todos", plug: Api.Router, json: todo_attrs)

      assert response.status == 422
      assert Map.has_key?(response.body, "errors")
    end
  end

  describe "PUT /todos/:id" do
    test "updates a todo" do
      {:ok, %{id: id}} = Todos.create_todo(%{"title" => "Old Title", "completed" => false})
      update_attrs = %{"title" => "Updated Title", "completed" => true}

      response = Req.put!("/todos/#{id}", plug: Api.Router, json: update_attrs)

      assert response.status == 204
      assert response.body["title"] == "Updated Title"
      assert response.body["completed"] == true
      assert response.body["id"] == id
    end

    test "returns 404 for non-existent todo" do
      response = Req.put!("/todos/999999", plug: Api.Router, json: %{"title" => "Updated"})
      assert response.status == 404
      assert response.body == "Not Found"
    end

    test "returns 422 for invalid data" do
      {:ok, %{id: id}} = Todos.create_todo(%{"title" => "Old Title", "completed" => false})

      # Invalid type for completed
      update_attrs = %{"completed" => 1}

      response = Req.put!("/todos/#{id}", plug: Api.Router, json: update_attrs)

      assert response.status == 422
      assert Map.has_key?(response.body, "errors")
    end
  end

  describe "DELETE /todos/:id" do
    test "deletes a todo" do
      {:ok, todo} = Todos.create_todo(%{"title" => "To Delete", "completed" => false})

      response = Req.delete!("/todos/#{todo.id}", plug: Api.Router)

      assert response.status == 204
      assert response.body == ""
    end

    test "returns 404 for non-existent todo" do
      response = Req.delete!("/todos/999999", plug: Api.Router)

      assert response.status == 404
      assert response.body == "Not Found"
    end
  end

  describe "unmatched routes" do
    test "returns 404 for unmatched routes" do
      response = Req.get!("/nonexistent", plug: Api.Router)

      assert response.status == 404
      assert response.body == "Not Found"
    end
  end
end
