# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

### Added
- `@spec` annotations on all public functions in `Francis.Websocket` and `Francis.Static`
- Documentation for telemetry events emitted during route dispatch
- Documentation for `forward/2` router composition
- Input validation for Elixir and OTP version strings in `mix francis.release`
- `CHANGELOG.md` and `CONTRIBUTING.md`
- Watcher now excludes `_build/`, `deps/`, `.elixir_ls/`, and `.git/` directories
- Watcher gracefully handles file deletions and syntax errors during recompilation
- Security note in `Francis.Watcher` moduledoc about `Code.eval_file/1` usage

### Changed
- `plug` is now an explicit dependency (previously transitive via `bandit`)
- `ex_doc` pinned to `~> 0.34` (previously `>= 0.0.0`)
- Hex package no longer includes `test/` directory
- Project generator (`mix francis.new`) now references `{:francis, "~> 1.0"}`

### Fixed
- Typo in `unmatched/1` documentation ("umatched" -> "unmatched")
- Redundant `put_status(500)` call before `send_resp(500, ...)` in error handler
- Watcher no longer crashes on deleted files (replaced `File.stat!` with `File.stat`)
- Watcher no longer recompiles files in `_build/` and `deps/` directories

## [0.2.0]

### Added
- WebSocket support with heartbeat, lifecycle events, and path parameters
- Static asset digesting with `mix francis.digest`
- Cache manifest support via `Francis.Static`
- Docker release generation with `mix francis.release`
- Development file watcher for auto-recompilation
- Project generator with `mix francis.new`

### Changed
- Upgraded to Bandit ~> 1.0

## [0.1.0]

### Added
- Initial release
- HTTP route macros (`get`, `post`, `put`, `delete`, `patch`)
- Response helpers (`json`, `text`, `html`, `redirect`)
- Plug.Router integration with telemetry
- Custom error handler support
- Static file serving via Plug.Static
