defmodule TextDrop.Router do
  use Francis, static: [from: "assets", at: "/assets"]

  get("/health", fn _ -> "OK" end)

  get("/", &TextDrop.Controllers.Home.index/1)

  post("/", &TextDrop.Controllers.Home.create/1)

  get("/about", &TextDrop.Controllers.Home.about/1)

  unmatched(fn _ -> "not found" end)
end
