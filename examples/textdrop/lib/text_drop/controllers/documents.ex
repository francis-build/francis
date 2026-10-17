defmodule TextDrop.Controllers.Documents do
  @moduledoc "The document page: metadata, page list and the workbench."

  import Francis.ResponseHandlers, only: [html: 2]

  alias TextDrop.Handlers.{Documents, Pdf}
  alias TextDrop.Views

  def show(%{params: %{"id" => id}} = conn) do
    with {:ok, path} <- Documents.fetch(id),
         {:ok, metadata} <- Pdf.metadata(path),
         {:ok, pages} <- Pdf.pages(path) do
      html(conn, Views.Documents.show(%{id: id, metadata: metadata, pages: pages}))
    end
  end
end
