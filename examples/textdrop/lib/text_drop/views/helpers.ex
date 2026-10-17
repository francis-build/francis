defmodule TextDrop.Views.Helpers do
  @moduledoc "Functions available inside every template."

  @doc "Escapes a value for HTML. EEx does not do this on its own."
  defdelegate escape(value), to: Francis.HTML

  @doc "Path of a static asset, digested when a manifest exists."
  def static_path(logical_path), do: Francis.Static.static_path(logical_path, "/assets")

  @doc "Formats a measurement in PDF points with at most two decimals."
  def points(value) when is_integer(value), do: Integer.to_string(value)

  def points(value) when is_float(value) do
    value
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(~r/\.?0+\z/, "")
  end
end
