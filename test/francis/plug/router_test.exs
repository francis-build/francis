defmodule Francis.Plug.RouterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  describe "match/2" do
    setup do
      %{mod: Support.RouteTester.generate_module(quote do: get("/:id", fn _ -> "ok" end))}
    end

    test "does not crash on malformed percent-encoding", %{mod: mod} do
      # URI.decode/1 is lenient on the supported Elixir versions, so the raw
      # sequence is routed as-is instead of raising Plug.Router.MalformedURIError
      conn = mod.call(conn(:get, "/%E0%A4%A"), mod.init([]))

      assert conn.status == 200
    end

    test "returns 404 and logs a warning for unmatched routes", %{mod: mod} do
      log =
        capture_log(fn ->
          conn = mod.call(conn(:get, "/a/b"), mod.init([]))

          assert conn.status == 404
          assert conn.halted
          assert conn.resp_body =~ "Not Found"
        end)

      assert log =~ "[warning] Failed to match route: GET /a/b"
      # capture_log sees every process, so only check this request's line;
      # concurrent async tests may log unrelated errors.
      refute log =~ "[error] Failed to match route"
    end
  end
end
