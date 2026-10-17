defmodule TextDrop.Handlers.Pdf do
  @moduledoc """
  Everything the app knows about reading a PDF, built on `PdfExtractor`.

  Every function takes the path of a stored document and returns `{:ok, result}`
  or `{:error, reason}`, where the reason is `:page_out_of_range` when the page
  does not exist, `:invalid_area` when an area has no size once clamped to the
  page, or `:unreadable` when the file cannot be parsed.

  Coordinates are PDF points with the origin at the top-left corner of the
  page, the convention pdfplumber uses. An area is `%{left, top, right, bottom}`, like the boxes of words and tables.
  """

  @type page :: non_neg_integer()
  @type area :: %{left: number(), top: number(), right: number(), bottom: number()}
  @type strategy :: :lines | :lines_strict | :text
  @type page_info :: %{
          number: page(),
          width: float(),
          height: float(),
          rotation: 0 | 90 | 180 | 270
        }
  @type word :: %{
          text: String.t(),
          left: float(),
          right: float(),
          top: float(),
          bottom: float(),
          font_name: String.t(),
          font_size: float()
        }
  @type table :: %{
          rows: [[String.t() | nil]],
          left: float(),
          top: float(),
          right: float(),
          bottom: float()
        }
  @type error :: :page_out_of_range | :invalid_area | :unreadable

  @timeout 30_000
  @metadata_order ~w(Title Author Subject Keywords Creator Producer CreationDate ModDate)

  @doc """
  Document metadata as `{label, value}` pairs in display order.

  Well-known keys come first, dates are reformatted from the PDF `D:` notation,
  and anything else is shown as the PDF stores it.
  """
  @spec metadata(Path.t()) :: {:ok, [{String.t(), String.t()}]} | {:error, :unreadable}
  def metadata(path) do
    with {:ok, raw} <- result(PdfExtractor.extract_metadata(path, timeout: @timeout)) do
      {:ok, format_metadata(raw)}
    end
  end

  @doc "Size and rotation of every page, in page order."
  @spec pages(Path.t()) :: {:ok, [page_info()]} | {:error, :unreadable}
  def pages(path) do
    with {:ok, by_page} <- result(PdfExtractor.extract_page_info(path, [], timeout: @timeout)) do
      pages =
        by_page
        |> Enum.sort()
        |> Enum.map(fn {number, info} -> Map.put(info, :number, number) end)

      {:ok, pages}
    end
  end

  @doc "Text of one page. `layout: true` pads the text so it keeps its position on the page."
  @spec text(Path.t(), page(), layout: boolean()) :: {:ok, String.t()} | {:error, error()}
  def text(path, page, opts \\ []) do
    layout = Keyword.get(opts, :layout, false)

    path
    |> PdfExtractor.extract_text(page, layout: layout, timeout: @timeout)
    |> page_result(page)
  end

  @doc """
  Text inside each area of a page, in the order the areas were given.

  Areas are clamped to the page first, because pdfplumber refuses boxes that
  reach outside it.
  """
  @spec text_in_areas(Path.t(), page(), [area()]) :: {:ok, [String.t()]} | {:error, error()}
  def text_in_areas(_path, _page, []), do: {:ok, []}

  def text_in_areas(path, page, areas) do
    with {:ok, size} <- page_size(path, page),
         {:ok, boxes} <- clamp_areas(areas, size) do
      path
      |> PdfExtractor.extract_text(%{page => boxes}, timeout: @timeout)
      |> page_result(page)
    end
  end

  @doc "Every word of a page with its bounding box, font name and size."
  @spec words(Path.t(), page()) :: {:ok, [word()]} | {:error, error()}
  def words(path, page) do
    path
    |> PdfExtractor.extract_words(page, font: true, timeout: @timeout)
    |> page_result(page)
  end

  @doc """
  Tables of a page: the rows of cells and the bounding box of each table.

  The strategies say how the edges are found: `:lines` uses the lines drawn on
  the page, `:lines_strict` ignores the sides of rectangles, and `:text` infers
  them from the alignment of the words.
  """
  @spec tables(Path.t(), page(), vertical_strategy: strategy(), horizontal_strategy: strategy()) ::
          {:ok, [table()]} | {:error, error()}
  def tables(path, page, opts \\ []) do
    strategies = [
      vertical_strategy: Keyword.get(opts, :vertical_strategy, :lines),
      horizontal_strategy: Keyword.get(opts, :horizontal_strategy, :lines)
    ]

    path
    |> PdfExtractor.extract_tables(page, strategies ++ [timeout: @timeout])
    |> page_result(page)
  end

  @doc "PNG of a page, `width` pixels wide (default 1200)."
  @spec render(Path.t(), page(), width: pos_integer()) :: {:ok, binary()} | {:error, error()}
  def render(path, page, opts \\ []) do
    width = Keyword.get(opts, :width, 1200)

    path
    |> PdfExtractor.render_pages(page, width: width, antialias: true, timeout: @timeout)
    |> page_result(page)
  end

  defp page_size(path, page) do
    with {:ok, by_page} <- result(PdfExtractor.extract_page_info(path, page, timeout: @timeout)) do
      case Map.fetch(by_page, page) do
        {:ok, %{width: width, height: height}} -> {:ok, {width, height}}
        :error -> {:error, :page_out_of_range}
      end
    end
  end

  defp clamp_areas(areas, {width, height}) do
    boxes =
      Enum.map(areas, fn area ->
        {clamp(area.left, width), clamp(area.top, height), clamp(area.right, width),
         clamp(area.bottom, height)}
      end)

    if Enum.all?(boxes, fn {x0, top, x1, bottom} -> x1 > x0 and bottom > top end) do
      {:ok, boxes}
    else
      {:error, :invalid_area}
    end
  end

  defp clamp(value, max), do: value |> max(0) |> min(max)

  # PdfExtractor answers with a map keyed by page number; a missing page means
  # the page does not exist.
  defp page_result({:ok, by_page}, page) do
    case Map.fetch(by_page, page) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :page_out_of_range}
    end
  end

  defp page_result({:error, _exception}, _page), do: {:error, :unreadable}

  defp result({:ok, value}), do: {:ok, value}
  defp result({:error, _exception}), do: {:error, :unreadable}

  defp format_metadata(raw) do
    known = for key <- @metadata_order, Map.has_key?(raw, key), do: {key, raw[key]}
    rest = raw |> Map.drop(@metadata_order) |> Enum.sort()

    Enum.map(known ++ rest, fn {key, value} -> {label(key), format_value(key, value)} end)
  end

  defp label("CreationDate"), do: "Created"
  defp label("ModDate"), do: "Modified"
  defp label(key), do: key

  defp format_value(key, value) when key in ["CreationDate", "ModDate"], do: format_date(value)
  defp format_value(_key, value) when is_binary(value), do: value
  defp format_value(_key, value), do: inspect(value)

  # PDF dates look like D:YYYYMMDDHHmmSSOHH'mm', where everything after the
  # year is optional and O is +, - or Z.
  defp format_date(value) when is_binary(value) do
    pattern = ~r/\AD:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?(Z|[+-]\d{2}(?:'\d{2})?)?/

    case Regex.run(pattern, value) do
      [_match | parts] ->
        [year, month, day, hour, minute, _second, zone] =
          parts |> Enum.map(&if(&1 == "", do: nil, else: &1)) |> pad(7)

        "#{year}-#{month || "01"}-#{day || "01"} #{hour || "00"}:#{minute || "00"}#{zone(zone)}"

      nil ->
        value
    end
  end

  defp format_date(value), do: inspect(value)

  defp pad(list, size), do: list ++ List.duplicate(nil, size - length(list))

  defp zone(nil), do: ""
  defp zone("Z"), do: " UTC"
  defp zone(offset), do: " " <> String.replace(offset, "'", ":")
end
