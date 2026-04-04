defmodule Francis.ErrorPageTest do
  use ExUnit.Case, async: true

  alias Francis.ErrorPage

  describe "render/1" do
    test "renders a 404 page" do
      html = ErrorPage.render(404)

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "404"
      assert html =~ "Not Found"
      assert html =~ "The page you are looking for does not exist."
    end

    test "renders a 500 page" do
      html = ErrorPage.render(500)

      assert html =~ "500"
      assert html =~ "Internal Server Error"
      assert html =~ "Something went wrong on our end."
    end

    test "renders a 400 page" do
      html = ErrorPage.render(400)

      assert html =~ "400"
      assert html =~ "Bad Request"
    end

    test "renders unknown status codes with generic message" do
      html = ErrorPage.render(418)

      assert html =~ "418"
      assert html =~ "Error"
      assert html =~ "An unexpected error occurred."
    end
  end

  describe "render/3" do
    test "renders a custom error page" do
      html = ErrorPage.render(503, "Maintenance", "We'll be back shortly.")

      assert html =~ "503"
      assert html =~ "Maintenance"
      assert html =~ "We&#39;ll be back shortly."
    end

    test "escapes HTML in title and message" do
      html = ErrorPage.render(500, "<script>alert('xss')</script>", "a & b")

      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>alert"
      assert html =~ "a &amp; b"
    end
  end

  describe "integration with default error handling" do
    test "404 response uses HTML error page" do
      mod = Support.RouteTester.generate_module(quote do: get("/", fn _ -> "test" end))

      response = Req.get!("/not_here", plug: mod)

      assert response.status == 404
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
      assert response.body =~ "Not Found"
      assert response.body =~ "<!DOCTYPE html>"
    end

    test "500 response uses HTML error page" do
      handler =
        quote do
          get("/", fn _ -> raise "test exception" end)
        end

      mod = Support.RouteTester.generate_module(handler)

      response = Req.get!("/", plug: mod, retry: false)

      assert response.status == 500
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
      assert response.body =~ "Internal Server Error"
      assert response.body =~ "<!DOCTYPE html>"
    end
  end
end
