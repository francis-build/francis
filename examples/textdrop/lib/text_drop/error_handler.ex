defmodule TextDrop.ErrorHandler do
  @moduledoc """
  Turns errors into error responses: HTML pages, or JSON under `/api/`.

  Francis calls `handle/2` with the `{:error, reason}` tuples returned by
  handlers, with exceptions raised anywhere in the pipeline (including
  `Plug.Parsers` errors raised before routing), or with `{kind, reason}` for
  throws and exits.
  """

  import Francis.ResponseHandlers, only: [html: 3, json: 3]

  require Logger

  alias Francis.ErrorPage

  @spec handle(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def handle(conn, {:error, reason}), do: respond(conn, describe(reason))

  def handle(conn, %Plug.Parsers.RequestTooLargeError{}) do
    respond(conn, {413, "File too large", "PDF uploads are limited to 20 MB."})
  end

  def handle(conn, %Plug.Parsers.ParseError{}) do
    respond(conn, {400, "Malformed request", "The request body could not be parsed."})
  end

  def handle(conn, exception) when is_exception(exception) do
    status = Plug.Exception.status(exception)
    if status >= 500, do: Logger.error("Unhandled error: #{inspect(exception)}")
    respond(conn, {status, nil, nil})
  end

  def handle(conn, reason) do
    Logger.error("Unhandled error: #{inspect(reason)}")
    respond(conn, {500, nil, nil})
  end

  defp describe(:not_found),
    do: {404, "Document not found", "This upload does not exist. Upload the PDF again."}

  defp describe(:page_out_of_range),
    do: {400, "Page out of range", "This document has no page with that number."}

  defp describe(:missing_pdf),
    do: {400, "No PDF uploaded", "Choose a PDF file before submitting the form."}

  defp describe(:unreadable),
    do: {422, "Could not read PDF", "The file could not be parsed as a PDF document."}

  defp describe(:invalid_area),
    do: {400, "Invalid area", "Each area must have a width and a height inside the page."}

  defp describe({:invalid, field}),
    do: {400, "Invalid #{field}", "The #{field} parameter is not valid."}

  defp describe(reason) do
    Logger.error("Unhandled error: #{inspect(reason)}")
    {500, nil, nil}
  end

  defp respond(%Plug.Conn{request_path: "/api/" <> _} = conn, {status, title, message}) do
    json(conn, status, %{
      error: title || Plug.Conn.Status.reason_phrase(status),
      message: message || "The request could not be completed."
    })
  end

  defp respond(conn, {status, nil, nil}), do: html(conn, status, ErrorPage.render(status))

  defp respond(conn, {status, title, message}),
    do: html(conn, status, ErrorPage.render(status, title, message))
end
