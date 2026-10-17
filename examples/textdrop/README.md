# TextDrop

Upload a PDF and take it apart: read its metadata, browse its pages, draw areas
on a page to extract the text inside them, and see every word and table the
page contains. A [Francis](https://github.com/francis-build/francis) example
built on [pdf_extractor](https://hex.pm/packages/pdf_extractor).

## How the code is organised

```
lib/text_drop/
  router.ex             routes, plugs and the error handler hook
  error_handler.ex      {:error, reason} and exceptions -> HTML or JSON error responses
  static.ex             cache headers for digested assets
  handlers/             what the app does, independent of HTTP
    documents.ex        store uploads, find them by id, delete them
    pdf.ex              metadata, pages, text, areas, words, tables, rendering
  controllers/          thin web layer: cast params, call a handler, render
    params.ex           request parameters -> values the handlers accept
    home.ex             upload form, upload, about page
    documents.ex        the document page
    api.ex              JSON endpoints used by the workbench
  views/                EEx templates and the layout around them
priv/static/js/workbench.js   the interactive page viewer
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
plain names in development.

## Deploying

```sh
docker build -t textdrop .
docker run --rm -p 4000:4000 textdrop
```

`config/deploy.yml` deploys the image with [kamal](https://kamal-deploy.org):
`kamal deploy`.
