defmodule Mix.Tasks.Francis.Release do
  @moduledoc """
  Generates Docker deployment files for Francis projects.

  This task creates a `Dockerfile` and `.dockerignore` in the current working directory,
  using the project name and configuration. It is intended to simplify containerization
  and deployment of Francis-based applications.

  ## Usage

      mix francis.release [OPTIONS]

  ## Command line options

    * `-p`, `--port <port>` - Port the container listens on (default: 4000). Sets both
      `ENV PORT` and `EXPOSE` in the Dockerfile; Francis reads `PORT` at runtime when
      `bandit_opts` does not set `:port`.
    * `--elixir-version <version>` - Elixir version to use in the Docker image (default: 1.18.4).
    * `--otp-version <version>` - Erlang/OTP version to use in the Docker image (default: 27.3.4).

  Example:

      mix francis.release --port 8080 --elixir-version 1.16.2 --otp-version 26.2.1

  This will generate a Dockerfile that sets `PORT=8080`, exposes port 8080 and uses the specified
  Elixir and OTP versions. If you use some combination of versions that are not
  compatible it will fail when building the docker image.

  All files are generated in the current working directory. Unknown options are ignored.
  """
  use Mix.Task

  alias Mix.Tasks.Francis.Release.Docker

  @shortdoc "Generates files for Francis deployment"

  @callback generate_files(args :: list) :: any()

  @impl true
  def run(args) do
    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [port: :integer, elixir_version: :string, otp_version: :string],
        aliases: [
          p: :port,
          elixir_version: :"elixir-version",
          otp_version: :"otp-version"
        ]
      )

    Docker.generate_files(opts)
  end
end
