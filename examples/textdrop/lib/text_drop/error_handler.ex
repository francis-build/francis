defmodule TextDrop.ErrorHandler do
  @moduledoc """
  Sends error responses: HTML pages, or JSON under `/api/`.

  Francis calls `handle/2` with the `{:error, reason}` tuples returned by
  handlers, with exceptions raised anywhere in the pipeline (including
  `Plug.Parsers` errors raised before routing), or with `{kind, reason}` for
  throws and exits. `TextDrop.Errors` says what each one means.
  """

  import Francis.ResponseHandlers, only: [html: 3, json: 3]

  require Logger

  alias Francis.ErrorPage
  alias TextDrop.Errors

  @spec handle(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def handle(conn, {:error, reason}), do: respond(conn, reason)
  def handle(conn, reason), do: respond(conn, reason)

  defp respond(conn, reason) do
    {status, _title, _message} = description = Errors.describe(reason)
    if status >= 500, do: Logger.error("Unhandled error: #{inspect(reason)}")
    render(conn, description)
  end

  defp render(%Plug.Conn{request_path: "/api/" <> _} = conn, {status, title, message}) do
    json(conn, status, %{
      error: title || Plug.Conn.Status.reason_phrase(status),
      message: message || "The request could not be completed."
    })
  end

  defp render(conn, {status, nil, nil}), do: html(conn, status, ErrorPage.render(status))

  defp render(conn, {status, title, message}),
    do: html(conn, status, ErrorPage.render(status, title, message))
end
