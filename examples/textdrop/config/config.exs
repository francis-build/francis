import Config

config :francis, dev: true

config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "text_drop"
  version = "0.0.0"
  requires-python = "==3.11.*"
  dependencies = [
    "pdfplumber==0.11.6"
  ]
  """
