defmodule Francis.Plug.CSPTest do
  use ExUnit.Case, async: true

  alias Francis.Plug.CSP

  describe "init/1" do
    test "generates default policy" do
      config = CSP.init([])

      assert config.report_only == false
      assert config.policy =~ "default-src 'self'"
      assert config.policy =~ "script-src 'self'"
      assert config.policy =~ "style-src 'self'"
      assert config.policy =~ "img-src 'self' data:"
      assert config.policy =~ "object-src 'none'"
      assert config.policy =~ "frame-ancestors 'none'"
    end

    test "merges custom directives with defaults" do
      config = CSP.init(directives: %{"script-src" => "'self' https://cdn.example.com"})

      assert config.policy =~ "script-src 'self' https://cdn.example.com"
      assert config.policy =~ "default-src 'self'"
    end

    test "enables report-only mode" do
      config = CSP.init(report_only: true)

      assert config.report_only == true
    end
  end

  describe "call/2" do
    test "sets content-security-policy header" do
      handler =
        quote do
          plug(Francis.Plug.CSP)
          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      [csp] = response.headers["content-security-policy"]
      assert csp =~ "default-src 'self'"
      assert csp =~ "script-src 'self'"
      assert csp =~ "object-src 'none'"
    end

    test "sets report-only header when configured" do
      handler =
        quote do
          plug(Francis.Plug.CSP, report_only: true)
          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      assert response.headers["content-security-policy-report-only"] != nil
      assert response.headers["content-security-policy"] == nil
    end

    test "applies custom directives" do
      handler =
        quote do
          plug(Francis.Plug.CSP,
            directives: %{
              "script-src" => "'self' https://cdn.example.com",
              "report-uri" => "/csp-report"
            }
          )

          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler)
      response = Req.get!("/", plug: mod)

      [csp] = response.headers["content-security-policy"]
      assert csp =~ "script-src 'self' https://cdn.example.com"
      assert csp =~ "report-uri /csp-report"
    end
  end
end
