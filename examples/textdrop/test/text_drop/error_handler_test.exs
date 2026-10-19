defmodule TextDrop.ErrorHandlerTest do
  @moduledoc """
  Exercises the error handler directly. Errors raised before routing, such as
  parser errors, cannot be observed through `Plug.Test` because
  `Plug.ErrorHandler` re-raises them after the response is built.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias TextDrop.ErrorHandler

  defp page_conn, do: conn(:get, "/documents/abc")
  defp api_conn, do: conn(:get, "/api/documents/abc/pages/0/text")

  test "renders an HTML error page outside the API" do
    conn = ErrorHandler.handle(page_conn(), {:error, :not_found})

    assert conn.status == 404
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert conn.resp_body =~ "Document not found"
  end

  test "answers with JSON under /api/" do
    conn = ErrorHandler.handle(api_conn(), {:error, {:invalid, :page}})

    assert conn.status == 400
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    assert Jason.decode!(conn.resp_body) == %{
             "error" => "Invalid page",
             "message" => "The page parameter is not valid."
           }
  end

  test "maps parser errors to 413 and 400" do
    too_large = %Plug.Parsers.RequestTooLargeError{}
    assert %{status: 413} = conn = ErrorHandler.handle(page_conn(), too_large)
    assert conn.resp_body =~ "File too large"

    malformed = %Plug.Parsers.ParseError{exception: %RuntimeError{message: "unexpected byte"}}
    assert %{status: 400} = conn = ErrorHandler.handle(api_conn(), malformed)
    assert %{"error" => "Malformed request"} = Jason.decode!(conn.resp_body)
  end

  test "uses the status of other exceptions and falls back to 500" do
    assert %{status: 405} =
             ErrorHandler.handle(api_conn(), %Plug.BadRequestError{plug_status: 405})

    log =
      capture_log(fn ->
        assert %{status: 500} =
                 conn = ErrorHandler.handle(api_conn(), %RuntimeError{message: "boom"})

        assert %{"error" => "Internal Server Error"} = Jason.decode!(conn.resp_body)
        assert %{status: 500} = ErrorHandler.handle(page_conn(), {:exit, :shutdown})
      end)

    assert log =~ "Unhandled error"
  end
end
