# Changelog

## 0.4.0

### Breaking changes

- **WebSocket process messages go through the handler.** Messages sent with
  `send(socket.transport, msg)` are now delivered to the handler as
  `{:info, msg}` first. Without an `{:info, _}` clause they are forwarded to the
  client as before (binaries, maps, lists and `{type, payload}` frames); any
  other message is logged and dropped instead of crashing the socket.
  **A catch-all clause such as `_event, _socket -> :ok` now also catches these
  messages, so they are no longer forwarded.** Add an explicit
  `{:info, msg}, _socket -> {:reply, msg}` clause to keep forwarding them.
- **Custom error handlers receive the exception.** Errors raised before a route
  runs (for example `Plug.Parsers.ParseError` for malformed JSON) used to reach
  the handler as `%{kind: _, reason: _, stack: _}`. The handler now always gets
  `{:error, reason}`, an exception, or `{kind, reason}` for throws and exits.
- **The default error page uses the exception's status.** Malformed JSON
  returns 400 instead of 500, and exceptions with a `plug_status` (such as
  `Ecto.NoResultsError`) return that status. `{:error, _}` still returns 500.
- **`static`, `parser` and `log_level` are compile-time configuration.** They are
  read with `Application.compile_env`, so changing them recompiles the router,
  and setting them only in `config/runtime.exs` fails at boot instead of being
  silently ignored.
- **The `PORT` environment variable is used** when `bandit_opts` has no `:port`.
  An invalid value fails at boot with an error naming `PORT`.
- **Internal modules changed.** `ws/3` and `sse/3` no longer generate a module
  per route; the public helpers of `Francis.Websocket` (`setup_heartbeat/1`,
  `handle_heartbeat/1`, `cancel_heartbeat/1`, `call_join/2`, `call_close/3`)
  were removed; `Francis.SSE.run/3` now takes `(conn, handler, opts)`; and
  `Francis.SSE.format_event/1` returns iodata. These modules were documented as
  internal.
- **SSE output is sanitised.** Multi-line data is sent as one `data:` line per
  line, line breaks are stripped from `event` and `id`, and a non-integer
  `retry` is omitted.
- **Elixir `~> 1.15` is required.**

### Fixed

- `ws/3` routes could replace Francis modules (`ws "/static"` replaced
  `Francis.Static`), and two routers declaring the same WebSocket path shared
  one handler.
- `ws/3` and `sse/3` handlers can use the router's aliases, imports and module
  attributes.
- Optional events (`:join`, `{:close, _}`, `{:info, _}`) are skipped when the
  handler has no clause for them, including handlers that delegate to another
  function; a `FunctionClauseError` raised deeper in user code is no longer
  swallowed.
- Open redirect: `redirect/2,3` sends paths containing a backslash, control
  characters or leading whitespace (e.g. `/\evil.com`) to `/`.
- SSE event injection through line breaks in relayed messages.
- `bandit_opts` and `error_handler` from application config were ignored.
- `static: false` did not disable static serving.
- `mix francis.digest` re-digested its own output when run again, path
  traversal through manifest entries in `--clean`, and `--age` was ignored.
- `mix francis.new --no-sup` generated a supervised app.
- `mix francis.release --port` only changed `EXPOSE`; the Dockerfile now also
  sets `ENV PORT`.
- The dev watcher scanned `deps/` and `_build/` every 100ms, evaluated
  `mix.exs` and tests, crashed on a file that failed to compile, and found
  nothing in umbrella apps.

### Added

- `{:info, msg}` WebSocket event.
- `PORT` environment variable support.
- `Francis.Static.cache_control/1`, and the digest manifest is cached in
  `:persistent_term`.
- Static files are served gzipped when a `.gz` variant exists (`gzip: true`).

### Dependencies

- Updated bandit, plug, thousand_island, websock_adapter, req (test), finch,
  mint and others to their latest versions.
