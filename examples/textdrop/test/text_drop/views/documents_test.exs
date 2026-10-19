defmodule TextDrop.Views.DocumentsTest do
  use ExUnit.Case, async: true

  alias TextDrop.Views.Documents

  @page %{number: 0, width: 612.0, height: 792.0, rotation: 0}

  test "render_partial/2 renders a _name.html.eex file from the view's directory" do
    assert Documents.render_partial("words", %{}) =~ ~s(id="words-button")
    assert Documents.render_partial(:tables, %{}) =~ ~s(<select id="vertical-strategy">)
    assert Documents.render_partial("pages", %{pages: [@page]}) =~ "<td>612 pt</td>"
  end

  test "render_partial/2 raises for a partial that does not exist" do
    assert_raise ArgumentError,
                 ~r/no partial _missing\.html\.eex in lib\/text_drop\/views\/documents/,
                 fn ->
                   Documents.render_partial("missing", %{})
                 end
  end
end
