defmodule TextDrop.IntegrationCase do
  @moduledoc """
  Case template for tests that run the real extractor, and therefore need the
  Python runtime. Tags them `:integration` and provides a temporary directory
  holding the fixture PDF.
  """

  use ExUnit.CaseTemplate

  alias TextDrop.PdfFixture

  using do
    quote do
      @moduletag :integration

      alias TextDrop.PdfFixture
    end
  end

  setup_all do
    dir = Path.join(System.tmp_dir!(), "textdrop-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir, fixture: PdfFixture.write!(dir)}
  end
end
