defmodule TextDrop.Handlers.Metadata do
  @moduledoc """
  Turns the raw metadata dictionary of a PDF into `{label, value}` pairs for
  display: well-known keys first, dates reformatted, everything else as stored.
  """

  @order ~w(Title Author Subject Keywords Creator Producer CreationDate ModDate)
  @labels %{"CreationDate" => "Created", "ModDate" => "Modified"}
  @dates ~w(CreationDate ModDate)

  @spec format(%{String.t() => term()}) :: [{String.t(), String.t()}]
  def format(raw) when is_map(raw) do
    known = for key <- @order, Map.has_key?(raw, key), do: {key, raw[key]}
    rest = raw |> Map.drop(@order) |> Enum.sort()

    Enum.map(known ++ rest, fn {key, value} ->
      {Map.get(@labels, key, key), format_value(key, value)}
    end)
  end

  defp format_value(key, value) when key in @dates, do: format_date(value)
  defp format_value(_key, value) when is_binary(value), do: value
  defp format_value(_key, value), do: inspect(value)

  @doc """
  Reformats a PDF date as `YYYY-MM-DD HH:MM` followed by its zone.

  PDF dates look like `D:YYYYMMDDHHmmSSOHH'mm'`, where everything after the
  year is optional and `O` is `+`, `-` or `Z`. Anything else is returned as is.
  """
  @spec format_date(term()) :: String.t()
  def format_date(value) when is_binary(value) do
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

  def format_date(value), do: inspect(value)

  defp pad(list, size), do: list ++ List.duplicate(nil, size - length(list))

  defp zone(nil), do: ""
  defp zone("Z"), do: " UTC"
  defp zone(offset), do: " " <> String.replace(offset, "'", ":")
end
