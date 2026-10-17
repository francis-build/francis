defmodule TextDrop.Handlers.MetadataTest do
  use ExUnit.Case, async: true

  alias TextDrop.Handlers.Metadata

  test "format/1 orders known keys first, relabels dates and keeps the rest sorted" do
    raw = %{
      "Zebra" => "last",
      "ModDate" => "D:20260102",
      "Producer" => "PDFium",
      "Title" => "Fixture",
      "Alpha" => 42
    }

    assert Metadata.format(raw) == [
             {"Title", "Fixture"},
             {"Producer", "PDFium"},
             {"Modified", "2026-01-02 00:00"},
             {"Alpha", "42"},
             {"Zebra", "last"}
           ]
  end

  test "format/1 of an empty dictionary is empty" do
    assert Metadata.format(%{}) == []
  end

  test "format_date/1 handles every level of precision a PDF date allows" do
    assert Metadata.format_date("D:20250621110000+01'00'") == "2025-06-21 11:00 +01:00"
    assert Metadata.format_date("D:20250621110000Z") == "2025-06-21 11:00 UTC"
    assert Metadata.format_date("D:202506211100") == "2025-06-21 11:00"
    assert Metadata.format_date("D:2025") == "2025-01-01 00:00"
    assert Metadata.format_date("yesterday") == "yesterday"
    assert Metadata.format_date(nil) == "nil"
  end
end
