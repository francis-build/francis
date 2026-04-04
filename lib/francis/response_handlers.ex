defmodule Francis.ResponseHandlers do
  @moduledoc """
  A module providing functions to handle HTTP responses in a Plug application.
  """

  import Plug.Conn

  @html_cache_control "no-cache, no-store, must-revalidate"

  @doc """
  Redirects the connection to the specified path with a 302 status code.

  Only relative paths are accepted. Absolute URLs (e.g. `http://...`) will raise
  an `ArgumentError` to prevent open redirect vulnerabilities. Protocol-relative
  URLs (e.g. `//evil.com`) are neutralized to `"/"`.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/old", fn conn -> redirect(conn, "/new") end)
  end
  ```
  """
  @spec redirect(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def redirect(conn, path) do
    validated_path = validate_redirect_path(path)

    conn
    |> put_resp_header("location", validated_path)
    |> send_resp(302, "")
    |> halt()
  end

  @doc """
  Redirects the connection to the specified path with a custom status code.

  Only relative paths are accepted. See `redirect/2` for details on URL validation.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/old", fn conn -> redirect(conn, 301, "/new") end)
  end
  ```
  """
  @spec redirect(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def redirect(conn, status, path) do
    validated_path = validate_redirect_path(path)

    conn
    |> put_resp_header("location", validated_path)
    |> send_resp(status, "")
    |> halt()
  end

  defp validate_redirect_path("/" <> _ = path) do
    case URI.parse(path) do
      # Reject protocol-relative URLs like "//evil.com"
      %URI{host: nil} -> path
      _ -> "/"
    end
  end

  defp validate_redirect_path(path) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: nil, host: nil} -> path
      _ -> raise ArgumentError, "redirect/2 only accepts relative paths, got: #{inspect(path)}"
    end
  end

  @doc """
  Sends a JSON response with the given status code and data.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    post("/users", fn conn ->
      json(conn, 201, %{id: 123, message: "User created"})
    end)
  end
  ```
  """
  @spec json(Plug.Conn.t(), integer(), map() | list()) :: Plug.Conn.t()
  def json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  @doc """
  Sends a JSON response with a 200 status code and the given data.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/api/data", fn conn ->
      json(conn, %{message: "Success", data: [1, 2, 3]})
    end)
  end
  ```
  """
  @spec json(Plug.Conn.t(), map() | list()) :: Plug.Conn.t()
  def json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  @doc """
  Sends a text response with the given status code and text.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/text", fn conn ->
      text(conn, 200, "Hello World!")
    end)
  end
  ```
  """
  @spec text(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def text(conn, status, text) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, text)
  end

  @doc """
  Sends a text response with a 200 status code and the given text.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/hello", fn conn ->
      text(conn, "Hello World!")
    end)
  end
  ```
  """
  @spec text(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def text(conn, text) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, text)
  end

  @doc """
  Sends an HTML response with a 200 status code and HTML content.

  **Warning:** The following function does **not** escape HTML content.
  Passing user-generated or untrusted input may result in [Cross-Site Scripting (XSS)](https://owasp.org/www-community/attacks/xss/) vulnerabilities.
  Only use this function with trusted, static HTML content. Use `Francis.HTML.escape/1` for escaping untrusted content,
  or use `safe_html/2` which escapes content automatically.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/", fn conn ->
      html(conn, "<h1>Hello World!</h1>")
    end)
  end
  ```
  """
  # sobelow_skip ["XSS.SendResp"]
  @spec html(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def html(conn, html) do
    conn
    |> put_html_headers()
    |> send_resp(200, html)
  end

  @doc """
  Sends an HTML response with the given status code and HTML content.

  **Warning:** The following function does **not** escape HTML content.
  Passing user-generated or untrusted input may result in [Cross-Site Scripting (XSS)](https://owasp.org/www-community/attacks/xss/) vulnerabilities.
  Only use this function with trusted, static HTML content.
  Use `Francis.HTML.escape/1` for escaping untrusted content,
  or use `safe_html/2` which escapes content automatically.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/", fn conn ->
      html(conn, 201, "<h1>Created</h1>")
    end)
  end
  ```
  """
  # sobelow_skip ["XSS.SendResp"]
  @spec html(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def html(conn, status, html) do
    conn
    |> put_html_headers()
    |> send_resp(status, html)
  end

  @doc """
  Sends an HTML response with a 200 status code, escaping the content to prevent XSS.

  Unlike `html/2`, this function escapes all HTML special characters in the content,
  making it safe for rendering untrusted or user-generated input.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/", fn conn ->
      user_input = conn.params["name"]
      safe_html(conn, "<h1>Hello, \#{user_input}!</h1>")
    end)
  end
  ```
  """
  @spec safe_html(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def safe_html(conn, content) do
    conn
    |> put_html_headers()
    |> send_resp(200, Francis.HTML.escape(content))
  end

  @doc """
  Sends an HTML response with the given status code, escaping the content to prevent XSS.

  Unlike `html/3`, this function escapes all HTML special characters in the content,
  making it safe for rendering untrusted or user-generated input.

  ## Examples

  ```elixir
  defmodule Example do
    use Francis

    get("/", fn conn ->
      user_input = conn.params["name"]
      safe_html(conn, 201, "<h1>Created: \#{user_input}</h1>")
    end)
  end
  ```
  """
  @spec safe_html(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def safe_html(conn, status, content) do
    conn
    |> put_html_headers()
    |> send_resp(status, Francis.HTML.escape(content))
  end

  defp put_html_headers(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", @html_cache_control)
  end
end
