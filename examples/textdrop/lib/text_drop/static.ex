defmodule TextDrop.Static do
  @moduledoc """
  Cache headers for the files `Plug.Static` serves under `/assets`.

  Wired in through the `headers:` option in `config/config.exs`. Digested files
  (`simple-<hash>.css`) get the immutable `cache-control` value recorded in the
  manifest written by `mix francis.digest`; plain files keep Plug.Static's
  default.
  """

  @spec headers(Plug.Conn.t()) :: %{optional(String.t()) => String.t()}
  def headers(%Plug.Conn{request_path: "/assets/" <> path}) do
    with cache_control when is_binary(cache_control) <- Francis.Static.cache_control(),
         true <- digested?(path) do
      %{"cache-control" => cache_control}
    else
      _ -> %{}
    end
  end

  def headers(_conn), do: %{}

  defp digested?(path) do
    Enum.any?(Francis.Static.all(), fn {_logical, entry} -> entry["digested_path"] == path end)
  end
end
