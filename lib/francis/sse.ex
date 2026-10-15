defmodule Francis.SSE do
  @moduledoc """
  Event loop backing the `Francis.sse/3` macro.

  This module holds the SSE lifecycle logic (keepalive, join/close events,
  response formatting, chunked streaming) shared by every SSE route. It is not
  intended for direct use by application code.

  ## SSE Wire Format

  Each event is encoded as one or more `field: value` lines followed by a blank
  line (`\\n\\n`). Supported fields:

    * `data:` – the event payload (required); multi-line payloads are split
      into one `data:` line per line
    * `event:` – named event type (optional, defaults to `"message"`)
    * `id:` – event ID for reconnection (optional)
    * `retry:` – reconnection interval hint in ms (optional)
  """

  require Logger

  alias Francis.Handler

  @default_keepalive_interval 15_000

  @doc """
  Formats a value into an SSE-encoded iodata chunk.

  Accepts:
    * a binary string – sent as `data: <string>\\n\\n`
    * a map or list – JSON-encoded and sent as `data: <json>\\n\\n`
    * a map with `:event`, `:data`, and optionally `:id` / `:retry` keys –
      sent with the corresponding SSE fields
  """
  def format_event(%{event: event, data: data} = fields) do
    [
      field("id", Map.get(fields, :id)),
      field("event", event),
      data_lines(encode_data(data)),
      retry_field(Map.get(fields, :retry)),
      "\n"
    ]
  end

  def format_event(data), do: [data_lines(encode_data(data)), "\n"]

  @doc """
  Translates a handler return value into an action for the SSE loop.

  Returns `{:chunk, iodata, state}` when there is data to send, or
  `{:noreply, state}` when there is nothing to send.
  """
  def format_response({:reply, msg}, state) do
    {:chunk, format_event(msg), state}
  end

  def format_response(:noreply, state), do: {:noreply, state}
  def format_response(:ok, state), do: {:noreply, state}

  @doc """
  Sends the initial SSE headers and switches the connection to chunked mode.
  """
  def init_conn(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.put_resp_header("x-accel-buffering", "no")
    |> Plug.Conn.send_chunked(200)
  end

  @doc """
  Initializes the SSE connection, sends the join event, and enters the receive loop.

  Returns `conn` when the loop terminates so the outer `handle_response/3`
  receives a `Plug.Conn` struct.

  ## Options

    * `:keepalive_interval` - ms between keepalive comments (default: 15_000), `nil` disables
  """
  def run(conn, handler, opts) do
    state =
      %{
        id: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(),
        path: conn.request_path,
        params: conn.params,
        transport: self(),
        keepalive_interval: Keyword.get(opts, :keepalive_interval, @default_keepalive_interval)
      }
      |> setup_keepalive()

    conn = init_conn(conn)

    case call_join(handler, state) do
      {:chunk, data, state} -> send_chunk_or_terminate(conn, data, state, handler)
      {:noreply, state} -> loop(conn, state, handler)
    end
  end

  @doc """
  The main SSE receive loop. Waits for keepalive ticks or messages
  forwarded via `send(socket.transport, msg)`.
  """
  def loop(conn, state, handler) do
    receive do
      :__francis_sse_keepalive__ ->
        handle_keepalive_tick(conn, state, handler)

      {:plug_conn, _} ->
        loop(conn, state, handler)

      {:EXIT, _pid, reason} ->
        terminate(conn, {:exit, reason}, handler, state)

      msg ->
        handle_incoming(conn, msg, state, handler)
    end
  end

  @doc """
  Sets up the keepalive timer if configured.
  """
  def setup_keepalive(state) do
    case Map.get(state, :keepalive_interval) do
      interval when is_integer(interval) and interval > 0 ->
        timer = Process.send_after(self(), :__francis_sse_keepalive__, interval)
        Map.put(state, :keepalive_timer, timer)

      _ ->
        Map.put(state, :keepalive_timer, nil)
    end
  end

  @doc """
  Reschedules the keepalive timer and sends a comment line to keep the connection alive.
  """
  def handle_keepalive(conn, state) do
    case Map.get(state, :keepalive_timer) do
      timer when is_reference(timer) ->
        Process.cancel_timer(timer)
        interval = Map.get(state, :keepalive_interval)
        new_timer = Process.send_after(self(), :__francis_sse_keepalive__, interval)

        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> {:ok, conn, Map.put(state, :keepalive_timer, new_timer)}
          {:error, _reason} -> {:error, :closed}
        end

      _ ->
        {:ok, conn, state}
    end
  end

  @doc """
  Cancels the keepalive timer during termination.
  """
  def cancel_keepalive(state) do
    case Map.get(state, :keepalive_timer) do
      timer when is_reference(timer) -> Process.cancel_timer(timer)
      _ -> :ok
    end
  end

  @doc """
  Safely calls a handler for the `:join` event.

  If the handler has no clause for `:join`, returns `{:noreply, state}` — join
  handling is optional.
  """
  def call_join(handler, state) do
    case Handler.call_optional(handler, :join, state) do
      {:ok, result} -> format_response(result, state)
      :unmatched -> {:noreply, state}
    end
  end

  @doc """
  Safely calls a handler for the `{:close, reason}` event.

  If the handler has no clause for close events, silently succeeds.
  """
  def call_close(handler, event, state) do
    Handler.call_optional(handler, event, state)
    :ok
  end

  @doc """
  Invokes the handler for a received message and formats the response.
  Errors are logged but do not crash the connection.
  """
  def call_received(handler, msg, state) do
    handler.({:received, msg}, state)
    |> format_response(state)
  rescue
    e ->
      Logger.error("SSE Handler error: #{inspect(e)}")
      {:noreply, state}
  end

  @doc """
  Cleans up the keepalive timer and invokes the close handler.
  Returns `conn` for the outer Plug pipeline.
  """
  def terminate(conn, reason, handler, state) do
    cancel_keepalive(state)
    call_close(handler, {:close, reason}, state)
    conn
  end

  # -- Private -----------------------------------------------------------------

  defp encode_data(data) when is_binary(data), do: data
  defp encode_data(data) when is_map(data) or is_list(data), do: Jason.encode!(data)
  defp encode_data(data), do: inspect(data)

  # A bare CR or LF inside a field would end it early and let the payload
  # inject extra fields or events, so data is split into one line per field
  # and single-line fields have line breaks stripped.
  defp data_lines(data) do
    data
    |> String.split(["\r\n", "\r", "\n"])
    |> Enum.map(&["data: ", &1, "\n"])
  end

  defp field(_name, nil), do: []
  defp field(name, value), do: [name, ": ", strip_newlines(to_string(value)), "\n"]

  defp retry_field(retry) when is_integer(retry) and retry >= 0,
    do: ["retry: ", to_string(retry), "\n"]

  defp retry_field(_retry), do: []

  defp strip_newlines(value), do: String.replace(value, ["\r", "\n"], "")

  defp handle_keepalive_tick(conn, state, handler) do
    case handle_keepalive(conn, state) do
      {:ok, conn, state} -> loop(conn, state, handler)
      {:error, :closed} -> terminate(conn, :keepalive_failed, handler, state)
    end
  end

  defp handle_incoming(conn, msg, state, handler) do
    case call_received(handler, msg, state) do
      {:chunk, data, state} -> send_chunk_or_terminate(conn, data, state, handler)
      {:noreply, state} -> loop(conn, state, handler)
    end
  end

  defp send_chunk_or_terminate(conn, data, state, handler) do
    case Plug.Conn.chunk(conn, data) do
      {:ok, conn} -> loop(conn, state, handler)
      {:error, _} -> terminate(conn, :chunk_failed, handler, state)
    end
  end
end
