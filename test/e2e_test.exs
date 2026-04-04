defmodule FrancisE2ETest do
  use ExUnit.Case

  @moduletag :e2e

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
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]

      assert response.headers["cache-control"] == [
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
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]

      assert response.headers["cache-control"] == [
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
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
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
      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert response.headers["x-frame-options"] == ["DENY"]
      assert response.headers["x-xss-protection"] == ["1; mode=block"]

      assert response.headers["referrer-policy"] == [
               "strict-origin-when-cross-origin"
             ]

      assert response.headers["permissions-policy"] == [
               "camera=(), microphone=(), geolocation=()"
             ]

      assert response.headers["strict-transport-security"] == [
               "max-age=63072000; includeSubDomains"
             ]
    end

    @tag :capture_log
    test "allows overriding specific security headers", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders,
            headers: %{"x-frame-options" => "SAMEORIGIN", "x-custom" => "my-value"}
          )

          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.headers["x-frame-options"] == ["SAMEORIGIN"]
      assert response.headers["x-custom"] == ["my-value"]
      # defaults still present
      assert response.headers["x-content-type-options"] == ["nosniff"]
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
      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert response.headers["x-frame-options"] == ["DENY"]
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

      [csp] = response.headers["content-security-policy"]
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

          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      [csp] = response.headers["content-security-policy"]
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
          get("/", fn _ -> "ok" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.headers["content-security-policy-report-only"] != nil
      assert response.headers["content-security-policy"] == nil
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
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
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
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
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
      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert response.headers["x-frame-options"] == ["DENY"]
      assert response.headers["x-xss-protection"] == ["1; mode=block"]

      assert response.headers["referrer-policy"] == [
               "strict-origin-when-cross-origin"
             ]

      # CSP header
      [csp] = response.headers["content-security-policy"]
      assert csp =~ "default-src 'self'"

      # HTML-specific headers
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]

      assert response.headers["cache-control"] == [
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
      assert response.headers["x-content-type-options"] == ["nosniff"]
      [csp] = response.headers["content-security-policy"]
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
      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert response.headers["x-frame-options"] == ["DENY"]
      [csp] = response.headers["content-security-policy"]
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
      assert html_resp.headers["content-type"] == ["text/html; charset=utf-8"]

      assert html_resp.headers["cache-control"] == [
               "no-cache, no-store, must-revalidate"
             ]

      assert html_resp.headers["x-content-type-options"] == ["nosniff"]

      # JSON route
      json_resp = Req.get!("http://localhost:#{port}/json")
      assert json_resp.status == 200
      assert json_resp.body == %{"message" => "hello"}

      assert json_resp.headers["content-type"] == [
               "application/json; charset=utf-8"
             ]

      assert json_resp.headers["x-content-type-options"] == ["nosniff"]

      # Text route
      text_resp = Req.get!("http://localhost:#{port}/text")
      assert text_resp.status == 200
      assert text_resp.body == "plain text"
      assert text_resp.headers["content-type"] == ["text/plain; charset=utf-8"]

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
      assert response.headers["location"] == ["/new"]
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

    @tag :capture_log
    test "rejects absolute URL redirects over HTTP", %{port: port} do
      handler =
        quote do
          get("/redir", fn conn -> redirect(conn, "http://evil.com/phish") end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/redir", redirect: false, retry: false)

      # Should get a 500 because the ArgumentError is raised
      assert response.status == 500
    end

    @tag :capture_log
    test "protocol-relative redirect is neutralized", %{port: port} do
      handler =
        quote do
          get("/redir", fn conn -> redirect(conn, "//evil.com/phish") end)
          get("/", fn _ -> "safe home" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/redir", redirect: false)

      assert response.status == 302
      # Protocol-relative URL is neutralized to "/"
      assert response.headers["location"] == ["/"]
    end
  end

  describe "e2e: complex HTML pages" do
    @tag :capture_log
    test "html/2 serves a full HTML document with nested elements", %{port: port} do
      page = """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Test Page</title>
        <style>
          body { font-family: sans-serif; margin: 0; }
          .container { max-width: 800px; margin: 0 auto; padding: 2rem; }
          nav a { color: #007bff; text-decoration: none; }
          nav a:hover { text-decoration: underline; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #dee2e6; padding: .5rem; text-align: left; }
          footer { margin-top: 2rem; color: #6c757d; font-size: .875rem; }
        </style>
      </head>
      <body>
        <div class="container">
          <nav>
            <a href="/">Home</a> | <a href="/about">About</a> | <a href="/contact">Contact</a>
          </nav>
          <h1>Dashboard</h1>
          <p>Welcome back, <strong>User</strong>!</p>
          <form action="/search" method="get">
            <input type="text" name="q" placeholder="Search&hellip;" required>
            <button type="submit">Go</button>
          </form>
          <table>
            <thead><tr><th>ID</th><th>Name</th><th>Status</th></tr></thead>
            <tbody>
              <tr><td>1</td><td>Item A</td><td>Active</td></tr>
              <tr><td>2</td><td>Item B</td><td>Pending</td></tr>
              <tr><td>3</td><td>Item C &amp; D</td><td>Done</td></tr>
            </tbody>
          </table>
          <footer>&copy; 2026 Test App. All rights reserved.</footer>
        </div>
        <script>
          document.addEventListener('DOMContentLoaded', function() {
            console.log('page loaded');
            var rows = document.querySelectorAll('tr');
            rows.forEach(function(r) { r.addEventListener('click', function() {}); });
          });
        </script>
      </body>
      </html>
      """

      handler =
        quote do
          get("/", fn conn -> html(conn, unquote(page)) end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]

      # Verify the full document structure survived the round-trip
      assert response.body =~ "<!DOCTYPE html>"
      assert response.body =~ "<html lang=\"en\">"
      assert response.body =~ "<meta charset=\"utf-8\">"
      assert response.body =~ "<style>"
      assert response.body =~ "border-collapse: collapse"
      assert response.body =~ "<nav>"
      assert response.body =~ "<form action=\"/search\" method=\"get\">"
      assert response.body =~ "placeholder=\"Search&hellip;\""
      assert response.body =~ "<table>"
      assert response.body =~ "<th>ID</th><th>Name</th><th>Status</th>"
      assert response.body =~ "Item C &amp; D"
      assert response.body =~ "<script>"
      assert response.body =~ "document.addEventListener('DOMContentLoaded'"
      assert response.body =~ "&copy; 2026 Test App"
      assert response.body =~ "</html>"
    end

    @tag :capture_log
    test "safe_html escapes user content without mangling surrounding HTML", %{port: port} do
      handler =
        quote do
          get("/", fn conn ->
            # Simulate building a page with user-controlled input
            user_name = "<script>alert('xss')</script>"
            user_bio = "I like coding & \"testing\" things"
            user_url = "https://example.com/?a=1&b=2"

            escaped_name = Francis.HTML.escape(user_name)
            escaped_bio = Francis.HTML.escape(user_bio)
            escaped_url = Francis.HTML.escape(user_url)

            page = """
            <!DOCTYPE html>
            <html>
            <head><title>Profile</title></head>
            <body>
              <h1>#{escaped_name}</h1>
              <p class="bio">#{escaped_bio}</p>
              <a href="#{escaped_url}">Website</a>
              <img src="/avatar.png" alt="#{escaped_name}">
              <form action="/update" method="post">
                <input type="hidden" name="name" value="#{escaped_name}">
                <textarea>#{escaped_bio}</textarea>
                <button type="submit">Save</button>
              </form>
            </body>
            </html>
            """

            html(conn, page)
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")

      assert response.status == 200

      # Script tag in user input is escaped
      refute response.body =~ "<script>alert"
      assert response.body =~ "&lt;script&gt;alert"

      # Quotes and ampersands in user content are escaped
      assert response.body =~ "I like coding &amp; &quot;testing&quot; things"
      assert response.body =~ "https://example.com/?a=1&amp;b=2"

      # But the structural HTML is NOT escaped — it renders properly
      assert response.body =~ "<!DOCTYPE html>"
      assert response.body =~ "<html>"
      assert response.body =~ "<h1>"
      assert response.body =~ "<p class=\"bio\">"
      assert response.body =~ "<a href=\""
      assert response.body =~ "<img src=\"/avatar.png\""
      assert response.body =~ "<form action=\"/update\" method=\"post\">"
      assert response.body =~ "<textarea>"
      assert response.body =~ "<button type=\"submit\">Save</button>"
      assert response.body =~ "</html>"
    end

    @tag :capture_log
    test "error page renders full HTML document", %{port: port} do
      handler =
        quote do
          get("/", fn _ -> "home" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/missing", retry: false)

      assert response.status == 404
      # Verify the error page is a complete, well-formed HTML document
      assert response.body =~ "<!DOCTYPE html>"
      assert response.body =~ "<html lang=\"en\">"
      assert response.body =~ "<meta charset=\"utf-8\">"
      assert response.body =~ "<meta name=\"viewport\""
      assert response.body =~ "<title>404"
      assert response.body =~ "<style>"
      assert response.body =~ "Not Found"
      assert response.body =~ "</html>"
    end
  end

  describe "e2e: WebSocket" do
    @tag :capture_log
    test "echo server over real WebSocket connection", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, "echo: #{message}"}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "hello"})
      assert_receive {:client, "echo: hello"}, 2000

      WebSockex.send_frame(tester_pid, {:text, "world"})
      assert_receive {:client, "echo: world"}, 2000
    end

    @tag :capture_log
    test "join event fires on WebSocket connect", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn
            :join, socket ->
              {:reply, %{event: "welcome", id: socket.id}}

            {:received, message}, _socket ->
              {:reply, message}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      _tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      assert_receive {:client, %{"event" => "welcome", "id" => id}}, 2000
      assert is_binary(id)
    end

    @tag :capture_log
    test "WebSocket sends JSON replies for maps", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, _socket ->
            {:reply, %{received: message, status: "ok"}}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "ping"})

      assert_receive {:client, %{"received" => "ping", "status" => "ok"}}, 2000
    end

    @tag :capture_log
    test "WebSocket transport forwarding works", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn {:received, message}, socket ->
            send(socket.transport, "broadcast: #{message}")
            {:reply, "ack"}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      WebSockex.send_frame(tester_pid, {:text, "hi"})

      assert_receive {:client, "ack"}, 2000
      assert_receive {:client, "broadcast: hi"}, 2000
    end

    @tag :capture_log
    test "WebSocket close event fires cleanly", %{port: port} do
      parent_pid = self()
      path = 10 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

      handler =
        quote do
          ws(unquote(path), fn
            {:close, _reason}, _socket ->
              send(unquote(parent_pid), {:lifecycle, :closed})
              :ok

            {:received, message}, _socket ->
              {:reply, message}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester, %{url: "ws://localhost:#{port}/#{path}", parent_pid: parent_pid}}
        )

      # Verify connection works
      WebSockex.send_frame(tester_pid, {:text, "alive"})
      assert_receive {:client, "alive"}, 2000

      # Close cleanly
      WebSockex.send_frame(tester_pid, :close)
      assert_receive {:lifecycle, :closed}, 2000
    end

    @tag :capture_log
    test "WebSocket full lifecycle with path params", %{port: port} do
      parent_pid = self()

      handler =
        quote do
          ws("/chat/:room", fn
            :join, socket ->
              room = socket.params["room"]
              {:reply, %{event: "joined", room: room}}

            {:close, _reason}, _socket ->
              send(unquote(parent_pid), {:lifecycle, :left})
              :ok

            {:received, message}, socket ->
              room = socket.params["room"]
              {:reply, %{room: room, message: message}}
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      {:ok, _} = start_supervised(mod)

      tester_pid =
        start_supervised!(
          {Support.WsTester,
           %{url: "ws://localhost:#{port}/chat/general", parent_pid: parent_pid}}
        )

      # Join event with room param
      assert_receive {:client, %{"event" => "joined", "room" => "general"}}, 2000

      # Message echoed with room context
      WebSockex.send_frame(tester_pid, {:text, "hello everyone"})

      assert_receive {:client, %{"room" => "general", "message" => "hello everyone"}},
                     2000

      # Clean close
      WebSockex.send_frame(tester_pid, :close)
      assert_receive {:lifecycle, :left}, 2000
    end
  end

  describe "e2e: DOM validation with Floki" do
    @tag :capture_log
    test "error page 404 has valid DOM structure", %{port: port} do
      handler =
        quote do
          get("/", fn _ -> "home" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/missing", retry: false)
      {:ok, doc} = Floki.parse_document(response.body)

      # Verify document structure
      assert [{"html", _, _}] = Floki.find(doc, "html")
      assert [{"head", _, _}] = Floki.find(doc, "head")
      assert [{"body", _, _}] = Floki.find(doc, "body")

      # Title contains status code
      assert [{"title", _, _}] = Floki.find(doc, "title")
      assert Floki.find(doc, "title") |> Floki.text() =~ "404"

      # Meta tags present
      assert [_ | _] = Floki.find(doc, "meta[charset]")
      assert [_ | _] = Floki.find(doc, "meta[name='viewport']")

      # Error content in correct elements
      assert [{"h1", _, _}] = Floki.find(doc, "h1")
      assert Floki.find(doc, "h1") |> Floki.text() =~ "Not Found"

      assert [{"p", _, _}] = Floki.find(doc, "p")

      # CSS is present
      assert [_ | _] = Floki.find(doc, "style")

      # Container structure
      assert [{"div", _, _}] = Floki.find(doc, ".container")
      assert [{"div", _, _}] = Floki.find(doc, ".status")
      assert Floki.find(doc, ".status") |> Floki.text() =~ "404"
    end

    @tag :capture_log
    test "error page 500 has valid DOM structure", %{port: port} do
      handler =
        quote do
          get("/", fn _ -> raise "boom" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/", retry: false)
      {:ok, doc} = Floki.parse_document(response.body)

      assert Floki.find(doc, "title") |> Floki.text() =~ "500"
      assert Floki.find(doc, "h1") |> Floki.text() =~ "Internal Server Error"
      assert Floki.find(doc, ".status") |> Floki.text() =~ "500"
    end

    @tag :capture_log
    test "complex HTML page preserves full DOM tree", %{port: port} do
      page = """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>DOM Test</title>
      </head>
      <body>
        <nav>
          <a href="/">Home</a>
          <a href="/about">About</a>
          <a href="/contact">Contact</a>
        </nav>
        <main>
          <h1>Dashboard</h1>
          <p>Welcome, <strong>User</strong>!</p>
          <table>
            <thead><tr><th>ID</th><th>Name</th></tr></thead>
            <tbody>
              <tr><td>1</td><td>Alpha</td></tr>
              <tr><td>2</td><td>Beta</td></tr>
            </tbody>
          </table>
          <form action="/search" method="get">
            <input type="text" name="q" placeholder="Search">
            <button type="submit">Go</button>
          </form>
        </main>
        <footer>© 2026 Test</footer>
      </body>
      </html>
      """

      handler =
        quote do
          get("/", fn conn -> html(conn, unquote(page)) end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")
      {:ok, doc} = Floki.parse_document(response.body)

      # Document structure
      assert [{"html", [{"lang", "en"}], _}] = Floki.find(doc, "html")
      assert [{"head", _, _}] = Floki.find(doc, "head")
      assert [{"body", _, _}] = Floki.find(doc, "body")
      assert [{"title", _, _}] = Floki.find(doc, "title")
      assert Floki.find(doc, "title") |> Floki.text() == "DOM Test"

      # Navigation links
      nav_links = Floki.find(doc, "nav a")
      assert length(nav_links) == 3
      assert Floki.attribute(nav_links, "href") == ["/", "/about", "/contact"]

      # Main content
      assert Floki.find(doc, "h1") |> Floki.text() == "Dashboard"
      assert Floki.find(doc, "p strong") |> Floki.text() == "User"

      # Table structure
      headers = Floki.find(doc, "thead th")
      assert length(headers) == 2
      assert Enum.map(headers, &Floki.text/1) == ["ID", "Name"]

      rows = Floki.find(doc, "tbody tr")
      assert length(rows) == 2

      cells = Floki.find(doc, "tbody td")
      assert Enum.map(cells, &Floki.text/1) == ["1", "Alpha", "2", "Beta"]

      # Form
      assert [{"form", attrs, _}] = Floki.find(doc, "form")
      assert {"action", "/search"} in attrs
      assert {"method", "get"} in attrs
      assert [{"input", _, _}] = Floki.find(doc, "input[name='q']")
      assert [{"button", _, _}] = Floki.find(doc, "button[type='submit']")

      # Footer
      assert Floki.find(doc, "footer") |> Floki.text() =~ "2026 Test"
    end

    @tag :capture_log
    test "escaped user input doesn't create DOM elements", %{port: port} do
      handler =
        quote do
          get("/", fn conn ->
            user_input = "<script>alert('xss')</script>"
            escaped = Francis.HTML.escape(user_input)

            page = """
            <html>
            <body>
              <div id="content">#{escaped}</div>
            </body>
            </html>
            """

            html(conn, page)
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")
      {:ok, doc} = Floki.parse_document(response.body)

      # The escaped content should NOT create a script element in the DOM
      assert Floki.find(doc, "script") == []

      # The content div should exist and contain the escaped text
      assert [{"div", [{"id", "content"}], _}] = Floki.find(doc, "#content")
      text = Floki.find(doc, "#content") |> Floki.text()
      assert text =~ "alert('xss')"
    end

    @tag :capture_log
    test "multiple escaped attributes don't break DOM structure", %{port: port} do
      handler =
        quote do
          get("/", fn conn ->
            name = Francis.HTML.escape("O'Reilly & \"Sons\"")
            bio = Francis.HTML.escape("<b>bold</b> & <i>italic</i>")

            page = """
            <html>
            <body>
              <div id="profile">
                <h2 class="name">#{name}</h2>
                <p class="bio">#{bio}</p>
                <input type="text" value="#{name}">
              </div>
            </body>
            </html>
            """

            html(conn, page)
          end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/")
      {:ok, doc} = Floki.parse_document(response.body)

      # DOM structure is intact
      assert [{"div", [{"id", "profile"}], _}] = Floki.find(doc, "#profile")
      assert [{"h2", [{"class", "name"}], _}] = Floki.find(doc, "h2.name")
      assert [{"p", [{"class", "bio"}], _}] = Floki.find(doc, "p.bio")

      # Escaped content didn't create extra DOM nodes
      assert Floki.find(doc, "b") == []
      assert Floki.find(doc, "i") == []

      # Text content is readable (Floki decodes entities)
      assert Floki.find(doc, "h2.name") |> Floki.text() =~ "O'Reilly"
      assert Floki.find(doc, "p.bio") |> Floki.text() =~ "bold"
    end

    @tag :capture_log
    test "security headers + CSP with Floki-validated error page", %{port: port} do
      handler =
        quote do
          plug(Francis.Plug.SecureHeaders)
          plug(Francis.Plug.CSP)
          get("/", fn _ -> "home" end)
        end

      mod = Support.RouteTester.generate_module(handler, bandit_opts: [port: port])
      start_supervised!(mod)

      response = Req.get!("http://localhost:#{port}/nope", retry: false)

      assert response.status == 404

      # Validate headers
      assert response.headers["x-content-type-options"] == ["nosniff"]
      [csp] = response.headers["content-security-policy"]
      assert csp =~ "default-src 'self'"

      # Validate DOM of error page
      {:ok, doc} = Floki.parse_document(response.body)
      assert [{"html", [{"lang", "en"}], _}] = Floki.find(doc, "html")
      assert Floki.find(doc, "h1") |> Floki.text() =~ "Not Found"
      assert [_ | _] = Floki.find(doc, "style")
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
      assert response.headers["content-type"] == ["text/html; charset=utf-8"]
      assert response.headers["x-content-type-options"] == ["nosniff"]
    end
  end
end
