defmodule TextDrop.Router do
  use Francis, static: [from: "priv/static", at: "/assets", gzip: true], bandit_opts: [port: 5050]

  get("/health", fn _ -> "OK" end)

  get("/", &TextDrop.Controllers.Home.index/1)

  post("/", &TextDrop.Controllers.Home.create/1)

  get("/about", &TextDrop.Controllers.Home.about/1)

  unmatched(fn _ -> "not found" end)
end
