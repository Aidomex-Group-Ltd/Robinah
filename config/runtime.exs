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

# `SECRET_BASE_KEY` takes precedence over `SECRET_KEY_BASE` when both are set;
# `secret_name` names the variable that actually provided the value so the
# boot-time error points at the right setting.
secret_name =
  if read_env.("SECRET_BASE_KEY") != nil, do: "SECRET_BASE_KEY", else: "SECRET_KEY_BASE"

secret = read_env.("SECRET_BASE_KEY") || read_env.("SECRET_KEY_BASE")
signing_salt = read_env.("LIVE_SIGNING_SALT")
session_secret = read_env.("JWT_SECRET")
database_url = read_env.("DATABASE_URL")

if secret do
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
  # Render sets RENDER_EXTERNAL_HOSTNAME for every web service, so the shop
  # boots even when PHX_HOST is left unset. PHX_HOST still wins when present,
  # but it must be a bare hostname — values like `true`, `false`, or a full
  # https:// URL were once entered by hand and silently broke LiveView's
  # origin check (every browser websocket was rejected with 403).
  normalize_host = fn value ->
    value
    |> String.trim()
    |> String.replace(~r|^https?://|, "")
    |> String.split("/")
    |> List.first()
    |> String.split(":")
    |> List.first()
  end

  phx_host = read_env.("PHX_HOST")

  external_host =
    phx_host || read_env.("RENDER_EXTERNAL_HOSTNAME") ||
      case read_env.("RENDER_EXTERNAL_URL") do
        nil -> nil
        url -> URI.parse(url).host
      end

  host =
    case external_host do
      nil ->
        "localhost"

      value ->
        normalize_host.(value)
    end

  # A valid host is a dotted DNS name ( robinah.onrender.com ). Render's own
  # hostname always matches; `true`/`false`/scheme-only values never do.
  valid_host? = fn host ->
    Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/i, host)
  end

  if phx_host != nil and not valid_host?.(host) do
    raise """
    PHX_HOST is set to an invalid value: #{inspect(phx_host)}.

    PHX_HOST must be the bare public hostname (no https://, no port, no
    path), for example: robinah.onrender.com

    Invalid values such as "true", "false", or a full URL break LiveView:
    the websocket origin check would reject every browser connection.
    On Render, delete PHX_HOST from the service's Environment tab — the
    release then falls back to RENDER_EXTERNAL_HOSTNAME, which Render
    injects automatically and which is always correct.
    """
  end

  if external_host != nil and not valid_host?.(host) do
    raise """
    The public hostname resolved to #{inspect(host)} (from #{if phx_host, do: "PHX_HOST", else: "RENDER_EXTERNAL_HOSTNAME/RENDER_EXTERNAL_URL"}), \
    which is not a valid DNS name. Fix the setting in Render → service → Environment.
    """
  end

  add_problem = fn problems, problem?, message ->
    if problem?, do: problems ++ [message], else: problems
  end

  # Resolved up front so a missing secret never reaches byte_size/1.
  secret_problem =
    cond do
      is_nil(secret) ->
        "#{secret_name} is not set. Generate one locally with: openssl rand -hex 64"

      byte_size(secret) < 64 ->
        "#{secret_name} must be at least 64 bytes (it is #{byte_size(secret)}). " <>
          "Replace it with the output of: openssl rand -hex 64"

      true ->
        nil
    end

  problems =
    []
    |> add_problem.(
      is_nil(database_url),
      "DATABASE_URL is not set. Link the Render Postgres instance (Environment → Add from database) or paste its connection string."
    )
    |> add_problem.(
      database_url != nil and not String.starts_with?(database_url, "postgres://") and
        not String.starts_with?(database_url, "postgresql://"),
      "DATABASE_URL must be a complete postgresql://user:password@host:5432/database URL. " <>
        "In Render use the linked database's Internal Database URL (render.yaml wires it with fromDatabase connectionString)."
    )
    |> then(fn problems ->
      if secret_problem, do: problems ++ [secret_problem], else: problems
    end)
    |> add_problem.(
      is_nil(session_secret),
      "JWT_SECRET is not set. Generate one with: openssl rand -hex 32 " <>
        "(Render's blueprint generates it automatically)."
    )
    |> add_problem.(
      is_nil(signing_salt),
      "LIVE_SIGNING_SALT is not set. Generate one with: openssl rand -hex 16 " <>
        "(Render's blueprint generates it automatically)."
    )

  if problems != [] do
    raise """
    Cannot start Robinah's Shop. Fix these settings in Render → service → Environment:

    #{Enum.map_join(problems, "\n", &("  - " <> &1))}

    Required: DATABASE_URL, SECRET_KEY_BASE (or SECRET_BASE_KEY), JWT_SECRET,
    LIVE_SIGNING_SALT, ADMIN_EMAIL, ADMIN_PASSWORD.
    Optional: PHX_HOST (defaults to RENDER_EXTERNAL_HOSTNAME), PORT, POOL_SIZE,
    ERL_FLAGS.
    """
  end

  # libpq sslmode semantics. Render's blueprint supplies the private-network
  # URL (no sslmode) which needs no TLS; the external URL requires
  # `sslmode=require`, which encrypts without verifying the certificate.
  # `verify-ca`/`verify-full` validate the chain against the OS CA store.
  repo_ssl =
    cond do
      String.contains?(database_url, "sslmode=verify") -> true
      String.contains?(database_url, "sslmode=disable") -> false
      String.contains?(database_url, "sslmode=require") -> [verify: :verify_none]
      System.get_env("PG_SSL") in ["true", "1"] -> [verify: :verify_none]
      true -> false
    end

  # Production always connects with the complete URL validated above, so the
  # service and the database only need to share Render's private network
  # (same region) for the internal hostname to resolve.
  config :robinahs_shop, RobinahsShop.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    ssl: repo_ssl

  config :robinahs_shop, RobinahsShopWeb.Endpoint,
    server: System.get_env("PHX_SERVER") in ["true", "1"],
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    check_origin: ["https://#{host}"]
end
