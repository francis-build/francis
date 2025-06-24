defmodule Francis.ResponseHandlers do
  @moduledoc """
  A module providing functions to handle HTTP responses in a Plug application.
  """

  import Plug.Conn

  @doc """
  Redirects the connection to the specified path with a 302 status code.

  ## Examples

  ```elixir
  redirect(conn, "/new_path")
  ```
  """
  @spec redirect(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def redirect(conn, path) do
    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
    |> halt()
  end

  @doc """
  Redirects the connection to the specified path with a custom status code.

  ## Examples

  ```elixir
  redirect(conn, 301, "/new_path")
  ```
  """
  @spec redirect(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def redirect(conn, status, path) do
    conn
    |> put_resp_header("location", path)
    |> send_resp(status, "")
    |> halt()
  end

  @doc """
  Sends a JSON response with the given status code and data.

  ## Examples

  ```elixir
  json(conn, 201, %{message: "Success"})
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
  json(conn, %{message: "Success"})
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
  text(conn, 200, "Hello World!")
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
  text(conn, "Hello World!")
  ```
  """
  @spec text(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def text(conn, text) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, text)
  end

  @doc """
  Sends an HTML response with the given status code and HTML content. It will escape the HTML content to prevent XSS attacks.

  ## Examples

  ```elixir
  html(conn, 200, "<h1>Hello World!</h1>")
  ```
  """
  @spec html(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def html(conn, html) do
    html = Phoenix.HTML.html_escape(html)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Phoenix.HTML.safe_to_string(html))
  end

  @doc """
  Sends an HTML response with the given status code and HTML content. It will escape the HTML content to prevent XSS attacks.

  ## Examples

  ```elixir
  html(conn, 200, "<h1>Hello World!</h1>")
  ```
  """
  @spec html(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def html(conn, status, html) do
    html = Phoenix.HTML.html_escape(html)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, Phoenix.HTML.safe_to_string(html))
  end
end
