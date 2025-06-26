defmodule Francis.ResponseHandlers do
  @moduledoc """
  A module providing functions to handle HTTP responses in a Plug application.
  """

  import Plug.Conn

  @doc """
  Redirects the connection to the specified path with a 302 status code.
  ## Examples
  ```
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
  ```
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
end
