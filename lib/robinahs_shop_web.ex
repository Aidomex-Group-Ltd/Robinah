defmodule RobinahsShopWeb do
  def static_paths,
    do: ~w(assets resources brand favicon.ico favicon.svg robots.txt site.webmanifest)

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json], layouts: [html: RobinahsShopWeb.Layouts]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import RobinahsShopWeb.Components
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {RobinahsShopWeb.Layouts, :app}
      import RobinahsShopWeb.Components
      alias RobinahsShop.{Shop, Accounts}
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: RobinahsShopWeb.Endpoint,
        router: RobinahsShopWeb.Router,
        statics: RobinahsShopWeb.static_paths()
    end
  end

  defmacro __using__(which), do: apply(__MODULE__, which, [])
end
