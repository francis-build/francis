defmodule Francis.HTML do
  @moduledoc """
  Utilities for safe HTML handling.

  Provides HTML escaping to prevent Cross-Site Scripting (XSS) vulnerabilities
  when interpolating untrusted content into HTML responses.

  ## Examples

      iex> Francis.HTML.escape("<script>alert('xss')</script>")
      "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"

      iex> Francis.HTML.escape("Hello, World!")
      "Hello, World!"

      iex> Francis.HTML.escape(nil)
      ""
  """

  @doc """
  Escapes HTML special characters in a string to prevent XSS attacks.

  Escapes the following characters:
    * `&` → `&amp;`
    * `<` → `&lt;`
    * `>` → `&gt;`
    * `"` → `&quot;`
    * `'` → `&#39;`

  Returns an empty string for `nil` input.

  ## Examples

      iex> Francis.HTML.escape("<b>bold</b>")
      "&lt;b&gt;bold&lt;/b&gt;"

      iex> Francis.HTML.escape("safe text")
      "safe text"

      iex> Francis.HTML.escape(~s(a "quoted" value))
      "a &quot;quoted&quot; value"
  """
  @spec escape(nil | String.t()) :: String.t()
  def escape(nil), do: ""

  def escape(text) when is_binary(text) do
    IO.iodata_to_binary(escape_iodata(text, []))
  end

  # Efficient single-pass escaping using iodata accumulation
  defp escape_iodata(<<>>, acc), do: Enum.reverse(acc)
  defp escape_iodata(<<"&", rest::binary>>, acc), do: escape_iodata(rest, ["&amp;" | acc])
  defp escape_iodata(<<"<", rest::binary>>, acc), do: escape_iodata(rest, ["&lt;" | acc])
  defp escape_iodata(<<">", rest::binary>>, acc), do: escape_iodata(rest, ["&gt;" | acc])
  defp escape_iodata(<<"\"", rest::binary>>, acc), do: escape_iodata(rest, ["&quot;" | acc])
  defp escape_iodata(<<"'", rest::binary>>, acc), do: escape_iodata(rest, ["&#39;" | acc])

  defp escape_iodata(<<char, rest::binary>>, acc),
    do: escape_iodata(rest, [<<char>> | acc])
end
