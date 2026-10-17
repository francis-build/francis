defmodule TextDrop do
  use Application

  def start(_type, _args) do
    children = [
      PdfExtractor,
      TextDrop.Router
    ]

    opts = [strategy: :one_for_one, name: TextDrop.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
