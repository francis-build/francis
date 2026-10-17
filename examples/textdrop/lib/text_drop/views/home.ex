defmodule TextDrop.Views.Home do
  @moduledoc "The upload form and the about page."

  use TextDrop.View

  template(:index_body, "index.html.eex")
  template(:about_body, "about.html.eex", assigns: false)

  def index(assigns), do: Layout.render(index_body(assigns), %{hero: true})

  def about, do: Layout.render(about_body(), %{title: "About TextDrop", hero: true})
end
