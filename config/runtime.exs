import Config

# ---------------------------------------------------------------------------
# Private .env loader.
#
# `scripts/init-env.sh` generates this gitignored file with openssl. Real
# process environment variables always win over the file, and a missing file
# is normal: Docker Compose passes the same names through `environment:`.
# ---------------------------------------------------------------------------
env_file = Path.join([__DIR__, "..", ".env"])

if File.regular?(env_file) do
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)

    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = String.trim(value)

          if key != "" and value != "" and is_nil(System.get_env(key)) do
            System.put_env(key, value)
          end

        _ ->
          :ok
      end
    end
  end)
end

read_env = fn name ->
  case System.get_env(name) do
    nil ->
      nil

    value ->
      trimmed = String.trim(value)
      if trimmed == "", do: nil, else: trimmed
  end
end

secret = read_env.("SECRET_BASE_KEY") || read_env.("SECRET_KEY_BASE")
signing_salt = read_env.("LIVE_SIGNING_SALT")
session_secret = read_env.("JWT_SECRET")
database_url = read_env.("DATABASE_URL")

if secret do
  if config_env() == :prod and byte_size(secret) < 64 do
    raise "SECRET_BASE_KEY must be at least 64 bytes"
  end

  config :robinahs_shop, RobinahsShopWeb.Endpoint, secret_key_base: secret
end

if signing_salt do
  config :robinahs_shop, RobinahsShopWeb.Endpoint, live_view: [signing_salt: signing_salt]
end

if session_secret do
  config :robinahs_shop, :session_hmac_secret, session_secret
end

# A full URL (postgresql://…) is parsed by Ecto. A bare name such as
# `robinah_db` is used as the PostgreSQL database name for local development;
# tests always stay on their own database.
if config_env() == :dev and database_url do
  if String.contains?(database_url, "://") do
    config :robinahs_shop, RobinahsShop.Repo, url: database_url
  else
    config :robinahs_shop, RobinahsShop.Repo, database: database_url
  end
end

if config_env() == :prod do
  if is_nil(secret) do
    raise "Set SECRET_BASE_KEY (or SECRET_KEY_BASE) with at least 64 bytes"
  end

  host = System.fetch_env!("PHX_HOST")

  if is_nil(database_url) or byte_size(database_url) < 3 do
    raise "DATABASE_URL must be set, for example postgresql://user:pass@host:5432/robinah_dev"
  end

  if String.contains?(database_url, "://") do
    config :robinahs_shop, RobinahsShop.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
      ssl: System.get_env("PG_SSL") in ["true", "1"]
  else
    config :robinahs_shop, RobinahsShop.Repo,
      database: database_url,
      username: System.get_env("POSTGRES_USER", "robinah"),
      password: System.get_env("POSTGRES_PASSWORD"),
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      port: String.to_integer(System.get_env("PGPORT", "5432")),
      pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
      ssl: System.get_env("PG_SSL") in ["true", "1"]
  end

  config :robinahs_shop, RobinahsShopWeb.Endpoint,
    server: System.get_env("PHX_SERVER") in ["true", "1"],
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    check_origin: ["https://#{host}"]
end
