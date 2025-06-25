defmodule Api.Todo do
  @moduledoc """
  The Todo schema represents a todo item in the application.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :title, :completed, :inserted_at, :updated_at]}
  @type t() :: %__MODULE__{
          id: integer(),
          title: String.t(),
          completed: boolean(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }
  schema "todos" do
    field(:title, :string)
    field(:completed, :boolean, default: false)
    timestamps()
  end

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title, :completed])
    |> validate_required([:title])
  end
end
