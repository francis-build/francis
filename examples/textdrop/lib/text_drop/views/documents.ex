defmodule TextDrop.Views.Documents do
  @moduledoc """
  The document page: a toolbar, the page viewer, and one tab per panel below.

  Tabs are generated from `@tabs`; each panel is the partial of the same name.
  """

  use TextDrop.View

  alias TextDrop.Handlers.Pdf

  @tabs [
    metadata: "Metadata",
    pages: "Pages",
    text: "Text",
    areas: "Areas",
    words: "Words",
    tables: "Tables"
  ]
  @strategy_labels %{lines: "lines", lines_strict: "lines (strict)", text: "text"}

  template(:show_body, "show.html.eex")

  def show(assigns) do
    assigns
    |> Map.put(:tabs, @tabs)
    |> show_body()
    |> Layout.render(%{title: "Document · TextDrop", scripts: ["js/workbench/main.js"]})
  end

  # The badge on a tab before the script runs; only the page count is known here.
  defp initial_count(:pages, assigns), do: length(assigns.pages)
  defp initial_count(_tab, _assigns), do: ""

  # A labelled <select> of the table strategies `TextDrop.Handlers.Pdf` accepts.
  defp strategy_select(id, label) do
    options =
      Enum.map_join(Pdf.strategies(), fn strategy ->
        ~s(<option value="#{strategy}">#{escape(Map.fetch!(@strategy_labels, strategy))}</option>)
      end)

    ~s(<label for="#{id}">#{escape(label)}</label> <select id="#{id}">#{options}</select>)
  end
end
