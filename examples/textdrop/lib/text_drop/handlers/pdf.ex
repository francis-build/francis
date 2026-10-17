defmodule TextDrop.Handlers.Pdf do
  @moduledoc """
  Reads PDFs through `PdfExtractor`.

  Every function takes the path of a stored document and returns `{:ok, result}`
  or `{:error, reason}`, where the reason is `:page_out_of_range` when the page
  does not exist, `:invalid_area` when an area has no size once clamped to the
  page, or `:unreadable` when the file cannot be parsed.

  Coordinates are PDF points with the origin at the top-left corner of the
  page, the convention pdfplumber uses. Areas are `TextDrop.Handlers.Area`
  structs, and the boxes of words and tables use the same field names.
  """

  alias TextDrop.Handlers.{Area, Metadata}

  @type page :: non_neg_integer()
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
  @strategies [:lines, :lines_strict, :text]

  @doc "How table edges can be found. See `tables/3`."
  @spec strategies() :: [strategy()]
  def strategies, do: @strategies

  @doc "Document metadata as `{label, value}` pairs in display order."
  @spec metadata(Path.t()) :: {:ok, [{String.t(), String.t()}]} | {:error, :unreadable}
  def metadata(path) do
    with {:ok, raw} <- call(&PdfExtractor.extract_metadata(path, &1)) do
      {:ok, Metadata.format(raw)}
    end
  end

  @doc "Size and rotation of every page, in page order."
  @spec pages(Path.t()) :: {:ok, [page_info()]} | {:error, :unreadable}
  def pages(path) do
    with {:ok, by_page} <- call(&PdfExtractor.extract_page_info(path, [], &1)) do
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
    extract(page, &PdfExtractor.extract_text(path, page, [layout: layout] ++ &1))
  end

  @doc """
  Text inside each area of a page, in the order the areas were given.

  Areas are clamped to the page first, because pdfplumber refuses boxes that
  reach outside it.
  """
  @spec text_in_areas(Path.t(), page(), [Area.t()]) :: {:ok, [String.t()]} | {:error, error()}
  def text_in_areas(_path, _page, []), do: {:ok, []}

  def text_in_areas(path, page, areas) do
    with {:ok, size} <- page_size(path, page),
         {:ok, boxes} <- boxes(areas, size) do
      extract(page, &PdfExtractor.extract_text(path, %{page => boxes}, &1))
    end
  end

  @doc "Every word of a page with its bounding box, font name and size."
  @spec words(Path.t(), page()) :: {:ok, [word()]} | {:error, error()}
  def words(path, page) do
    extract(page, &PdfExtractor.extract_words(path, page, [font: true] ++ &1))
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
    strategies =
      [vertical_strategy: :lines, horizontal_strategy: :lines]
      |> Keyword.merge(opts)
      |> Keyword.take([:vertical_strategy, :horizontal_strategy])

    extract(page, &PdfExtractor.extract_tables(path, page, strategies ++ &1))
  end

  @doc "PNG of a page, `width` pixels wide."
  @spec render(Path.t(), page(), pos_integer()) :: {:ok, binary()} | {:error, error()}
  def render(path, page, width) do
    extract(page, &PdfExtractor.render_pages(path, page, [width: width, antialias: true] ++ &1))
  end

  defp page_size(path, page) do
    with {:ok, by_page} <- call(&PdfExtractor.extract_page_info(path, page, &1)),
         {:ok, %{width: width, height: height}} <- fetch_page(by_page, page) do
      {:ok, {width, height}}
    end
  end

  defp boxes(areas, size) do
    clamped = Enum.map(areas, &Area.clamp(&1, size))

    if Enum.any?(clamped, &Area.empty?/1),
      do: {:error, :invalid_area},
      else: {:ok, Enum.map(clamped, &Area.to_tuple/1)}
  end

  # Runs one PdfExtractor call with the shared timeout. The extractor answers
  # {:ok, result} or {:error, exception}; any exception means the file could
  # not be read as asked.
  defp call(fun) do
    case fun.(timeout: @timeout) do
      {:ok, result} -> {:ok, result}
      {:error, _exception} -> {:error, :unreadable}
    end
  end

  # Page-scoped calls answer with a map keyed by page number.
  defp extract(page, fun) do
    with {:ok, by_page} <- call(fun), do: fetch_page(by_page, page)
  end

  defp fetch_page(by_page, page) do
    case Map.fetch(by_page, page) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :page_out_of_range}
    end
  end
end
