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
  """

  @root "lib/text_drop/views"

  defmacro __using__(_opts) do
    quote do
      require EEx

      import TextDrop.View, only: [template: 2, template: 3]
      import TextDrop.Views.Helpers, warn: false

      alias TextDrop.Views.Layout, warn: false

      @templates_dir TextDrop.View.templates_dir(__MODULE__)
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
end
