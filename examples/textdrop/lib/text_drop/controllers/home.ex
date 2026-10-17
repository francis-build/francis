defmodule TextDrop.Controllers.Home do
  @moduledoc "The upload form, the about page, and the upload itself."

  import Francis.ResponseHandlers, only: [html: 2, redirect: 3]

  alias TextDrop.Handlers.Documents
  alias TextDrop.Views

  def index(%{params: params} = conn) do
    html(conn, Views.Home.index(%{deleted: Map.has_key?(params, "deleted")}))
  end

  def about(conn), do: html(conn, Views.Home.about())

  def create(%{params: %{"pdf" => %Plug.Upload{} = upload}} = conn) do
    with {:ok, id} <- Documents.store(upload) do
      redirect(conn, 303, "/documents/#{id}")
    end
  end

  def create(_conn), do: {:error, :missing_pdf}
end
