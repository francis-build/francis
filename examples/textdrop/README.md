# TextDrop

Upload a PDF and take it apart: read its metadata, browse its pages, draw areas
on a page to extract the text inside them, and see every word and table the
page contains. A [Francis](https://github.com/francis-build/francis) example
built on [pdf_extractor](https://hex.pm/packages/pdf_extractor).

## How the code is organised

```
lib/text_drop/
  router.ex             routes, plugs and the error handler hook
  controller.ex         `use TextDrop.Controller`: response helpers, Plug.Conn, aliases
  view.ex               `use TextDrop.View`: helpers, layout alias, `template/3`, `render_partial/2`
  errors.ex             what each error reason means: status, title, message
  error_handler.ex      sends errors as HTML pages, or as JSON under /api/
  static.ex             cache headers for digested assets
  handlers/             what the app does, independent of HTTP
    documents.ex        store uploads, find them by id, delete them
    pdf.ex              metadata, pages, text, areas, words, tables, rendering
    area.ex             a rectangle on a page: build, clamp, hand to the extractor
    metadata.ex         raw PDF metadata -> labelled values, dates reformatted
  controllers/          thin web layer: cast params, call a handler, render
    params.ex           request parameters -> values the handlers accept
    home.ex             upload form, upload, about page
    documents.ex        the document page
    api.ex              JSON endpoints used by the workbench
  views/                one module per page with its templates in a folder of the same name
priv/static/js/workbench/
  main.js               wires the toolbar, the viewer and the panels together
  overlay.js            canvas over the page: layers of boxes, hover, drawing
  panels/*.js           one module per tab, each owning its controls and layer
  client.js, tabs.js, status.js, geometry.js, dom.js
```

## Francis features used

- `use Francis` with a custom `error_handler` (`lib/text_drop/error_handler.ex`).
  Handlers return `{:error, reason}` and the error handler turns each reason into
  a `Francis.ErrorPage`, or into JSON under `/api/`.
- `html/2,3`, `json/2,3`, `text/2` and `redirect/3` response helpers.
- `Francis.Plug.SecureHeaders` and `Francis.Plug.CSP`. The policy forbids inline
  scripts, so all behaviour lives in `priv/static/js/workbench.js`.
- `Francis.HTML.escape/1` for every value a template prints.
- Compile-time `config :francis` for `static` (served at `/assets`) and `parser`
  (JSON bodies, 20 MB uploads) in `config/config.exs`.
- `mix francis.digest` (through the `mix assets.deploy` alias),
  `Francis.Static.static_path/2` in the templates and
  `Francis.Static.cache_control/1` for immutable cache headers on digested files
  (`lib/text_drop/static.ex`).
- The `PORT` environment variable: no port is configured for production, the
  Dockerfile sets `ENV PORT=4000`.

## Running

```sh
mix deps.get
mix francis.server
```

Open <http://localhost:4000>. pdf_extractor downloads a Python runtime the first
time the application starts.

```sh
mix test                        # everything, including the extractor tests
mix test --exclude integration  # only what runs without Python
```

## Static assets

```sh
mix assets.deploy             # digests priv/static in place and writes cache_manifest.json
mix francis.digest --clean    # removes the previous digest output before regenerating
```

Digest output is ignored by git. The Dockerfile runs `mix assets.deploy` in the
build stage, so templates link to hashed file names in production and to the
plain names in development. The workbench script is loaded as an ES module;
its `import` statements use the plain file names, which the digest keeps next
to the hashed copies.

## Deploying

```sh
docker build -t textdrop .
docker run --rm -p 4000:4000 textdrop
```

`config/deploy.yml` deploys with [kamal](https://kamal-deploy.org). The image
is not pushed to Docker Hub: Kamal starts a registry on your machine
(`localhost:5555`) and tunnels it to the server over SSH, so no registry
credentials are needed. This needs Docker and Kamal 2.10 or newer on your
machine, and you have to stay online for the whole deploy because the server
pulls the image through that tunnel.

```sh
kamal setup    # first time: installs Docker and kamal-proxy on the server
kamal deploy
```
