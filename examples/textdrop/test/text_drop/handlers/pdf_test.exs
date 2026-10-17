defmodule TextDrop.Handlers.PdfTest do
  @moduledoc "Runs the real extractor on the fixture PDF, so it needs the Python runtime."

  use ExUnit.Case, async: true

  @moduletag :integration

  alias TextDrop.Handlers.Pdf
  alias TextDrop.PdfFixture

  @text_area %{left: 60, top: 50, right: 400, bottom: 110}
  @empty_area %{left: 0, top: 400, right: 612, bottom: 792}

  setup_all do
    dir = Path.join(System.tmp_dir!(), "textdrop-pdf-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    unreadable = Path.join(dir, "unreadable.pdf")
    File.write!(unreadable, "not a pdf")

    %{path: PdfFixture.write!(dir), unreadable: unreadable}
  end

  test "metadata/1 lists the known keys first and reformats dates", %{path: path} do
    assert Pdf.metadata(path) == {:ok, PdfFixture.metadata()}
  end

  test "pages/1 returns size and rotation in page order", %{path: path} do
    assert Pdf.pages(path) == {:ok, [%{number: 0, width: 612.0, height: 792.0, rotation: 0}]}
  end

  test "text/3 returns the text of a page, with or without layout", %{path: path} do
    assert {:ok, text} = Pdf.text(path, 0)
    assert text =~ PdfFixture.text()

    assert {:ok, laid_out} = Pdf.text(path, 0, layout: true)
    assert laid_out =~ "Hello"
    assert String.length(laid_out) > String.length(text)
  end

  test "text/3 reports a page that does not exist", %{path: path} do
    assert Pdf.text(path, 5) == {:error, :page_out_of_range}
  end

  test "text_in_areas/3 extracts each area in order", %{path: path} do
    assert {:ok, [with_text, without]} = Pdf.text_in_areas(path, 0, [@text_area, @empty_area])
    assert with_text =~ "Hello"
    assert without == ""
  end

  test "text_in_areas/3 clamps areas to the page and rejects empty ones", %{path: path} do
    oversized = %{left: -50, top: -50, right: 10_000, bottom: 10_000}
    assert {:ok, [text]} = Pdf.text_in_areas(path, 0, [oversized])
    assert text =~ "Hello"

    off_page = %{left: 700, top: 0, right: 900, bottom: 100}
    assert Pdf.text_in_areas(path, 0, [off_page]) == {:error, :invalid_area}
    assert Pdf.text_in_areas(path, 0, []) == {:ok, []}
  end

  test "words/2 returns every word with its box and font", %{path: path} do
    assert {:ok, words} = Pdf.words(path, 0)
    assert hello = Enum.find(words, &(&1.text == "Hello"))
    assert hello.font_name == "Helvetica"
    assert_in_delta hello.font_size, 24, 0.01
    assert hello.left < hello.right and hello.top < hello.bottom
    assert_in_delta hello.left, 72, 0.5
  end

  test "tables/3 finds no tables on a page without lines", %{path: path} do
    assert Pdf.tables(path, 0) == {:ok, []}
    assert Pdf.tables(path, 0, vertical_strategy: :text, horizontal_strategy: :text) == {:ok, []}
  end

  test "render/3 returns a PNG of the requested width", %{path: path} do
    assert {:ok, png} = Pdf.render(path, 0, width: 300)

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
