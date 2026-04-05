defmodule Mix.Tasks.Francis.New do
  use Mix.Task

  @shortdoc "Generates a new Francis project"

  @mix_template """
  defmodule <%= Macro.camelize(module_name) %>.MixProject do
    use Mix.Project

    def project do
      [
        app: :<%= app_name %>,
        version: "0.1.0",
        elixir: "~> 1.18",
        start_permanent: Mix.env() == :prod,
        deps: deps(),
        elixirc_paths: ["lib"]
      ]
    end

    def application do
      [mod: {<%= Macro.camelize(module_name) %>, []}, extra_applications: [:logger]]
    end

    defp deps do
      [
        {:francis, "~> 0.2"}
      ]
    end
  end
  """

  @gitignore_template """
  # The directory Mix will write compiled artifacts to.
  /_build/

  # If you run "mix test --cover", coverage assets end up here.
  /cover/

  # The directory Mix downloads your dependencies sources to.
  /deps/

  # Where 3rd-party dependencies like ExDoc output generated docs.
  /doc/

  # Ignore .fetch files in case you like to edit your project deps locally.
  /.fetch

  # If the VM crashes, it generates a dump, let's ignore it too.
  erl_crash.dump
  """

  @config_template """
  import Config

  import_config "\#{config_env()}.exs"
  """

  @dev_config_template """
  import Config

  config :francis, dev: true
  """

  @prod_config_template """
  import Config

  config :francis, dev: false
  """

  @test_config_template """
  import Config

  config :francis, dev: false
  """

  @with_sup_app_template """
  defmodule <%= Macro.camelize(module_name) %> do
    use Application

    def start(_type, _args) do
      children = [
        <%= Macro.camelize(module_name) %>.Router
      ]

      opts = [strategy: :one_for_one, name: <%= Macro.camelize(module_name) %>.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  """

  @with_sup_router_template """
  defmodule <%= Macro.camelize(module_name) %>.Router do
    use Francis
    get("/", fn _ -> "ok" end)
    unmatched(fn _ -> "not found" end)
  end
  """

  @without_sup_app_template """
  defmodule <%= Macro.camelize(module_name)%> do
    use Francis
    get("/", fn _ -> "ok" end)
    unmatched(fn _ -> "not found" end)
  end
  """

  @formatter_template """
  [
    inputs: ["{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  @moduledoc """
  Generates a new Francis project.
  This task creates a new directory with the specified application name and a basic project structure.

  ## Usage

      mix francis.new <app_name> [--sup [<supervisor_module_name>]]

  ## Examples

      mix francis.new my_app
      mix francis.new my_app --sup
      mix francis.new my_app --sup MyApp
  """
  def usage, do: @moduledoc

  def main(args), do: run(args)

  def run([]) do
    Mix.raise("You must provide an application name, e.g. `mix francis.new my_app`")
  end

  def run([app_name | opts]) do
    unless Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_]*$/, app_name) do
      Mix.raise(
        "Application name must only contain alphanumeric characters and underscores, and start with a letter"
      )
    end

    if File.exists?(app_name) do
      Mix.raise("Directory `#{app_name}` already exists. Please choose a different name.")
    end

    {sup, supervisor_module_name} =
      OptionParser.parse!(opts, strict: [sup: :boolean, supervisor_module_name: :string])

    Mix.Generator.create_directory(app_name)

    module_name =
      if supervisor_module_name == [],
        do: app_name,
        else: hd(supervisor_module_name)

    copy_template(:mix, Path.join(app_name, "mix.exs"), %{
      module_name: module_name,
      app_name: app_name
    })

    copy_template(:gitignore, Path.join(app_name, ".gitignore"), %{})

    Mix.Generator.create_directory(Path.join(app_name, "lib"))

    # Create config directory and config files
    config_dir = Path.join(app_name, "config")
    Mix.Generator.create_directory(config_dir)
    copy_template(:config, Path.join(config_dir, "config.exs"), %{app_name: app_name})
    copy_template(:dev_config, Path.join(config_dir, "dev.exs"), %{app_name: app_name})
    copy_template(:prod_config, Path.join(config_dir, "prod.exs"), %{app_name: app_name})
    copy_template(:test_config, Path.join(config_dir, "test.exs"), %{app_name: app_name})

    copy_template(:formatter, Path.join(app_name, ".formatter.exs"), %{})

    if sup != [] && hd(sup) do
      copy_template(:with_sup_app, Path.join([app_name, "lib", app_name, "application.ex"]), %{
        module_name: module_name
      })

      copy_template(:with_sup_router, Path.join([app_name, "lib", app_name, "router.ex"]), %{
        module_name: module_name
      })
    else
      copy_template(:without_sup_app, Path.join([app_name, "lib", app_name, "#{app_name}.ex"]), %{
        module_name: module_name
      })
    end

    Mix.shell().info("\nYour Francis project is ready!\n\nNext steps to start your project:")
    Mix.shell().info("\n\tcd #{app_name}\n\tmix deps.get\n\tmix francis.server\n")
  end

  defp copy_template(:mix, dest, assigns),
    do: write_template(@mix_template, dest, assigns)

  defp copy_template(:gitignore, dest, assigns),
    do: write_template(@gitignore_template, dest, assigns)

  defp copy_template(:config, dest, assigns),
    do: write_template(@config_template, dest, assigns)

  defp copy_template(:dev_config, dest, assigns),
    do: write_template(@dev_config_template, dest, assigns)

  defp copy_template(:prod_config, dest, assigns),
    do: write_template(@prod_config_template, dest, assigns)

  defp copy_template(:test_config, dest, assigns),
    do: write_template(@test_config_template, dest, assigns)

  defp copy_template(:with_sup_app, dest, assigns),
    do: write_template(@with_sup_app_template, dest, assigns)

  defp copy_template(:with_sup_router, dest, assigns),
    do: write_template(@with_sup_router_template, dest, assigns)

  defp copy_template(:without_sup_app, dest, assigns),
    do: write_template(@without_sup_app_template, dest, assigns)

  defp copy_template(:formatter, dest, assigns),
    do: write_template(@formatter_template, dest, assigns)

  defp write_template(template, dest, assigns) do
    # Make Macro available in the template context and merge assigns
    bindings = [Macro: Macro] ++ Map.to_list(assigns)
    rendered = EEx.eval_string(template, bindings)
    Mix.Generator.create_file(dest, rendered)
  end
end
