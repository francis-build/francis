# Contributing to Francis

Thank you for your interest in contributing to Francis! This guide will help you get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/francis.git`
3. Install dependencies: `mix deps.get`
4. Run the tests: `mix test`

## Development

### Running the Full CI Suite Locally

```bash
mix test --all-warnings
mix credo --strict
mix dialyzer
mix sobelow
mix hex.audit
mix deps.audit
mix deps.unlock --check-unused
```

### Code Style

- Run `mix format` before committing
- Run `mix credo --strict` to check for style issues
- Add `@spec` annotations to all public functions
- Add `@moduledoc` and `@doc` to public modules and functions

## Submitting Changes

1. Create a feature branch: `git checkout -b my-feature`
2. Make your changes
3. Add tests for new functionality
4. Ensure all tests pass: `mix test`
5. Format your code: `mix format`
6. Commit with a clear message describing the change
7. Push and open a Pull Request

## Reporting Issues

- Use [GitHub Issues](https://github.com/francis-build/francis/issues)
- Include Elixir/OTP versions and a minimal reproduction if possible

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
