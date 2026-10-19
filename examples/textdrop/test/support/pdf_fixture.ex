defmodule TextDrop.PdfFixture do
  @moduledoc """
  Builds a small one-page PDF for tests, with real text and an Info dictionary,
  so no external tool or binary fixture is needed.

  The text is placed at 72 pt from the left and 700 pt from the bottom of a
  US Letter page, which is about 68 to 92 pt from the top.
  """

  @text ~S|Hello <b>&"world"</b>|

  def text, do: @text

  @doc "Metadata values the fixture carries, as `TextDrop.Handlers.Pdf.metadata/1` formats them."
  def metadata,
    do: [{"Title", "Fixture"}, {"Author", "TextDrop"}, {"Created", "2025-06-21 11:00 +01:00"}]

  @doc "The PDF as a binary."
  def binary(text \\ @text) do
    stream = "BT /F1 24 Tf 72 700 Td (#{text}) Tj ET"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R " <>
        "/Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Title (Fixture) /Author (TextDrop) /CreationDate (D:20250621110000+01'00') >>"
    ]

    {body, offsets} =
      objects
      |> Enum.with_index(1)
      |> Enum.reduce({"%PDF-1.4\n", []}, fn {object, index}, {body, offsets} ->
        {body <> "#{index} 0 obj\n#{object}\nendobj\n", [byte_size(body) | offsets]}
      end)

    count = length(objects) + 1

    entries =
      offsets
      |> Enum.reverse()
      |> Enum.map_join(fn offset ->
        String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
      end)

    body <>
      "xref\n0 #{count}\n0000000000 65535 f \n" <>
      entries <>
      "trailer\n<< /Root 1 0 R /Info 6 0 R /Size #{count} >>\nstartxref\n#{byte_size(body)}\n%%EOF\n"
  end

  @doc "Writes the fixture into `dir` and returns its path."
  def write!(dir, name \\ "fixture.pdf") do
    path = Path.join(dir, name)
    File.write!(path, binary())
    path
  end

  @doc "The fixture as a `Plug.Upload`, written into `dir`."
  def upload(dir, name \\ "fixture.pdf") do
    %Plug.Upload{path: write!(dir, name), filename: name, content_type: "application/pdf"}
  end
end
