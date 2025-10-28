defmodule Chat do
  use Application

  def start(_type, _args) do
    children = [
      Chat.Room,
      {Bandit, plug: Chat.Router}
    ]

    opts = [strategy: :one_for_one, name: Chat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
