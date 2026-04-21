defmodule Support.SseTester do
  @moduledoc """
  SSE client to test Francis SSE routes
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(%{url: url, parent_pid: parent_pid}) do
    uri = URI.parse(url)
    port = uri.port || 80
    host = uri.host || "localhost"
    path = uri.path || "/"

    {:ok, conn} = Mint.HTTP.connect(:http, host, port, [])

    {:ok, conn, request_ref} =
      Mint.HTTP.request(conn, "GET", path, [
        {"accept", "text/event-stream"},
        {"cache-control", "no-cache"}
      ], "")

    {:ok, %{conn: conn, request_ref: request_ref, parent_pid: parent_pid, buffer: ""}}
  end

  def handle_info(message, state) do
    case Mint.HTTP.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = Enum.reduce(responses, %{state | conn: conn}, &handle_response/2)
        {:noreply, state}

      {:error, conn, error, _responses} ->
        send(state.parent_pid, {:client, {:error, error}})
        {:stop, :normal, %{state | conn: conn}}

      :unknown ->
        {:noreply, state}
    end
  end

  defp handle_response({:status, _ref, status}, state) do
    send(state.parent_pid, {:client, {:status, status}})
    state
  end

  defp handle_response({:headers, _ref, headers}, state) do
    send(state.parent_pid, {:client, {:headers, headers}})
    state
  end

  defp handle_response({:data, _ref, data}, state) do
    buffer = state.buffer <> data
    {events, remaining} = parse_events(buffer)
    Enum.each(events, fn event -> send(state.parent_pid, {:client, event}) end)
    %{state | buffer: remaining}
  end

  defp handle_response({:done, _ref}, state) do
    send(state.parent_pid, {:client, :done})
    state
  end

  defp handle_response({:error, _ref, error}, state) do
    send(state.parent_pid, {:client, {:error, error}})
    state
  end

  defp handle_response(_, state), do: state

  defp parse_events(buffer) do
    case String.split(buffer, ~r/\r?\n\r?\n/, parts: 2, trim: false) do
      [event_data, rest] ->
        event = parse_event(event_data)
        {more_events, remaining} = parse_events(rest)
        {[event | more_events], remaining}

      [_incomplete] ->
        {[], buffer}
    end
  end

  defp parse_event(event_data) do
    lines = String.split(event_data, "\n", trim: true)

    event =
      Enum.reduce(lines, %{data: []}, fn line, acc ->
        case String.split(line, ":", parts: 2) do
          ["data", data] -> %{acc | data: [String.trim_leading(data) | acc.data]}
          _ -> acc
        end
      end)

    data = event.data |> Enum.reverse() |> Enum.join("\n")

    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> data
    end
  end

  def terminate(_reason, state) do
    if state.conn, do: Mint.HTTP.close(state.conn)
  end
end
