defmodule TextDrop.Controllers.Home do
  @upload_dir :code.priv_dir(:text_drop) |> Path.join("uploads")

  def index(%{params: params = %{"id" => id}}) do
    file_path = to_file_path(id)
    page_number = String.to_integer(params["page"] || "0")
    extracted_text = TextDrop.PdfPlumber.extract_text(file_path, page_number)
    TextDrop.Views.Home.index(%{page_number: page_number, extracted_text: extracted_text})
  end

  def index(_conn) do
    TextDrop.Views.Home.index(%{})
  end

  def create(conn = %{params: %{"pdf" => pdf}}) do
    id = TextDrop.Id.generate()
    file_path = to_file_path(id)

    File.cp!(pdf.path, file_path)

    conn
    |> Plug.Conn.put_resp_header("location", "/?id=#{id}")
    |> Plug.Conn.send_resp(302, "")
  end

  def about(_conn) do
    TextDrop.Views.Home.about(%{})
  end

  defp to_file_path(id) do
    Path.join(@upload_dir, "#{id}.pdf")
  end
end
