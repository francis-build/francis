defmodule TextDrop.Views.Documents do
  @moduledoc """
  The document page: a toolbar, the page viewer, and one tab per panel below.

  Tabs and panels are generated from `@tabs`; each panel has a partial named
  after it under `documents/`.
  """

  require EEx

  import TextDrop.Views.Helpers

  alias TextDrop.Handlers.Pdf
  alias TextDrop.Views.Layout

  @tabs [
    metadata: "Metadata",
    pages: "Pages",
    text: "Text",
    areas: "Areas",
    words: "Words",
    tables: "Tables"
  ]
  @strategy_labels %{lines: "lines", lines_strict: "lines (strict)", text: "text"}
  @templates "lib/text_drop/views/documents"

  EEx.function_from_file(:defp, :show_body, "#{@templates}/show.html.eex", [:assigns])

  # Panels whose markup comes from the document. The others are static shells
  # that the script fills in.
  @dynamic_panels [:metadata, :pages]

  for {tab, _label} <- @tabs do
    template = "#{@templates}/_#{tab}.html.eex"

    if tab in @dynamic_panels do
      EEx.function_from_file(:defp, :"#{tab}_panel", template, [:assigns])
      defp panel(unquote(tab), assigns), do: unquote(:"#{tab}_panel")(assigns)
    else
      EEx.function_from_file(:defp, :"#{tab}_panel", template, [])
      defp panel(unquote(tab), _assigns), do: unquote(:"#{tab}_panel")()
    end
  end

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
