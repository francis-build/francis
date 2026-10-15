defmodule Mix.Tasks.Francis.Digest do
  use Mix.Task

  @shortdoc "Digests and compresses static files"

  @moduledoc """
  Digests and compresses static files for production deployment.

  This task generates versions of static files with content-based hashes in their
  filenames and creates a manifest file mapping original names to their hashed versions.

      $ mix francis.digest
      $ mix francis.digest priv/static
      $ mix francis.digest priv/static --output priv/static

  ## Command line options

    * `--output` - the output path for generated files.
      Defaults to the input path.

    * `--age` - sets the cache control max age in seconds for static assets.
      Stored in the manifest as `"cache_control" => "public, max-age=<age>, immutable"`
      and exposed through `Francis.Static.cache_control/1`. Defaults to 31536000 (1 year).

    * `--gzip` - when set to false, does not generate gzipped files.
      Defaults to true.

    * `--exclude` - list of file patterns to exclude from digest.
      Example: `--exclude '*.txt' --exclude '*.json'`

    * `--clean` - removes previously digested files and the manifest before
      regenerating. Uses the existing manifest to identify files to delete, so
      only known digested files are removed. Useful for single-instance deploys
      where stale hashed files are never needed. Avoid in rolling/blue-green
      deployments where old instances may still serve previous asset hashes.

  The output will be a set of digested files along with a cache manifest file.
  The manifest file maps original file names to their digested counterparts.

  Running the task again is safe: the manifest at the output root, the files it
  lists (digested and gzipped) and, when the output directory lives inside the
  input directory, everything under the output directory are never digested
  again. Digested files dropped from the manifest by a later run are treated as
  sources; use `--clean` to remove them.

  ## Examples

      $ mix francis.digest
      Generated digested assets in priv/static:
        * app.css -> app-a1b2c3d4e5f6.css
        * app.js -> app-9f8e7d6c5b4a.js
        * manifest.json

      $ mix francis.digest assets --output priv/static
      Generated digested assets from assets to priv/static

      $ mix francis.digest priv/static --clean
      Cleaned 4 previously digested files
      Generated digested assets in priv/static
  """

  alias Mix.Tasks.Francis.Digest.Manifest

  @default_input_path "priv/static"
  # 1 year in seconds — standard cache-control max-age for fingerprinted assets
  @default_age 31_536_000
  @digest_algorithm :sha256
  # 12 hex chars = 48 bits of entropy, collision-safe for up to ~16M files
  @digest_length 12

  def run(args) do
    {opts, args} = parse_args(args)

    input_path = List.first(args) || @default_input_path
    output_path = opts[:output] || input_path

    if !File.exists?(input_path) do
      Mix.shell().error("Input path #{input_path} does not exist")
      exit({:shutdown, 1})
    end

    File.mkdir_p!(output_path)

    manifest_path = Path.join(output_path, "cache_manifest.json")
    # Read before cleaning so previous outputs are still recognised when input == output
    skipped = generated_paths(input_path, output_path, manifest_path)

    if opts[:clean], do: clean_old_digests(output_path)

    Mix.shell().info("Generating digested files from #{input_path} to #{output_path}")

    exclude_regexes = compile_exclude_patterns(opts[:exclude] || [])
    files = collect_files(input_path, exclude_regexes, skipped)
    digested_files = Enum.map(files, &digest_file(&1, input_path, output_path, opts))

    Manifest.write(manifest_path, digested_files, cache_control: cache_control(opts[:age]))

    Mix.shell().info("Generated #{length(digested_files)} digested files")
    Mix.shell().info("Manifest written to #{manifest_path}")

    :ok
  end

  defp parse_args(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          age: :integer,
          gzip: :boolean,
          exclude: :keep,
          clean: :boolean
        ],
        aliases: [
          o: :output
        ]
      )

    opts =
      opts
      |> Keyword.put_new(:age, @default_age)
      |> Keyword.put_new(:gzip, true)
      |> Keyword.put_new(:clean, false)
      |> process_exclude_patterns()

    {opts, args}
  end

  defp clean_old_digests(output_path) do
    manifest_path = Path.join(output_path, "cache_manifest.json")

    with {:ok, content} <- File.read(manifest_path),
         {:ok, %{"files" => files}} <- Jason.decode(content) do
      count = Enum.count(files, fn {_, info} -> remove_digested(output_path, info) end)

      File.rm(manifest_path)
      Mix.shell().info("Cleaned #{count} previously digested files")
    end
  end

  # Returns whether the digested file itself was removed; the gzip variant is best-effort.
  defp remove_digested(output_path, info) do
    with {:ok, gzip_path} <- safe_output_path(output_path, get_in(info, ["gzipped", "path"])) do
      File.rm(gzip_path)
    end

    case safe_output_path(output_path, info["digested_path"]) do
      {:ok, digested_path} -> File.rm(digested_path) == :ok
      :error -> false
    end
  end

  # Manifest entries come from disk, so only paths that stay inside output_path are touched
  defp safe_output_path(_output_path, nil), do: :error

  defp safe_output_path(output_path, relative_path) when is_binary(relative_path) do
    case Path.safe_relative(relative_path, output_path) do
      {:ok, safe_path} ->
        {:ok, Path.join(output_path, safe_path)}

      :error ->
        Mix.shell().error("Skipping unsafe manifest path #{inspect(relative_path)}")
        :error
    end
  end

  defp safe_output_path(_output_path, relative_path) do
    Mix.shell().error("Skipping invalid manifest path #{inspect(relative_path)}")
    :error
  end

  defp process_exclude_patterns(opts) do
    exclude_patterns =
      opts
      |> Keyword.get_values(:exclude)

    Keyword.put(opts, :exclude, exclude_patterns)
  end

  defp compile_exclude_patterns(patterns) do
    Enum.flat_map(patterns, fn pattern ->
      regex_pattern =
        pattern
        |> String.replace(".", "\\.")
        |> String.replace("*", ".*")
        |> String.replace("?", ".")
        |> then(&("^" <> &1 <> "$"))

      case Regex.compile(regex_pattern) do
        {:ok, regex} -> [regex]
        _ -> []
      end
    end)
  end

  defp cache_control(age), do: "public, max-age=#{age}, immutable"

  # Outputs of previous runs that must never be digested again: the manifest itself, every
  # file it lists and, when output_path is nested inside input_path, the whole output tree.
  defp generated_paths(input_path, output_path, manifest_path) do
    expanded_input = Path.expand(input_path)
    expanded_output = Path.expand(output_path)

    nested_output =
      if expanded_output != expanded_input and
           String.starts_with?(expanded_output, expanded_input <> "/") do
        expanded_output
      end

    files =
      [Path.expand(manifest_path) | previous_manifest_paths(expanded_output, manifest_path)]
      |> MapSet.new()

    %{files: files, nested_output: nested_output}
  end

  defp previous_manifest_paths(expanded_output, manifest_path) do
    with {:ok, content} <- File.read(manifest_path),
         {:ok, %{"files" => files}} when is_map(files) <- Jason.decode(content) do
      files
      |> Enum.flat_map(fn {_, info} ->
        [info["digested_path"], get_in(info, ["gzipped", "path"])]
      end)
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&Path.expand(&1, expanded_output))
    else
      _ -> []
    end
  end

  defp collect_files(input_path, exclude_regexes, skipped) do
    input_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&(generated?(&1, skipped) or should_exclude?(&1, exclude_regexes)))
  end

  defp generated?(file_path, %{files: files, nested_output: nested_output}) do
    expanded_path = Path.expand(file_path)

    MapSet.member?(files, expanded_path) or
      (is_binary(nested_output) and String.starts_with?(expanded_path, nested_output <> "/"))
  end

  defp should_exclude?(file_path, exclude_regexes) do
    filename = Path.basename(file_path)
    Enum.any?(exclude_regexes, &Regex.match?(&1, filename))
  end

  defp digest_file(file_path, input_path, output_path, opts) do
    relative_path = Path.relative_to(file_path, input_path)
    content = File.read!(file_path)

    digest = generate_digest(content)
    digested_filename = add_digest_to_filename(relative_path, digest)
    digested_path = Path.join(output_path, digested_filename)

    digested_path |> Path.dirname() |> File.mkdir_p!()

    File.write!(digested_path, content)

    file_info = %{
      logical_path: relative_path,
      digest: digest,
      digested_path: digested_filename,
      size: byte_size(content),
      mtime: get_mtime(file_path)
    }

    if opts[:gzip] do
      gzipped_content = :zlib.gzip(content)
      gzipped_path = digested_path <> ".gz"
      File.write!(gzipped_path, gzipped_content)

      Map.put(file_info, :gzipped, %{
        path: Path.relative_to(gzipped_path, output_path),
        size: byte_size(gzipped_content)
      })
    else
      file_info
    end
  end

  defp generate_digest(content) do
    :crypto.hash(@digest_algorithm, content)
    |> Base.encode16(case: :lower)
    |> String.slice(0, @digest_length)
  end

  defp add_digest_to_filename(file_path, digest) do
    extension = Path.extname(file_path)
    basename = Path.basename(file_path, extension)
    dirname = Path.dirname(file_path)

    digested_basename = "#{basename}-#{digest}#{extension}"

    if dirname == "." do
      digested_basename
    else
      Path.join(dirname, digested_basename)
    end
  end

  defp get_mtime(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        mtime
        |> NaiveDateTime.from_erl!()
        |> NaiveDateTime.to_iso8601()

      _ ->
        nil
    end
  end
end
