defmodule TextDrop.Handlers.PdfTest do
  @moduledoc "Runs the real extractor on the fixture PDF."

  use TextDrop.IntegrationCase, async: true

  alias TextDrop.Handlers.{Area, Pdf}

  @text_area Area.new(60, 50, 400, 110)
  @empty_area Area.new(0, 400, 612, 792)

  setup_all %{dir: dir} do
    unreadable = Path.join(dir, "unreadable.pdf")
    File.write!(unreadable, "not a pdf")
    %{unreadable: unreadable}
  end

  test "metadata/1 lists the known keys first and reformats dates", %{fixture: path} do
    assert Pdf.metadata(path) == {:ok, PdfFixture.metadata()}
  end

  test "pages/1 returns size and rotation in page order", %{fixture: path} do
    assert Pdf.pages(path) == {:ok, [%{number: 0, width: 612.0, height: 792.0, rotation: 0}]}
  end

  test "text/3 returns the text of a page, with or without layout", %{fixture: path} do
    assert {:ok, text} = Pdf.text(path, 0)
    assert text =~ PdfFixture.text()

    assert {:ok, laid_out} = Pdf.text(path, 0, layout: true)
    assert laid_out =~ "Hello"
    assert String.length(laid_out) > String.length(text)
  end

  test "text/3 reports a page that does not exist", %{fixture: path} do
    assert Pdf.text(path, 5) == {:error, :page_out_of_range}
  end

  test "text_in_areas/3 extracts each area in order", %{fixture: path} do
    assert {:ok, [with_text, without]} = Pdf.text_in_areas(path, 0, [@text_area, @empty_area])
    assert with_text =~ "Hello"
    assert without == ""
  end

  test "text_in_areas/3 clamps areas to the page and rejects empty ones", %{fixture: path} do
    assert {:ok, [text]} = Pdf.text_in_areas(path, 0, [Area.new(-50, -50, 10_000, 10_000)])
    assert text =~ "Hello"

    assert Pdf.text_in_areas(path, 0, [Area.new(700, 0, 900, 100)]) == {:error, :invalid_area}
    assert Pdf.text_in_areas(path, 0, []) == {:ok, []}
  end

  test "words/2 returns every word with its box and font", %{fixture: path} do
    assert {:ok, words} = Pdf.words(path, 0)
    assert hello = Enum.find(words, &(&1.text == "Hello"))
    assert hello.font_name == "Helvetica"
    assert_in_delta hello.font_size, 24, 0.01
    assert hello.left < hello.right and hello.top < hello.bottom
    assert_in_delta hello.left, 72, 0.5
  end

  test "tables/3 finds no tables on a page without lines", %{fixture: path} do
    assert Pdf.tables(path, 0) == {:ok, []}
    assert Pdf.tables(path, 0, vertical_strategy: :text, horizontal_strategy: :text) == {:ok, []}
  end

  test "render/3 returns a PNG of the requested width", %{fixture: path} do
    assert {:ok, png} = Pdf.render(path, 0, 300)

    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary-size(8), 300::32, height::32, _::binary>> =
             png

    assert height > 300
  end

  test "an unreadable file is reported as such", %{unreadable: path} do
    assert Pdf.metadata(path) == {:error, :unreadable}
    assert Pdf.pages(path) == {:error, :unreadable}
    assert Pdf.text(path, 0) == {:error, :unreadable}
  end
end
