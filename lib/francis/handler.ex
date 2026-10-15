defmodule Francis.Handler do
  @moduledoc false
  # Invocation helpers shared by the WebSocket and SSE event loops.

  @doc """
  Calls `handler` with an event the handler is allowed to leave unmatched
  (`:join`, `{:close, _}`, `{:info, _}`).

  Returns `{:ok, result}`, or `:unmatched` when the handler has no clause for
  the event. "No clause" means the function that failed to match was called
  with exactly `[event, socket]` — the handler itself, or a function it
  delegates to unchanged (`fn e, s -> MyApp.Socket.handle(e, s) end`). Any
  other `FunctionClauseError` is a real bug in user code and is re-raised.
  """
  @spec call_optional(function(), term(), map()) :: {:ok, term()} | :unmatched
  def call_optional(handler, event, socket) do
    {:ok, handler.(event, socket)}
  rescue
    e in FunctionClauseError ->
      case __STACKTRACE__ do
        [{_mod, _fun, [^event, ^socket], _location} | _] -> :unmatched
        stacktrace -> reraise(e, stacktrace)
      end
  end
end
