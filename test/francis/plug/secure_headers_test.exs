defmodule Francis.Plug.SecureHeadersTest do
  use ExUnit.Case, async: true

  alias Francis.Plug.SecureHeaders

  describe "init/1" do
    test "returns default headers when no options given" do
      headers = SecureHeaders.init([])

      assert headers["x-content-type-options"] == "nosniff"
      assert headers["x-frame-options"] == "DENY"
      assert headers["x-xss-protection"] == "1; mode=block"
      assert headers["referrer-policy"] == "strict-origin-when-cross-origin"
      assert headers["permissions-policy"] == "camera=(), microphone=(), geolocation=()"
      assert headers["strict-transport-security"] == "max-age=63072000; includeSubDomains"
    end

    test "merges custom headers with defaults" do
      headers = SecureHeaders.init(headers: %{"x-frame-options" => "SAMEORIGIN"})

      assert headers["x-frame-options"] == "SAMEORIGIN"
      assert headers["x-content-type-options"] == "nosniff"
    end

    test "allows adding new headers" do
      headers = SecureHeaders.init(headers: %{"x-custom" => "value"})

      assert headers["x-custom"] == "value"
      assert headers["x-content-type-options"] == "nosniff"
    end
  end

  describe "call/2" do
    test "sets all default security headers" do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert response.headers["x-frame-options"] == ["DENY"]
      assert response.headers["x-xss-protection"] == ["1; mode=block"]
      assert response.headers["referrer-policy"] == ["strict-origin-when-cross-origin"]

      assert response.headers["permissions-policy"] == [
               "camera=(), microphone=(), geolocation=()"
             ]
    end

    test "sets custom headers when configured" do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders, headers: %{"x-frame-options" => "SAMEORIGIN"})
          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.headers["x-frame-options"] == ["SAMEORIGIN"]
      assert response.headers["x-content-type-options"] == ["nosniff"]
    end
  end
end
