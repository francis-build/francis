defmodule PhoenixEmbedWeb.Router do
  use PhoenixEmbedWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixEmbedWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PhoenixEmbedWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Forward all /api requests to the Francis API router.
  # Phoenix strips the /api prefix, so Francis routes are relative (e.g. /items).
  forward "/api", PhoenixEmbedWeb.FrancisApi
end
