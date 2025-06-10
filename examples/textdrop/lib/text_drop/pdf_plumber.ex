defmodule TextDrop.PdfPlumber do
  @moduledoc """
  Extracts text from PDF files using the Python library `pdfplumber`.
  """

  def extract_text(file_path, page_number \\ 0, area \\ nil) do
    """
    import pdfplumber
    import logging

    logging.getLogger("pdfminer").setLevel(logging.ERROR)

    def main(file_path, page_number=0, area=None):
        with pdfplumber.open(file_path) as pdf:
            page = pdf.pages[page_number]
            if area:
                return page.within_bbox(area).extract_text()
            else:
                return page.extract_text()

    if isinstance(file_path, bytes):
        file_path = file_path.decode('utf-8')

    main(file_path, page_number, area)
    """
    |> Pythonx.eval(%{"file_path" => file_path, "page_number" => page_number, "area" => area})
    |> elem(0)
    |> Pythonx.decode()
  end
end
