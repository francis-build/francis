defmodule TextDrop.Views.Layout do
  @moduledoc "The HTML document around every page: head, header, nav and footer."

  use TextDrop.View

  @defaults %{title: "TextDrop", hero: false, scripts: []}

  template(:layout, "layout.html.eex")

  @doc """
  Wraps already-rendered HTML in the layout.

  Assigns: `:title`, `:hero` (show the logo and tagline) and `:scripts`
  (logical paths of ES modules to load).
  """
  @spec render(iodata(), map()) :: String.t()
  def render(inner_content, assigns \\ %{}) do
    @defaults
    |> Map.merge(assigns)
    |> Map.put(:inner_content, inner_content)
    |> layout()
  end
end
