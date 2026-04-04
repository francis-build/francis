defmodule Francis.Plug.CSP do
  @moduledoc """
  A plug that sets the Content-Security-Policy (CSP) header.

  CSP helps prevent Cross-Site Scripting (XSS), clickjacking, and other code injection
  attacks by specifying which content sources the browser should trust.

  ## Default Policy

  The default policy is restrictive and only allows resources from the same origin:

      default-src 'self'; script-src 'self';
      style-src 'self'; img-src 'self' data:;
      font-src 'self'; object-src 'none'; frame-ancestors 'none'

  ## Usage

      # Use default policy
      plug Francis.Plug.CSP

      # Use custom policy directives
      plug Francis.Plug.CSP,
        directives: %{
          "default-src" => "'self'",
          "script-src" => "'self' https://cdn.example.com",
          "style-src" => "'self' 'unsafe-inline'",
          "img-src" => "'self' data: https://images.example.com"
        }

  ## Options

    * `:directives` — a map of CSP directive names to their values. Merged with defaults.
    * `:report_only` — when `true`, uses `Content-Security-Policy-Report-Only` header
      instead of `Content-Security-Policy`, allowing you to test policies without enforcing them.
      Defaults to `false`.
  """

  @behaviour Plug

  @default_directives %{
    "default-src" => "'self'",
    "script-src" => "'self'",
    "style-src" => "'self'",
    "img-src" => "'self' data:",
    "font-src" => "'self'",
    "object-src" => "'none'",
    "frame-ancestors" => "'none'"
  }

  @impl true
  def init(opts) do
    custom_directives = Keyword.get(opts, :directives, %{})
    report_only = Keyword.get(opts, :report_only, false)

    directives = Map.merge(@default_directives, custom_directives)

    policy =
      directives
      |> Enum.sort()
      |> Enum.map_join("; ", fn {key, value} -> "#{key} #{value}" end)

    %{policy: policy, report_only: report_only}
  end

  @impl true
  def call(conn, %{policy: policy, report_only: report_only}) do
    header_name =
      if report_only,
        do: "content-security-policy-report-only",
        else: "content-security-policy"

    Plug.Conn.put_resp_header(conn, header_name, policy)
  end
end
