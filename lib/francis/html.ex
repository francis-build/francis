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
    IO.iodata_to_binary(escape_iodata(text, 0, text, []))
  end

  # Escapes in a single pass using chunked iodata accumulation.
  #
  # Instead of building one list element per byte, we track how many consecutive
  # safe bytes we've seen (`skip`). When we hit a special character, we emit the
  # safe run as a single `binary_part(original, 0, skip)` slice, followed by the
  # replacement entity. Then `rest` becomes the new `original` and `skip` resets.
  #
  # This produces far fewer list elements than byte-by-byte for typical HTML
  # where most characters are safe (e.g. "hello<world" = 2 chunks, not 11).
  defp escape_iodata(<<>>, 0, _original, acc), do: Enum.reverse(acc)

  defp escape_iodata(<<>>, skip, original, acc),
    do: Enum.reverse([binary_part(original, 0, skip) | acc])

  for {char, replacement} <- [
        {?&, "&amp;"},
        {?<, "&lt;"},
        {?>, "&gt;"},
        {?", "&quot;"},
        {?', "&#39;"}
      ] do
    defp escape_iodata(<<unquote(char), rest::binary>>, 0, _original, acc) do
      escape_iodata(rest, 0, rest, [unquote(replacement) | acc])
    end

    defp escape_iodata(<<unquote(char), rest::binary>>, skip, original, acc) do
      chunk = binary_part(original, 0, skip)
      escape_iodata(rest, 0, rest, [unquote(replacement), chunk | acc])
    end
  end

  defp escape_iodata(<<_char, rest::binary>>, skip, original, acc) do
    escape_iodata(rest, skip + 1, original, acc)
  end
end
