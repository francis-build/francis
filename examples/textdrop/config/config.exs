import Config

# Where uploaded PDFs are kept, relative to the working directory.
config :text_drop, upload_dir: "priv/uploads"

# `static` and `parser` are read with `Application.compile_env/2`, so they live
# here and recompile the router when they change. A `parser` value replaces the
# whole default, hence all three parsers are restated to raise the upload limit.
config :francis,
  static: [
    from: "priv/static",
    at: "/assets",
    gzip: true,
    headers: {TextDrop.Static, :headers, []}
  ],
  parser: [
    parsers: [:urlencoded, {:multipart, length: 20_000_000}, :json],
    json_decoder: Jason
  ]

import_config "#{config_env()}.exs"
