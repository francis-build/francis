defmodule Francis.ErrorPage do
  @moduledoc """
  Generates simple HTML error pages for common HTTP error responses.

  Used internally by Francis to render error pages for 404 and 500 responses.
  Can also be used directly to generate custom error pages.

  ## Examples

      Francis.ErrorPage.render(404)
      #=> "<!DOCTYPE html>..."

      Francis.ErrorPage.render(500)
      #=> "<!DOCTYPE html>..."

      Francis.ErrorPage.render(503, "Service Unavailable", "We'll be back shortly.")
      #=> "<!DOCTYPE html>..."
  """

  @status_messages %{
    400 => {"Bad Request", "The request could not be understood by the server."},
    404 => {"Not Found", "The page you are looking for does not exist."},
    500 => {"Internal Server Error", "Something went wrong on our end."},
    502 => {"Bad Gateway", "The server received an invalid response."},
    503 => {"Service Unavailable", "The server is temporarily unavailable."}
  }

  @doc """
  Renders an HTML error page for the given status code.

  Uses default title and message for known status codes (400, 404, 500, 502, 503).
  For unknown codes, uses "Error" as the title and a generic message.

  ## Examples

      iex> Francis.ErrorPage.render(404) |> String.contains?("Not Found")
      true
  """
  @spec render(integer()) :: String.t()
  def render(status) do
    {title, message} =
      Map.get(@status_messages, status, {"Error", "An unexpected error occurred."})

    render(status, title, message)
  end

  @doc """
  Renders an HTML error page with a custom title and message.

  ## Examples

      iex> Francis.ErrorPage.render(503, "Maintenance", "Back soon!")
      iex> |> String.contains?("Maintenance")
      true
  """
  @spec render(integer(), String.t(), String.t()) :: String.t()
  def render(status, title, message) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{status} — #{Francis.HTML.escape(title)}</title>
    <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
    display:flex;align-items:center;justify-content:center;
    min-height:100vh;background:#f8f9fa;color:#212529}
    .container{text-align:center;padding:2rem}
    .status{font-size:6rem;font-weight:700;color:#dee2e6;line-height:1}
    h1{font-size:1.5rem;margin:1rem 0 .5rem}
    p{color:#6c757d;font-size:1rem}
    </style>
    </head>
    <body>
    <div class="container">
    <div class="status">#{status}</div>
    <h1>#{Francis.HTML.escape(title)}</h1>
    <p>#{Francis.HTML.escape(message)}</p>
    </div>
    </body>
    </html>
    """
  end
end
