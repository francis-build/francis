defmodule TextDrop.Handlers.DocumentsTest do
  # Not async: one test compares listings of the shared upload directory.
  use ExUnit.Case, async: false

  alias TextDrop.Handlers.Documents
  alias TextDrop.PdfFixture

  describe "fetch/1" do
    test "rejects ids that TextDrop did not generate" do
      for id <- ["../../mix.exs", "ABCDEF0123456789ABCDEF0123456789", "abc", nil, 42] do
        assert Documents.fetch(id) == {:error, :not_found}
      end
    end

    test "does not find an id that was never stored" do
      assert Documents.fetch(String.duplicate("f", 32)) == {:error, :not_found}
    end
  end

  describe "store/1" do
    @describetag :integration

    @tag :tmp_dir
    test "stores a readable PDF under a fresh id", %{tmp_dir: tmp_dir} do
      assert {:ok, id} = Documents.store(PdfFixture.upload(tmp_dir))
      on_exit(fn -> Documents.delete(id) end)

      assert id =~ ~r/\A[0-9a-f]{32}\z/
      assert {:ok, path} = Documents.fetch(id)
      assert Path.dirname(path) == Application.fetch_env!(:text_drop, :upload_dir)
      assert File.read!(path) == PdfFixture.binary()
    end

    @tag :tmp_dir
    test "rejects a file that is not a PDF and keeps nothing", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "not.pdf")
      File.write!(source, "plain text")
      upload = %Plug.Upload{path: source, filename: "not.pdf", content_type: "application/pdf"}

      upload_dir = Application.fetch_env!(:text_drop, :upload_dir)
      before = upload_dir |> File.ls!() |> MapSet.new()

      assert Documents.store(upload) == {:error, :unreadable}
      assert upload_dir |> File.ls!() |> MapSet.new() == before
    end
  end
end
