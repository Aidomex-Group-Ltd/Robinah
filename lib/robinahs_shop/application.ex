defmodule RobinahsShop.Application do
  use Application

  def start(_type, _args) do
    children = [
      RobinahsShop.Repo,
      {Phoenix.PubSub, name: RobinahsShop.PubSub},
      RobinahsShop.LoginLimiter,
      RobinahsShopWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RobinahsShop.Supervisor)
  end

  def config_change(changed, _new, removed),
    do: RobinahsShopWeb.Endpoint.config_change(changed, removed)
end
