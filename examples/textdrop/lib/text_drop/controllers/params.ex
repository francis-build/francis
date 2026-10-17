defmodule TextDrop.Controllers.Params do
  @moduledoc """
  Casts request parameters into the values the handlers expect.

  Every function returns `{:ok, value}` or `{:error, {:invalid, field}}`, which
  `TextDrop.Errors` turns into a 400 response naming the field.
  """

  alias TextDrop.Handlers.{Area, Pdf}

  @strategies Map.new(Pdf.strategies(), &{Atom.to_string(&1), &1})
  @max_areas 50
  @default_width 1400
  @width_range 100..3000

  @spec page(term()) :: {:ok, non_neg_integer()} | {:error, {:invalid, :page}}
  def page(nil), do: {:ok, 0}

  def page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page >= 0 -> {:ok, page}
      _ -> {:error, {:invalid, :page}}
    end
  end

  def page(_value), do: {:error, {:invalid, :page}}

  @spec boolean(term(), atom()) :: {:ok, boolean()} | {:error, {:invalid, atom()}}
  def boolean(nil, _field), do: {:ok, false}
  def boolean(value, _field) when value in ["true", "1", "on"], do: {:ok, true}
  def boolean(value, _field) when value in ["false", "0", "off"], do: {:ok, false}
  def boolean(_value, field), do: {:error, {:invalid, field}}

  @spec strategy(term(), atom()) :: {:ok, Pdf.strategy()} | {:error, {:invalid, atom()}}
  def strategy(nil, _field), do: {:ok, :lines}

  def strategy(value, field) do
    case Map.fetch(@strategies, value) do
      {:ok, strategy} -> {:ok, strategy}
      :error -> {:error, {:invalid, field}}
    end
  end

  @doc "Width of a rendered page in pixels. The default is what the workbench displays."
  @spec width(term()) :: {:ok, pos_integer()} | {:error, {:invalid, :width}}
  def width(nil), do: {:ok, @default_width}

  def width(value) when is_binary(value) do
    case Integer.parse(value) do
      {width, ""} when width in @width_range -> {:ok, width}
      _ -> {:error, {:invalid, :width}}
    end
  end

  def width(_value), do: {:error, {:invalid, :width}}

  @doc "A list of area maps, as the workbench sends them."
  @spec areas(term()) :: {:ok, [Area.t()]} | {:error, {:invalid, :areas}}
  def areas(areas) when is_list(areas) and length(areas) <= @max_areas do
    cast = Enum.map(areas, &Area.cast/1)

    if Enum.all?(cast, &match?({:ok, _}, &1)),
      do: {:ok, Enum.map(cast, fn {:ok, area} -> area end)},
      else: {:error, {:invalid, :areas}}
  end

  def areas(_areas), do: {:error, {:invalid, :areas}}
end
