defmodule TextDrop.Controllers.Api do
  @moduledoc """
  JSON endpoints behind the workbench, all scoped to one page of one document.

  Errors are returned as JSON by `TextDrop.ErrorHandler` because the paths
  start with `/api/`.
  """

  import Francis.ResponseHandlers, only: [json: 2]
  import Plug.Conn, only: [put_resp_content_type: 3, put_resp_header: 3, send_resp: 3]

  alias TextDrop.Controllers.Params
  alias TextDrop.Handlers.{Documents, Pdf}

  @doc "PNG render of the page. Documents never change, so the image may be cached for a year."
  def page_image(%{params: params} = conn) do
    with {:ok, path, page} <- document_page(params),
         {:ok, width} <- Params.width(params["width"]),
         {:ok, png} <- Pdf.render(path, page, width) do
      conn
      |> put_resp_content_type("image/png", nil)
      |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
      |> send_resp(200, png)
    end
  end

  def page_text(%{params: params} = conn) do
    with {:ok, path, page} <- document_page(params),
         {:ok, layout} <- Params.boolean(params["layout"], :layout),
         {:ok, text} <- Pdf.text(path, page, layout: layout) do
      json(conn, %{page: page, layout: layout, text: text})
    end
  end

  def page_areas(%{params: params} = conn) do
    with {:ok, path, page} <- document_page(params),
         {:ok, areas} <- Params.areas(params["areas"]),
         {:ok, texts} <- Pdf.text_in_areas(path, page, areas) do
      results = Enum.zip_with(areas, texts, &(&1 |> Map.from_struct() |> Map.put(:text, &2)))
      json(conn, %{page: page, areas: results})
    end
  end

  def page_words(%{params: params} = conn) do
    with {:ok, path, page} <- document_page(params),
         {:ok, words} <- Pdf.words(path, page) do
      json(conn, %{page: page, words: words})
    end
  end

  def page_tables(%{params: params} = conn) do
    with {:ok, path, page} <- document_page(params),
         {:ok, vertical} <- Params.strategy(params["vertical_strategy"], :vertical_strategy),
         {:ok, horizontal} <- Params.strategy(params["horizontal_strategy"], :horizontal_strategy),
         {:ok, tables} <-
           Pdf.tables(path, page, vertical_strategy: vertical, horizontal_strategy: horizontal) do
      json(conn, %{page: page, tables: tables})
    end
  end

  defp document_page(params) do
    with {:ok, page} <- Params.page(params["page"]),
         {:ok, path} <- Documents.fetch(params["id"]) do
      {:ok, path, page}
    end
  end
end
