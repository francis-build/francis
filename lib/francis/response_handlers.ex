defmodule Francis.ResponseHandlers do
  @moduledoc """
  A module providing functions to handle HTTP responses in a Plug application.
  """

  import Plug.Conn

  @doc """
  Redirects the connection to the specified path with a 302 status code.
  You can specify a different status code by passing the `:status` option.
  ## Examples

  ```
  redirect(conn, "/new_path")
  redirect(conn, "/new_path", status: 301)
  ```
  """
  @spec redirect(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def redirect(conn, path, opts \\ []) do
    status = Keyword.get(opts, :status, 302)

    conn
    |> put_resp_header("location", path)
    |> send_resp(status, "")
    |> halt()
  end

  @doc """
  Sends a JSON response with the given status code and data.
  ## Examples
  ```
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
  ```
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
  ```
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
  ```
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
  Sends an HTML response with the given status code and HTML content.
  ## Examples
  ```
  html(conn, 200, "<h1>Hello World!</h1>")
  ```
  """
  @spec html(Plug.Conn.t(), integer(), String.t()) :: Plug.Conn.t()
  def html(conn, status, html) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
  end

  @doc """
  Sends an HTML response with a 200 status code and the given HTML content.
  ## Examples
  ```
  html(conn, "<h1>Hello World!</h1>")
  ```
  """
  def html(conn, html) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
