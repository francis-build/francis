[
  import_deps: [:ecto, :ecto_sql],
  subdirectories: ["priv/*/migrations"],
  inputs: ["{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"],
  line_length: 120
]
