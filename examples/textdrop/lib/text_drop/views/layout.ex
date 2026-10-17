defmodule TextDrop.Views.Layout do
  @moduledoc "The HTML document around every page: head, header, nav and footer."

  require EEx

  import TextDrop.Views.Helpers

  @defaults %{title: "TextDrop", hero: false, scripts: []}

  EEx.function_from_file(:defp, :layout, "lib/text_drop/views/layout.html.eex", [:assigns])

  @doc """
  Wraps already-rendered HTML in the layout.

  Assigns: `:title`, `:hero` (show the logo and tagline) and `:scripts`
  (logical paths of scripts to load with `defer`).
  """
  @spec render(iodata(), map()) :: String.t()
  def render(inner_content, assigns \\ %{}) do
    @defaults
    |> Map.merge(assigns)
    |> Map.put(:inner_content, inner_content)
    |> layout()
  end
end
