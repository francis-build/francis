defmodule TextDrop.Handlers.Documents do
  @moduledoc """
  Stores uploaded PDFs and finds them again by id.

  Ids are 32 lowercase hex characters generated here, and only ids of that
  shape are ever turned into a path, so a crafted id cannot escape the upload
  directory (`config :text_drop, :upload_dir`). An upload that `PdfExtractor`
  cannot open is removed again instead of being kept.
  """

  alias TextDrop.Handlers.Pdf

  @type id :: String.t()

  @doc "Copies an upload into the upload directory and checks that it is a readable PDF."
  @spec store(Plug.Upload.t()) :: {:ok, id()} | {:error, :unreadable}
  def store(%Plug.Upload{path: source}) do
    id = generate_id()
    destination = path_for(id)

    File.mkdir_p!(Path.dirname(destination))
    File.cp!(source, destination)

    case Pdf.pages(destination) do
      {:ok, _pages} ->
        {:ok, id}

      {:error, reason} ->
        File.rm(destination)
        {:error, reason}
    end
  end

  @doc "Returns the path of a stored document."
  @spec fetch(term()) :: {:ok, Path.t()} | {:error, :not_found}
  def fetch(id) when is_binary(id) do
    with true <- Regex.match?(~r/\A[0-9a-f]{32}\z/, id),
         path = path_for(id),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> {:error, :not_found}
    end
  end

  def fetch(_id), do: {:error, :not_found}

  @doc "Deletes a stored document. Unknown ids are ignored."
  @spec delete(term()) :: :ok
  def delete(id) do
    with {:ok, path} <- fetch(id), do: File.rm(path)
    :ok
  end

  defp generate_id do
    16 |> :crypto.strong_rand_bytes() |> :binary.encode_hex() |> String.downcase()
  end

  defp path_for(id), do: Path.join(upload_dir(), id <> ".pdf")

  defp upload_dir, do: Application.fetch_env!(:text_drop, :upload_dir)
end
