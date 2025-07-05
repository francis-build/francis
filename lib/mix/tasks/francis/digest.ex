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
      This value is used for cache headers. Defaults to 31536000 (1 year).

    * `--gzip` - when set to false, does not generate gzipped files.
      Defaults to true.

    * `--exclude` - list of file patterns to exclude from digest.
      Example: `--exclude '*.txt' --exclude '*.json'`

  The output will be a set of digested files along with a cache manifest file.
  The manifest file maps original file names to their digested counterparts.

  ## Examples

      $ mix francis.digest
      Generated digested assets in priv/static:
        * app.css -> app-a1b2c3d4e5f6.css
        * app.js -> app-9f8e7d6c5b4a.js
        * manifest.json

      $ mix francis.digest assets --output priv/static
      Generated digested assets from assets to priv/static
  """

  alias Mix.Tasks.Francis.Digest.Manifest

  @default_input_path "priv/static"
  @default_age 31_536_000
  @digest_algorithm :md5
  @digest_length 8

  def run(args) do
    {opts, args} = parse_args(args)

    input_path = List.first(args) || @default_input_path
    output_path = opts[:output] || input_path

    if !File.exists?(input_path) do
      Mix.shell().error("Input path #{input_path} does not exist")
      exit({:shutdown, 1})
    end

    File.mkdir_p!(output_path)

    Mix.shell().info("Generating digested files from #{input_path} to #{output_path}")

    files = collect_files(input_path, opts[:exclude] || [])
    digested_files = Enum.map(files, &digest_file(&1, input_path, output_path, opts))

    manifest_path = Path.join(output_path, "cache_manifest.json")
    Manifest.write(manifest_path, digested_files)

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
          exclude: :keep
        ],
        aliases: [
          o: :output
        ]
      )

    opts =
      opts
      |> Keyword.put_new(:age, @default_age)
      |> Keyword.put_new(:gzip, true)
      |> process_exclude_patterns()

    {opts, args}
  end

  defp process_exclude_patterns(opts) do
    exclude_patterns =
      opts
      |> Keyword.get_values(:exclude)

    Keyword.put(opts, :exclude, exclude_patterns)
  end

  defp collect_files(input_path, exclude_patterns) do
    input_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&should_exclude?(&1, exclude_patterns))
  end

  defp should_exclude?(file_path, exclude_patterns) do
    filename = Path.basename(file_path)

    Enum.any?(exclude_patterns, fn pattern ->
      match_pattern?(filename, pattern)
    end)
  end

  defp match_pattern?(filename, pattern) do
    regex_pattern =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> String.replace("?", ".")
      |> then(&("^" <> &1 <> "$"))

    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, filename)
      _ -> false
    end
  end

  defp digest_file(file_path, input_path, output_path, opts) do
    relative_path = Path.relative_to(file_path, input_path)
    content = File.read!(file_path)

    digest = generate_digest(content)
    digested_filename = add_digest_to_filename(relative_path, digest)
    digested_path = Path.join(output_path, digested_filename)

    digested_path |> Path.dirname() |> File.mkdir_p!()

    File.write!(digested_path, content)

    gzipped_info =
      if opts[:gzip] do
        gzipped_content = :zlib.gzip(content)
        gzipped_path = digested_path <> ".gz"
        File.write!(gzipped_path, gzipped_content)

        %{
          path: Path.relative_to(gzipped_path, output_path),
          size: byte_size(gzipped_content)
        }
      end

    file_info = %{
      logical_path: relative_path,
      digest: digest,
      digested_path: digested_filename,
      size: byte_size(content),
      mtime: get_mtime(file_path)
    }

    if gzipped_info do
      Map.put(file_info, :gzipped, gzipped_info)
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
