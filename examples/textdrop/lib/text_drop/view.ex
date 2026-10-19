defmodule TextDrop.View do
  @moduledoc """
  Shared setup for view modules.

      defmodule TextDrop.Views.Home do
        use TextDrop.View

        template(:index_body, "index.html.eex")
        template(:about_body, "about.html.eex", assigns: false)
      end

  `use TextDrop.View` imports `TextDrop.Views.Helpers` into the module and
  therefore into its templates, aliases `TextDrop.Views.Layout`, and points
  `template/3` at `lib/text_drop/views/<module name>/`, so `TextDrop.Views.Home`
  reads its templates from `lib/text_drop/views/home/`.

  ## Partials

  Every `_name.html.eex` file in that directory is compiled as a partial, and
  templates render one with `render_partial/2`, passing the assigns it needs:

      <%= render_partial("sidebar", assigns) %>

  The name may be a string or an atom. Partials are found when the view module
  compiles, so after adding a new file save the view module or run
  `mix compile --force`.
  """

  @root "lib/text_drop/views"

  defmacro __using__(_opts) do
    quote unquote: false do
      require EEx

      import TextDrop.View, only: [template: 2, template: 3]
      import TextDrop.Views.Helpers, warn: false

      alias TextDrop.Views.Layout, warn: false

      @templates_dir TextDrop.View.templates_dir(__MODULE__)

      @doc false
      for path <- TextDrop.View.partial_files(@templates_dir) do
        @external_resource path

        # `var!` puts the argument in the same scope as the `assigns` the
        # compiled template reads; the match keeps partials without assigns
        # free of warnings.
        def render_partial(unquote(TextDrop.View.partial_name(path)), var!(assigns)) do
          _ = var!(assigns)
          unquote(EEx.compile_file(path, file: path, line: 1))
        end
      end

      def render_partial(name, assigns) when is_atom(name) do
        render_partial(Atom.to_string(name), assigns)
      end

      def render_partial(name, _assigns) do
        raise ArgumentError, "no partial _#{name}.html.eex in #{@templates_dir}"
      end
    end
  end

  @doc """
  Compiles an EEx template from the module's template directory into a private
  function. The function takes `assigns` unless `assigns: false` is given.
  """
  defmacro template(name, file, opts \\ []) do
    quote do
      EEx.function_from_file(
        :defp,
        unquote(name),
        Path.join(@templates_dir, unquote(file)),
        if(Keyword.get(unquote(opts), :assigns, true), do: [:assigns], else: [])
      )
    end
  end

  @doc false
  def templates_dir(module) do
    Path.join(@root, module |> Module.split() |> List.last() |> Macro.underscore())
  end

  @doc false
  def partial_files(dir), do: dir |> Path.join("_*.html.eex") |> Path.wildcard() |> Enum.sort()

  @doc false
  def partial_name(path), do: path |> Path.basename(".html.eex") |> String.trim_leading("_")
end
