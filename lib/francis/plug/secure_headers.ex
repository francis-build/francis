defmodule Francis.Plug.SecureHeaders do
  @moduledoc """
  A plug that sets common security-related HTTP headers.

  This plug adds a set of sensible default security headers to every response,
  helping protect against common web vulnerabilities like clickjacking, MIME-type
  sniffing, and information leakage.

  ## Default Headers

    * `x-content-type-options: nosniff` — Prevents browsers from MIME-sniffing the content type
    * `x-frame-options: DENY` — Prevents the page from being rendered in a frame/iframe
    * `x-xss-protection: 1; mode=block` — Enables the browser's XSS filter
    * `referrer-policy: strict-origin-when-cross-origin` — Controls how much referrer info is sent
    * `permissions-policy: camera=(), microphone=(), geolocation=()` — Restricts browser features
    * `strict-transport-security: max-age=63072000; includeSubDomains` — Enforces HTTPS connections

  ## Usage

      plug Francis.Plug.SecureHeaders

  ## Custom Headers

  You can override or extend the default headers by passing a `:headers` option:

      plug Francis.Plug.SecureHeaders,
        headers: %{
          "x-frame-options" => "SAMEORIGIN",
          "x-custom-header" => "custom-value"
        }

  Custom headers are merged with the defaults, so you only need to specify the
  headers you want to change.
  """

  @behaviour Plug

  @default_headers %{
    "x-content-type-options" => "nosniff",
    "x-frame-options" => "DENY",
    "x-xss-protection" => "1; mode=block",
    "referrer-policy" => "strict-origin-when-cross-origin",
    "permissions-policy" => "camera=(), microphone=(), geolocation=()",
    "strict-transport-security" => "max-age=63072000; includeSubDomains"
  }

  @impl true
  def init(opts) do
    custom_headers = Keyword.get(opts, :headers, %{})
    Map.merge(@default_headers, custom_headers)
  end

  @impl true
  def call(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      Plug.Conn.put_resp_header(conn, key, value)
    end)
  end
end
