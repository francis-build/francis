defmodule Mix.Tasks.Francis.Digest.Manifest do
  @moduledoc false

  def write(manifest_path, digested_files, opts \\ []) do
    manifest = %{
      "version" => 1,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "cache_control" => opts[:cache_control],
      "files" => build_manifest_entries(digested_files)
    }

    write_atomically(manifest_path, Jason.encode!(manifest, pretty: true))
  end

  # Readers (Francis.Static) never observe a half-written manifest, and the rename gives the
  # file a new inode so caches keyed on it are invalidated even within the same second.
  # The temp file is a dotfile so a crashed run never leaves something `**/*` would digest.
  defp write_atomically(manifest_path, content) do
    tmp_path =
      Path.join(
        Path.dirname(manifest_path),
        ".#{Path.basename(manifest_path)}.#{System.unique_integer([:positive])}.tmp"
      )

    File.write!(tmp_path, content)

    case File.rename(tmp_path, manifest_path) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm(tmp_path)

        raise File.RenameError,
          source: tmp_path,
          destination: manifest_path,
          reason: reason,
          action: "rename"
    end
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
