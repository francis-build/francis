defmodule TextDrop.Handlers.AreaTest do
  use ExUnit.Case, async: true

  alias TextDrop.Handlers.Area

  test "new/4 accepts the corners in any order" do
    assert Area.new(10, 20, 30, 40) == %Area{left: 10, top: 20, right: 30, bottom: 40}
    assert Area.new(30, 40, 10, 20) == %Area{left: 10, top: 20, right: 30, bottom: 40}
  end

  test "cast/1 reads string or atom keys and rejects anything else" do
    assert Area.cast(%{"left" => 1, "top" => 2.5, "right" => 3, "bottom" => 4}) ==
             {:ok, %Area{left: 1, top: 2.5, right: 3, bottom: 4}}

    assert Area.cast(%{left: 1, top: 2, right: 3, bottom: 4}) == {:ok, Area.new(1, 2, 3, 4)}
    assert Area.cast(%{"left" => "1", "top" => 2, "right" => 3, "bottom" => 4}) == :error
    assert Area.cast(%{"left" => 1}) == :error
    assert Area.cast("nope") == :error
  end

  test "clamp/2 keeps the area inside the page" do
    assert Area.clamp(Area.new(-50, -50, 10_000, 10_000), {612, 792}) == Area.new(0, 0, 612, 792)
    assert Area.clamp(Area.new(700, 10, 900, 20), {612, 792}) == Area.new(612, 10, 612, 20)
  end

  test "empty?/1 is true without width or height" do
    refute Area.empty?(Area.new(0, 0, 1, 1))
    assert Area.empty?(Area.new(5, 0, 5, 10))
    assert Area.empty?(Area.new(0, 5, 10, 5))
  end

  test "to_tuple/1 gives PdfExtractor its {x0, top, x1, bottom}" do
    assert Area.to_tuple(Area.new(1, 2, 3, 4)) == {1, 2, 3, 4}
  end
end
