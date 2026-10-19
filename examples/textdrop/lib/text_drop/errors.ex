defmodule TextDrop.Errors do
  @moduledoc """
  What each error means to the user: an HTTP status, a title and a message.

  `describe/1` covers the reasons handlers return in `{:error, reason}` tuples
  and the exceptions Plug raises before a route runs. A `nil` title and message
  mean the generic text for the status is good enough. Unknown reasons get a
  plain 500, so a programming error never shows its details.
  """

  @type description ::
          {status :: 400..599, title :: String.t() | nil, message :: String.t() | nil}

  @spec describe(term()) :: description()
  def describe(:route_not_found), do: {404, nil, nil}

  def describe(:not_found),
    do: {404, "Document not found", "This upload does not exist. Upload the PDF again."}

  def describe(:page_out_of_range),
    do: {400, "Page out of range", "This document has no page with that number."}

  def describe(:missing_pdf),
    do: {400, "No PDF uploaded", "Choose a PDF file before submitting the form."}

  def describe(:unreadable),
    do: {422, "Could not read PDF", "The file could not be parsed as a PDF document."}

  def describe(:invalid_area),
    do: {400, "Invalid area", "Each area must have a width and a height inside the page."}

  def describe({:invalid, field}),
    do: {400, "Invalid #{field}", "The #{field} parameter is not valid."}

  def describe(%Plug.Parsers.RequestTooLargeError{}),
    do: {413, "File too large", "PDF uploads are limited to 20 MB."}

  def describe(%Plug.Parsers.ParseError{}),
    do: {400, "Malformed request", "The request body could not be parsed."}

  def describe(exception) when is_exception(exception),
    do: {Plug.Exception.status(exception), nil, nil}

  def describe(_reason), do: {500, nil, nil}
end
