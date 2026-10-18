import Config

config :robinahs_shop, RobinahsShop.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: System.get_env("PGDATABASE_TEST", "robinah_shop_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

config :robinahs_shop, RobinahsShopWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("test-only-", 8)

config :logger, level: :warning
config :robinahs_shop, :password_iterations, 1_000
config :robinahs_shop, :secure_cookies, false
