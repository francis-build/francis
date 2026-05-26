defmodule PhoenixEmbedWeb.PageController do
  use PhoenixEmbedWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
