import Config

# Tests store their uploads outside priv/.
config :text_drop, upload_dir: "tmp/uploads"

# An ephemeral port keeps `mix test` from colliding with a running dev server.
config :francis, dev: false, bandit_opts: [port: 0]

# Keep Plug.Logger request lines out of the test output.
config :logger, level: :warning
