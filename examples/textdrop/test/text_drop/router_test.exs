defmodule TextDrop.RouterTest do
  @moduledoc "Routes and error responses that need no PDF, and therefore no Python."

  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TextDrop.Router

  @opts Router.init([])
  @unknown_id String.duplicate("0", 32)

  defp request(conn), do: Router.call(conn, @opts)

  defp json!(conn), do: Jason.decode!(conn.resp_body)

  describe "pages" do
    test "GET / renders the upload form as HTML with security headers" do
      conn = request(conn(:get, "/"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert conn.resp_body =~ "Open Any PDF File"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "script-src 'self'"
    end

    test "GET /about renders the about page with asset paths from static_path/1" do
      conn = request(conn(:get, "/about"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert conn.resp_body =~ ~s(href="/assets/css/simple)
    end

    test "GET /health answers in plain text" do
      conn = request(conn(:get, "/health"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert conn.resp_body == "OK"
    end

    test "unknown routes get a 404 HTML page" do
      conn = request(conn(:get, "/nope"))

      assert conn.status == 404
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert conn.resp_body =~ "Not Found"
    end

    test "unknown API routes get a 404 JSON body" do
      conn = request(conn(:get, "/api/nope"))

      assert conn.status == 404
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      assert %{"error" => "Not Found"} = json!(conn)
    end
  end

  describe "documents" do
    test "GET /documents/:id with an unknown id is not found" do
      conn = request(conn(:get, "/documents/#{@unknown_id}"))

      assert conn.status == 404
      assert conn.resp_body =~ "Document not found"
    end

    test "GET /documents/:id with an id of the wrong shape is not found" do
      conn = request(conn(:get, "/documents/not-a-real-id"))

      assert conn.status == 404
      assert conn.resp_body =~ "Document not found"
    end

    test "POST /documents/:id/delete with an unknown id is not found" do
      conn = request(conn(:post, "/documents/#{@unknown_id}/delete"))

      assert conn.status == 404
      assert conn.resp_body =~ "Document not found"
    end

    test "POST / without a PDF is rejected" do
      conn = request(conn(:post, "/", %{"page" => "0"}))

      assert conn.status == 400
      assert conn.resp_body =~ "No PDF uploaded"
    end
  end

  describe "API errors" do
    test "are JSON" do
      conn = request(conn(:get, "/api/documents/#{@unknown_id}/pages/0/text"))

      assert conn.status == 404
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      assert %{"error" => "Document not found", "message" => "This upload" <> _} = json!(conn)
    end

    test "reject a page that is not a non-negative integer" do
      conn = request(conn(:get, "/api/documents/#{@unknown_id}/pages/abc/words"))

      assert conn.status == 400
      assert %{"error" => "Invalid page"} = json!(conn)
    end
  end
end
