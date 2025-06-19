import Config

config :api, watcher: true

config :api, ecto_repos: [Api.Repo]

config :api, Api.Repo,
  database: "api_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool_size: 10
