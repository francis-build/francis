import Config

config :api, watcher: false
config :api, ecto_repos: [Api.Repo]

config :api, Api.Repo,
  database: "api_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox
