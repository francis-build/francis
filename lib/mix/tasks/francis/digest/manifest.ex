defmodule Mix.Tasks.Francis.Digest.Manifest do
  @moduledoc false

  def write(manifest_path, digested_files) do
    manifest = %{
      "version" => 1,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "files" => build_manifest_entries(digested_files)
    }

    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
  end

  defp build_manifest_entries(digested_files) do
    Enum.into(digested_files, %{}, fn file_info ->
      {file_info.logical_path, to_entry(file_info)}
    end)
  end

  defp to_entry(file_info) do
    file_info
    |> Map.take([:digest, :digested_path, :size, :mtime, :gzipped])
  end
end
