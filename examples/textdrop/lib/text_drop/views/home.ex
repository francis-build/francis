defmodule TextDrop.Views.Home do
  @moduledoc "The upload form and the about page."

  require EEx

  alias TextDrop.Views.Layout

  EEx.function_from_file(:defp, :index_body, "lib/text_drop/views/home/index.html.eex", [
    :_assigns
  ])

  EEx.function_from_file(:defp, :about_body, "lib/text_drop/views/home/about.html.eex", [
    :_assigns
  ])

  def index(assigns), do: Layout.render(index_body(assigns), %{hero: true})

  def about(assigns),
    do: Layout.render(about_body(assigns), %{title: "About TextDrop", hero: true})
end
