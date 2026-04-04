defmodule FrancisE2ETest do
  @moduledoc """
  End-to-end tests that boot a real Bandit HTTP server and make actual
  HTTP requests over the network, exercising the full request/response
  lifecycle including middleware, headers, and error handling.
  """
  use ExUnit.Case

  @moduletag :e2e

  import ExUnit.CaptureLog

  setup do
    port = Enum.random(10_000..20_000)

    on_exit(fn ->
      case System.cmd("lsof", ["-ti", ":#{port}"], stderr_to_stdout: true) do
        {pid_str, 0} when pid_str != "" ->
          pid = String.trim(pid_str) |> String.to_integer()
          System.cmd("kill", ["-INT", to_string(pid)])
          Process.sleep(100)

        _ ->
          :ok
      end
    end)

    %{port: port}
  end

  describe "e2e: HTML response handlers" do
    @tag :capture_log
    test "html/2 serves HTML with correct headers over HTTP", %{port: port} do
      handler =
        quote do
          get("/", fn conn -> html(conn, "<h1>Hello, World!</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]

      assert Req.Response.get_header(response, "cache-control") == [
               "no-cache, no-store, must-revalidate"
             ]

      assert response.body == "<h1>Hello, World!</h1>"
    end

    @tag :capture_log
    test "html/3 serves HTML with custom status over HTTP", %{port: port} do
      handler =
        quote do
          get("/", fn conn -> html(conn, 201, "<h1>Created</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 201
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]

      assert Req.Response.get_header(response, "cache-control") == [
               "no-cache, no-store, must-revalidate"
             ]
    end

    @tag :capture_log
    test "safe_html/2 escapes content and serves over HTTP", %{port: port} do
      handler =
        quote do
          get("/", fn conn ->
            safe_html(conn, "<script>alert('xss')</script>")
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]
      assert response.body == "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
      refute response.body =~ "<script>"
    end

    @tag :capture_log
    test "safe_html/3 escapes content with custom status over HTTP", %{port: port} do
      handler =
        quote do
          get("/", fn conn ->
            safe_html(conn, 201, "<img src=x onerror=alert(1)>")
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 201
      assert response.body == "&lt;img src=x onerror=alert(1)&gt;"
      refute response.body =~ "<img"
    end
  end

  describe "e2e: secure headers plug" do
    @tag :capture_log
    test "sets all default security headers on responses", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          get("/", fn conn -> html(conn, "<h1>Secure</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
      assert Req.Response.get_header(response, "x-frame-options") == ["DENY"]
      assert Req.Response.get_header(response, "x-xss-protection") == ["1; mode=block"]

      assert Req.Response.get_header(response, "referrer-policy") == [
               "strict-origin-when-cross-origin"
             ]

      assert Req.Response.get_header(response, "permissions-policy") == [
               "camera=(), microphone=(), geolocation=()"
             ]
    end

    @tag :capture_log
    test "allows overriding specific security headers", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders,
            headers: %{"x-frame-options" => "SAMEORIGIN", "x-custom" => "my-value"}
          )

          get("/", fn conn -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert Req.Response.get_header(response, "x-frame-options") == ["SAMEORIGIN"]
      assert Req.Response.get_header(response, "x-custom") == ["my-value"]
      # defaults still present
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
    end

    @tag :capture_log
    test "secure headers present on JSON responses too", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          get("/api", fn conn -> json(conn, %{ok: true}) end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/api")

      assert response.status == 200
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
      assert Req.Response.get_header(response, "x-frame-options") == ["DENY"]
    end
  end

  describe "e2e: CSP plug" do
    @tag :capture_log
    test "sets default content-security-policy header", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.CSP)
          get("/", fn conn -> html(conn, "<h1>CSP</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      [csp] = Req.Response.get_header(response, "content-security-policy")
      assert csp =~ "default-src 'self'"
      assert csp =~ "script-src 'self'"
      assert csp =~ "object-src 'none'"
      assert csp =~ "frame-ancestors 'none'"
    end

    @tag :capture_log
    test "supports custom CSP directives", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.CSP,
            directives: %{
              "script-src" => "'self' https://cdn.example.com",
              "connect-src" => "'self' https://api.example.com"
            }
          )

          get("/", fn conn -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      [csp] = Req.Response.get_header(response, "content-security-policy")
      assert csp =~ "script-src 'self' https://cdn.example.com"
      assert csp =~ "connect-src 'self' https://api.example.com"
      # defaults still present
      assert csp =~ "default-src 'self'"
    end

    @tag :capture_log
    test "report-only mode uses correct header", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.CSP, report_only: true)
          get("/", fn conn -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert Req.Response.get_header(response, "content-security-policy-report-only") != []
      assert Req.Response.get_header(response, "content-security-policy") == []
    end
  end

  describe "e2e: HTML error pages" do
    @tag :capture_log
    test "404 returns styled HTML error page", %{port: port} do
      handler =
        quote do
          get("/", fn _ -> "home" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/nonexistent", retry: false)

      assert response.status == 404
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]
      assert response.body =~ "<!DOCTYPE html>"
      assert response.body =~ "404"
      assert response.body =~ "Not Found"
    end

    @tag :capture_log
    test "500 returns styled HTML error page", %{port: port} do
      handler =
        quote do
          get("/", fn _ -> raise "boom" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/", retry: false)

      assert response.status == 500
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]
      assert response.body =~ "<!DOCTYPE html>"
      assert response.body =~ "Internal Server Error"
    end

    @tag :capture_log
    test "custom error handler still works over HTTP", %{port: port} do
      handler =
        quote do
          get("/", fn _ -> {:error, :not_authorized} end)
        end

      defmodule E2ECustomErrorHandler do
        import Plug.Conn

        def handle(conn, {:error, :not_authorized}) do
          send_resp(conn, 403, "Forbidden")
        end
      end

      mod =
        Support.RouteTester.generate_module(handler,
          bandit_opts: [port: port],
          error_handler: &E2ECustomErrorHandler.handle/2
        )

      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/", retry: false)

      assert response.status == 403
      assert response.body == "Forbidden"
    end
  end

  describe "e2e: combined security middleware stack" do
    @tag :capture_log
    test "secure headers + CSP work together on HTML responses", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          plug(Francis.Plug.CSP)
          get("/", fn conn -> html(conn, "<h1>Fully Secured</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200
      assert response.body == "<h1>Fully Secured</h1>"

      # Security headers
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
      assert Req.Response.get_header(response, "x-frame-options") == ["DENY"]
      assert Req.Response.get_header(response, "x-xss-protection") == ["1; mode=block"]

      assert Req.Response.get_header(response, "referrer-policy") == [
               "strict-origin-when-cross-origin"
             ]

      # CSP header
      [csp] = Req.Response.get_header(response, "content-security-policy")
      assert csp =~ "default-src 'self'"

      # HTML-specific headers
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]

      assert Req.Response.get_header(response, "cache-control") == [
               "no-cache, no-store, must-revalidate"
             ]
    end

    @tag :capture_log
    test "full stack with safe_html escaping", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          plug(Francis.Plug.CSP)

          get("/", fn conn ->
            safe_html(conn, "<script>document.cookie</script>")
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200
      # XSS payload is escaped
      refute response.body =~ "<script>"
      assert response.body =~ "&lt;script&gt;"

      # All security headers present
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
      [csp] = Req.Response.get_header(response, "content-security-policy")
      assert csp =~ "script-src 'self'"
    end

    @tag :capture_log
    test "security headers present even on error pages", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          plug(Francis.Plug.CSP)
          get("/", fn _ -> "home" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/nonexistent", retry: false)

      assert response.status == 404
      assert response.body =~ "Not Found"

      # Security headers should still be set by the plug pipeline
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
      assert Req.Response.get_header(response, "x-frame-options") == ["DENY"]
      [csp] = Req.Response.get_header(response, "content-security-policy")
      assert csp =~ "default-src 'self'"
    end
  end

  describe "e2e: static file serving" do
    @describetag :tmp_dir

    @tag :capture_log
    test "serves static files with correct content type over HTTP", %{
      port: port,
      tmp_dir: tmp_dir
    } do
      static_dir = Path.join(tmp_dir, "static")
      File.mkdir_p!(static_dir)
      File.write!(Path.join(static_dir, "style.css"), "body { margin: 0; }")

      handler = quote do: unmatched(fn _ -> "" end)

      mod =
        Support.RouteTester.generate_module(handler,
          bandit_opts: [port: port],
          static: [at: "/", from: static_dir]
        )

      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/style.css")

      assert response.status == 200
      assert response.body == "body { margin: 0; }"
    end

    @tag :capture_log
    test "returns 404 HTML page for missing static files", %{port: port, tmp_dir: tmp_dir} do
      static_dir = Path.join(tmp_dir, "static")
      File.mkdir_p!(static_dir)

      handler = quote do: get("/", fn _ -> "home" end)

      mod =
        Support.RouteTester.generate_module(handler,
          bandit_opts: [port: port],
          static: [at: "/assets", from: static_dir]
        )

      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/assets/missing.css", retry: false)

      assert response.status == 404
      assert response.body =~ "Not Found"
    end
  end

  describe "e2e: multiple routes and response types" do
    @tag :capture_log
    test "serves HTML, JSON, and text from different routes", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)

          get("/html", fn conn -> html(conn, "<h1>HTML Page</h1>") end)
          get("/json", fn conn -> json(conn, %{message: "hello"}) end)
          get("/text", fn conn -> text(conn, "plain text") end)

          get("/safe", fn conn ->
            safe_html(conn, "<b>user input: <script>bad</script></b>")
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      # HTML route
      html_resp = Req.get!("http://localhost:#{port}/html")
      assert html_resp.status == 200
      assert html_resp.body == "<h1>HTML Page</h1>"
      assert Req.Response.get_header(html_resp, "content-type") == ["text/html; charset=utf-8"]

      assert Req.Response.get_header(html_resp, "cache-control") == [
               "no-cache, no-store, must-revalidate"
             ]

      assert Req.Response.get_header(html_resp, "x-content-type-options") == ["nosniff"]

      # JSON route
      json_resp = Req.get!("http://localhost:#{port}/json")
      assert json_resp.status == 200
      assert json_resp.body == %{"message" => "hello"}

      assert Req.Response.get_header(json_resp, "content-type") == [
               "application/json; charset=utf-8"
             ]

      assert Req.Response.get_header(json_resp, "x-content-type-options") == ["nosniff"]

      # Text route
      text_resp = Req.get!("http://localhost:#{port}/text")
      assert text_resp.status == 200
      assert text_resp.body == "plain text"
      assert Req.Response.get_header(text_resp, "content-type") == ["text/plain; charset=utf-8"]

      # Safe HTML route
      safe_resp = Req.get!("http://localhost:#{port}/safe")
      assert safe_resp.status == 200
      refute safe_resp.body =~ "<script>"
      assert safe_resp.body =~ "&lt;script&gt;"
    end

    @tag :capture_log
    test "POST, PUT, DELETE routes work over HTTP", %{port: port} do
      handler =
        quote do
          post("/create", fn conn -> json(conn, 201, %{created: true}) end)
          put("/update", fn conn -> json(conn, %{updated: true}) end)
          delete("/remove", fn conn -> json(conn, %{deleted: true}) end)
          patch("/patch", fn conn -> json(conn, %{patched: true}) end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      post_resp = Req.post!("http://localhost:#{port}/create", body: "")
      assert post_resp.status == 201
      assert post_resp.body == %{"created" => true}

      put_resp = Req.put!("http://localhost:#{port}/update", body: "")
      assert put_resp.status == 200
      assert put_resp.body == %{"updated" => true}

      delete_resp = Req.delete!("http://localhost:#{port}/remove")
      assert delete_resp.status == 200
      assert delete_resp.body == %{"deleted" => true}

      patch_resp = Req.patch!("http://localhost:#{port}/patch", body: "")
      assert patch_resp.status == 200
      assert patch_resp.body == %{"patched" => true}
    end
  end

  describe "e2e: redirect" do
    @tag :capture_log
    test "redirect/2 returns 302 with location header over HTTP", %{port: port} do
      handler =
        quote do
          get("/old", fn conn -> redirect(conn, "/new") end)
          get("/new", fn _ -> "new page" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      # Disable redirect following to inspect the 302
      response = Req.get!("http://localhost:#{port}/old", redirect: false)

      assert response.status == 302
      assert Req.Response.get_header(response, "location") == ["/new"]
    end

    @tag :capture_log
    test "redirect is followed to destination", %{port: port} do
      handler =
        quote do
          get("/old", fn conn -> redirect(conn, "/new") end)
          get("/new", fn _ -> "arrived at new" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      # Let Req follow the redirect
      response = Req.get!("http://localhost:#{port}/old")

      assert response.status == 200
      assert response.body == "arrived at new"
    end
  end

  describe "e2e: HEAD requests" do
    @tag :capture_log
    test "HEAD returns headers but no body", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          get("/", fn conn -> html(conn, "<h1>Hello</h1>") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.head!("http://localhost:#{port}/")

      assert response.status == 200
      assert response.body == ""
      assert Req.Response.get_header(response, "content-type") == ["text/html; charset=utf-8"]
      assert Req.Response.get_header(response, "x-content-type-options") == ["nosniff"]
    end
  end
end
