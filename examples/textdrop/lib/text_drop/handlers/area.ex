defmodule TextDrop.Handlers.Area do
  @moduledoc """
  A rectangle on a page, in PDF points with the origin at the top-left corner.

  The areas a user draws, and the boxes of words and tables, all share this
  shape, so the geometry lives here: building an area from any two corners,
  keeping it inside a page, and handing it to `PdfExtractor` as a tuple.
  """

  @enforce_keys [:left, :top, :right, :bottom]
  defstruct [:left, :top, :right, :bottom]

  @type t :: %__MODULE__{left: number(), top: number(), right: number(), bottom: number()}
  @type size :: {width :: number(), height :: number()}

  @doc "Builds an area from two opposite corners, in any order."
  @spec new(number(), number(), number(), number()) :: t()
  def new(x1, y1, x2, y2)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) do
    %__MODULE__{left: min(x1, x2), top: min(y1, y2), right: max(x1, x2), bottom: max(y1, y2)}
  end

  @doc "Builds an area from a map with string or atom keys, as JSON delivers it."
  @spec cast(term()) :: {:ok, t()} | :error
  def cast(%{"left" => left, "top" => top, "right" => right, "bottom" => bottom}) do
    cast(%{left: left, top: top, right: right, bottom: bottom})
  end

  def cast(%{left: left, top: top, right: right, bottom: bottom})
      when is_number(left) and is_number(top) and is_number(right) and is_number(bottom) do
    {:ok, new(left, top, right, bottom)}
  end

  def cast(_other), do: :error

  @doc "Keeps the area inside a page of the given size."
  @spec clamp(t(), size()) :: t()
  def clamp(%__MODULE__{} = area, {width, height}) do
    %__MODULE__{
      left: area.left |> max(0) |> min(width),
      top: area.top |> max(0) |> min(height),
      right: area.right |> max(0) |> min(width),
      bottom: area.bottom |> max(0) |> min(height)
    }
  end

  @doc "An area without width or without height."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = area), do: area.right <= area.left or area.bottom <= area.top

  @doc "The `{x0, top, x1, bottom}` tuple `PdfExtractor` takes."
  @spec to_tuple(t()) :: {number(), number(), number(), number()}
  def to_tuple(%__MODULE__{} = area), do: {area.left, area.top, area.right, area.bottom}
end
