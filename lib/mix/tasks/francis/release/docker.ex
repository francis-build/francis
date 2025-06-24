defmodule Mix.Tasks.Francis.Release.Docker do
  @moduledoc false

  @behaviour Mix.Tasks.Francis.Release

  @dockerfile_template """
  ARG ELIXIR_VERSION=<%= @elixir_version %>
  ARG OTP_VERSION=<%= @otp_version %>
  ARG DEBIAN_VERSION=bookworm-20250520-slim
  ARG BUILDER_IMAGE=\"hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}\"
  ARG RUNNER_IMAGE=\"debian:${DEBIAN_VERSION}\"

  # Build Stage
  FROM ${BUILDER_IMAGE} AS build
  ENV MIX_ENV=prod

  # Install build dependencies
  RUN apt-get update -y && apt-get install curl -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

  # Set working directory
  WORKDIR /app

  # Copy application code
  COPY . .

  # Install dependencies
  RUN mix local.hex --force && mix local.rebar --force && mix deps.get && mix compile
  # Build the release
  RUN mix release

  # Run Stage
  FROM ${RUNNER_IMAGE} AS run
  ENV LANG=en_US.UTF-8
  ENV LANGUAGE=en_US:en
  ENV LC_ALL=en_US.UTF-8

  # Install runtime dependencies
  RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
  RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

  # Set working directory
  WORKDIR /app

  # set runner ENV
  ENV MIX_ENV="prod"

  # Copy the release from the build stage
  COPY --from=build /app/_build/${MIX_ENV}/rel/<%= @app %> ./
  COPY --from=build /app/priv ./priv

  # Set environment variables
  ENV HOME=/app

  # Expose port
  EXPOSE <%= @port %>

  # Start the application
  CMD [\"bin/<%= @app %>\", \"start\"]
  """

  @dockerignore_template """
  .git
  _build
  deps
  doc
  .elixir_ls
  """

  @impl true
  @doc "Generates Docker and .dockerignore for deployment."
  @spec generate_files(keyword()) :: :ok
  def generate_files(args) do
    app = Mix.Project.config() |> Keyword.fetch!(:app)
    {port, args} = Keyword.pop(args, :port, 4000)
    {elixir_version, args} = Keyword.pop(args, :elixir_version, "1.18.4")
    {otp_version, []} = Keyword.pop(args, :otp_version, "27.3.4")

    docker_file =
      EEx.eval_string(@dockerfile_template,
        assigns: [app: app, port: port, elixir_version: elixir_version, otp_version: otp_version]
      )

    docker_ignore = EEx.eval_string(@dockerignore_template, assigns: [])

    Mix.Generator.create_file("Dockerfile", docker_file)
    Mix.Generator.create_file(".dockerignore", docker_ignore)

    :ok
  end
end
