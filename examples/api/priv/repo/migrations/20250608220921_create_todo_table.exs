defmodule Api.Repo.Migrations.CreateTodoTable do
  use Ecto.Migration

  def up do
    create table(:todos) do
      add(:title, :string, null: false)
      add(:completed, :boolean, default: false, null: false)
      timestamps()
    end
  end
end
