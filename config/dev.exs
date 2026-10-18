import Config

config :robinahs_shop, RobinahsShop.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: System.get_env("PGDATABASE", "robinah_dev"),
  pool_size: 10

config :robinahs_shop, RobinahsShopWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  secret_key_base: String.duplicate("development-only-replace-in-production-", 3),
  debug_errors: true,
  check_origin: false

config :robinahs_shop, :secure_cookies, false
