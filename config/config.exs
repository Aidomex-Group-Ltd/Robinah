import Config
config :robinahs_shop, ecto_repos: [RobinahsShop.Repo]

config :robinahs_shop, RobinahsShopWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RobinahsShopWeb.ErrorHTML, json: RobinahsShopWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RobinahsShop.PubSub,
  live_view: [signing_salt: "robinahs-live-view"]

config :phoenix_live_view, :colocated_assets, disable_symlink_warning: true
config :phoenix, :json_library, Jason
config :logger, :console, format: "$time $metadata[$level] $message\n", metadata: [:request_id]
config :phoenix, :filter_parameters, ["password", "password_confirmation", "token"]
import_config "#{config_env()}.exs"
