defmodule TextDrop.Controllers.Params do
  @moduledoc """
  Casts request parameters into the values the handlers expect.

  Every function returns `{:ok, value}` or `{:error, {:invalid, field}}`, which
  `TextDrop.ErrorHandler` turns into a 400 response naming the field.
  """

  @strategies %{"lines" => :lines, "lines_strict" => :lines_strict, "text" => :text}
  @max_areas 50
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

  @spec strategy(term(), atom()) :: {:ok, atom()} | {:error, {:invalid, atom()}}
  def strategy(nil, _field), do: {:ok, :lines}

  def strategy(value, field) do
    case Map.fetch(@strategies, value) do
      {:ok, strategy} -> {:ok, strategy}
      :error -> {:error, {:invalid, field}}
    end
  end

  @spec width(term()) :: {:ok, pos_integer()} | {:error, {:invalid, :width}}
  def width(nil), do: {:ok, 1200}

  def width(value) when is_binary(value) do
    case Integer.parse(value) do
      {width, ""} when width in @width_range -> {:ok, width}
      _ -> {:error, {:invalid, :width}}
    end
  end

  def width(_value), do: {:error, {:invalid, :width}}

  @doc "A list of `%{\"left\", \"top\", \"right\", \"bottom\"}` maps with numeric values, as sent by the workbench."
  @spec areas(term()) :: {:ok, [TextDrop.Handlers.Pdf.area()]} | {:error, {:invalid, :areas}}
  def areas(areas) when is_list(areas) and length(areas) <= @max_areas do
    areas
    |> Enum.reduce_while({:ok, []}, fn area, {:ok, acc} ->
      case area(area) do
        {:ok, area} -> {:cont, {:ok, [area | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, areas} -> {:ok, Enum.reverse(areas)}
      error -> error
    end
  end

  def areas(_areas), do: {:error, {:invalid, :areas}}

  defp area(%{"left" => left, "top" => top, "right" => right, "bottom" => bottom})
       when is_number(left) and is_number(top) and is_number(right) and is_number(bottom) do
    {:ok,
     %{
       left: min(left, right),
       top: min(top, bottom),
       right: max(left, right),
       bottom: max(top, bottom)
     }}
  end

  defp area(_area), do: {:error, {:invalid, :areas}}
end
