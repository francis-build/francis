defmodule TextDrop.Controller do
  @moduledoc """
  Shared setup for controllers.

      defmodule TextDrop.Controllers.Home do
        use TextDrop.Controller

        def index(conn), do: html(conn, Views.Home.index(%{}))
      end

  `use TextDrop.Controller` imports the Francis response helpers (`html/2,3`,
  `json/2,3`, `text/2,3`, `redirect/2,3`, ...) and `Plug.Conn`, and aliases
  `TextDrop.Controllers.Params`, the handlers and `TextDrop.Views`.
  """

  defmacro __using__(_opts) do
    quote do
      import Francis.ResponseHandlers, warn: false
      import Plug.Conn, warn: false

      alias TextDrop.Controllers.Params, warn: false
      alias TextDrop.Handlers.{Documents, Pdf}, warn: false
      alias TextDrop.Views, warn: false
    end
  end
end
