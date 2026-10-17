defmodule TextDrop.Views.Documents do
  @moduledoc "The document page with its metadata, pages and workbench."

  require EEx

  import TextDrop.Views.Helpers

  alias TextDrop.Views.Layout

  EEx.function_from_file(:defp, :show_body, "lib/text_drop/views/documents/show.html.eex", [
    :assigns
  ])

  def show(assigns) do
    Layout.render(show_body(assigns), %{
      title: "Document · TextDrop",
      scripts: ["js/workbench.js"]
    })
  end
end
