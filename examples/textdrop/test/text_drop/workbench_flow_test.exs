defmodule TextDrop.WorkbenchFlowTest do
  @moduledoc "Upload a PDF through the router and drive the document page and its API."

  use ExUnit.Case, async: true

  @moduletag :integration

  import Plug.Conn
  import Plug.Test

  alias TextDrop.Handlers.Documents
  alias TextDrop.PdfFixture
  alias TextDrop.Router

  @opts Router.init([])

  defp request(conn), do: Router.call(conn, @opts)

  defp json!(conn), do: Jason.decode!(conn.resp_body)

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> request()
  end

  setup_all do
    dir = Path.join(System.tmp_dir!(), "textdrop-flow-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    conn = request(conn(:post, "/", %{"pdf" => PdfFixture.upload(dir)}))
    assert conn.status == 303
    assert ["/documents/" <> id] = get_resp_header(conn, "location")

    on_exit(fn ->
      Documents.delete(id)
      File.rm_rf!(dir)
    end)

    %{id: id}
  end

  test "the document page shows the metadata and page tables", %{id: id} do
    conn = request(conn(:get, "/documents/#{id}"))

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-document-id="#{id}")

    for {label, value} <- PdfFixture.metadata() do
      assert conn.resp_body =~ "<th scope=\"row\">#{label}</th><td>#{value}</td>"
    end

    assert conn.resp_body =~ "<td>612 pt</td>"
    assert conn.resp_body =~ "<td>792 pt</td>"
    assert conn.resp_body =~ ~s(src="/assets/js/workbench.js")
  end

  test "the page text is returned as JSON, escaped by the encoder", %{id: id} do
    conn = request(conn(:get, "/api/documents/#{id}/pages/0/text"))

    assert conn.status == 200
    assert %{"page" => 0, "layout" => false, "text" => text} = json!(conn)
    assert text =~ PdfFixture.text()

    conn = request(conn(:get, "/api/documents/#{id}/pages/0/text?layout=true"))
    assert %{"layout" => true, "text" => laid_out} = json!(conn)
    assert laid_out =~ "Hello"
  end

  test "areas come back with their text", %{id: id} do
    areas = [
      %{left: 60, top: 50, right: 400, bottom: 110},
      %{left: 0, top: 400, right: 612, bottom: 792}
    ]

    conn = post_json("/api/documents/#{id}/pages/0/areas", %{areas: areas})

    assert conn.status == 200

    assert %{"areas" => [%{"left" => 60, "text" => text}, %{"top" => 400, "text" => ""}]} =
             json!(conn)

    assert text =~ "Hello"
  end

  test "words carry their font", %{id: id} do
    conn = request(conn(:get, "/api/documents/#{id}/pages/0/words"))

    assert conn.status == 200
    assert %{"words" => words} = json!(conn)
    assert Enum.any?(words, &(&1["text"] == "Hello" and &1["font_name"] == "Helvetica"))
  end

  test "tables are searched with the chosen strategies", %{id: id} do
    conn =
      request(
        conn(
          :get,
          "/api/documents/#{id}/pages/0/tables?vertical_strategy=text&horizontal_strategy=lines"
        )
      )

    assert conn.status == 200
    assert %{"page" => 0, "tables" => []} = json!(conn)

    conn = request(conn(:get, "/api/documents/#{id}/pages/0/tables?vertical_strategy=bogus"))
    assert conn.status == 400
    assert %{"error" => "Invalid vertical_strategy"} = json!(conn)
  end

  test "the page image is a cacheable PNG", %{id: id} do
    conn = request(conn(:get, "/api/documents/#{id}/pages/0/image?width=200"))

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "cache-control") == ["private, max-age=31536000, immutable"]
    assert <<137, 80, 78, 71, _::binary>> = conn.resp_body

    conn = request(conn(:get, "/api/documents/#{id}/pages/0/image?width=5"))
    assert conn.status == 400
    assert %{"error" => "Invalid width"} = json!(conn)
  end

  test "errors from the extractor are reported per request", %{id: id} do
    conn = request(conn(:get, "/api/documents/#{id}/pages/7/text"))
    assert conn.status == 400
    assert %{"error" => "Page out of range"} = json!(conn)

    conn = post_json("/api/documents/#{id}/pages/0/areas", %{areas: [%{left: "a"}]})
    assert conn.status == 400
    assert %{"error" => "Invalid areas"} = json!(conn)

    conn =
      post_json("/api/documents/#{id}/pages/0/areas", %{
        areas: [%{left: 700, top: 0, right: 900, bottom: 10}]
      })

    assert conn.status == 400
    assert %{"error" => "Invalid area"} = json!(conn)
  end
end
