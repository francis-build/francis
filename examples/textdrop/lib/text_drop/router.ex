defmodule TextDrop.Router do
  use Francis, error_handler: &TextDrop.ErrorHandler.handle/2

  alias TextDrop.Controllers

  plug(Francis.Plug.SecureHeaders)

  # Scripts may only come from /assets (see priv/static/js/workbench.js). Styles
  # stay inline-friendly because `Francis.ErrorPage` renders an inline <style>.
  plug(Francis.Plug.CSP, directives: %{"style-src" => "'self' 'unsafe-inline'"})

  get("/health", fn conn -> text(conn, "OK") end)

  # HTML pages
  get("/", &Controllers.Home.index/1)
  post("/", &Controllers.Home.create/1)
  get("/about", &Controllers.Home.about/1)
  get("/documents/:id", &Controllers.Documents.show/1)

  # JSON API used by the workbench (priv/static/js/workbench.js)
  get("/api/documents/:id/pages/:page/image", &Controllers.Api.page_image/1)
  get("/api/documents/:id/pages/:page/text", &Controllers.Api.page_text/1)
  post("/api/documents/:id/pages/:page/areas", &Controllers.Api.page_areas/1)
  get("/api/documents/:id/pages/:page/words", &Controllers.Api.page_words/1)
  get("/api/documents/:id/pages/:page/tables", &Controllers.Api.page_tables/1)

  unmatched(fn conn -> html(conn, 404, Francis.ErrorPage.render(404)) end)
end
