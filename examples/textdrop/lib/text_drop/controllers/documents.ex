defmodule TextDrop.Controllers.Documents do
  @moduledoc "The document page with its workbench, and deleting a document."

  import Francis.ResponseHandlers, only: [html: 2, redirect: 3]

  alias TextDrop.Handlers.{Documents, Pdf}
  alias TextDrop.Views

  def show(%{params: %{"id" => id}} = conn) do
    with {:ok, path} <- Documents.fetch(id),
         {:ok, metadata} <- Pdf.metadata(path),
         {:ok, pages} <- Pdf.pages(path) do
      html(conn, Views.Documents.show(%{id: id, metadata: metadata, pages: pages}))
    end
  end

  @doc "Removes the document and sends the user back to the upload form with a notice."
  def delete(%{params: %{"id" => id}} = conn) do
    with {:ok, _path} <- Documents.fetch(id) do
      Documents.delete(id)
      redirect(conn, 303, "/?deleted=1")
    end
  end
end
