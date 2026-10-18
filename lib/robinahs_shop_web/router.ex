defmodule RobinahsShopWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RobinahsShopWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug RobinahsShopWeb.Auth, :fetch_current_user
  end

  scope "/", RobinahsShopWeb do
    get "/healthz", HealthController, :index
    pipe_through :browser
    live "/", StoreLive, :index
    get "/staff/sign-in", SessionController, :new
    post "/staff/sign-in", SessionController, :create
    delete "/staff/sign-out", SessionController, :delete
    get "/staff/reports.csv", ReportController, :export
    get "/staff/inventory.csv", InventoryController, :export

    live_session :staff, on_mount: [{RobinahsShopWeb.Auth, :require_staff}] do
      live "/staff/pos", StaffLive, :pos
      live "/staff/receiving", StaffLive, :receiving
      live "/staff/products", StaffLive, :products
      live "/staff/reports", StaffLive, :reports
      live "/staff/team", StaffLive, :team
    end
  end
end
