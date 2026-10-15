defmodule Francis.ResponseHandlersTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Francis.ResponseHandlers

  defp location(path) do
    conn(:get, "/")
    |> ResponseHandlers.redirect(path)
    |> Plug.Conn.get_resp_header("location")
  end

  describe "redirect/2 open redirect protection" do
    for payload <- [
          "//evil.com",
          "///evil.com",
          "/\\evil.com",
          "\\\\evil.com",
          "/\t/evil.com",
          "/\n/evil.com",
          "/\r/evil.com",
          "/\0/evil.com",
          "/\x7F/evil.com",
          " //evil.com",
          "\t//evil.com"
        ] do
      test "neutralizes #{inspect(payload)} to /" do
        assert location(unquote(payload)) == ["/"]
      end
    end

    test "passes through an encoded backslash without making it protocol-relative" do
      assert [location] = location("/%5Cevil.com")
      refute String.starts_with?(location, "//")
      assert %URI{host: nil, scheme: nil} = URI.parse(location)
    end

    test "keeps regular relative paths" do
      assert location("/new_path?a=1#top") == ["/new_path?a=1#top"]
      assert location("new_path") == ["new_path"]
    end

    test "still raises on absolute URLs" do
      assert_raise ArgumentError, fn -> location("https://evil.com") end
    end
  end

  describe "redirect/3 open redirect protection" do
    test "neutralizes backslash and control character payloads" do
      for payload <- ["/\\evil.com", "/\t/evil.com", "/\n/evil.com"] do
        conn = ResponseHandlers.redirect(conn(:get, "/"), 301, payload)

        assert conn.status == 301
        assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
      end
    end
  end
end
