import Config

config :robinahs_shop, RobinahsShopWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto], exclude: ["localhost", "127.0.0.1"]]

config :robinahs_shop, :secure_cookies, true
config :logger, level: :info
