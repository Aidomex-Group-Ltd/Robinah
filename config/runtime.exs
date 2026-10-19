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

# libpq `sslmode` semantics, translated into the `:ssl` option Postgrex
# understands — Ecto copies an unknown `sslmode=require` query parameter
# through as a plain option and Postgrex never reads it, so without this
# translation a TLS-only server would be contacted in the clear. This runs in
# every environment, because `DATABASE_URL` may point at a TLS-only server in
# development too.
#   no sslmode      → plain TCP (Render's internal/private-network URL)
#   sslmode=require → TLS, encrypts without verifying the certificate
#   sslmode=verify-*→ TLS against the OS CA store, including hostname check
repo_ssl =
  cond do
    is_nil(database_url) ->
      false

    String.contains?(database_url, "sslmode=verify") ->
      true

    String.contains?(database_url, "sslmode=disable") ->
      false

    String.contains?(database_url, "sslmode=require") ->
      [verify: :verify_none]

    System.get_env("PG_SSL") in ["true", "1"] ->
      [verify: :verify_none]

    true ->
      false
  end

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
    config :robinahs_shop, RobinahsShop.Repo, url: database_url, ssl: repo_ssl
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

  # A URL Ecto can parse: postgres scheme, a host and a database name. Ecto
  # itself raises `Ecto.InvalidURLError` only after boot has started, so the
  # same shape is checked here to produce one readable message.
  database_shape_ok? =
    not is_nil(database_url) and
      (String.starts_with?(database_url, "postgres://") or
         String.starts_with?(database_url, "postgresql://")) and
      case URI.parse(database_url) do
        %URI{host: db_host, path: db_path} ->
          is_binary(db_host) and db_host != "" and is_binary(db_path) and db_path not in ["", "/"]

        _ ->
          false
      end

  # POOL_SIZE and PORT used to reach String.to_integer/1 with whatever was in
  # the Environment tab; an empty or non-numeric value crashed with a bare
  # FunctionClauseError. Parse both once and report the offending value.
  parse_positive_int = fn name, default ->
    raw = System.get_env(name, default) |> String.trim()

    case Integer.parse(raw) do
      {int, ""} when int > 0 ->
        {int, nil}

      _ ->
        {String.to_integer(default),
         "#{name} must be a positive integer (it is #{inspect(raw)})."}
    end
  end

  {pool_size, pool_problem} = parse_positive_int.("POOL_SIZE", "10")
  {http_port, port_problem} = parse_positive_int.("PORT", "4000")

  problems =
    []
    |> add_problem.(
      is_nil(database_url),
      "DATABASE_URL is not set. Set it in Environment → Add from database (Render's " <>
        "internal URL) or paste the complete URL of your PostgreSQL server."
    )
    |> add_problem.(
      database_url != nil and not database_shape_ok?,
      "DATABASE_URL must be a complete postgresql://user:password@host:5432/database URL. " <>
        "A server outside Render (for example an Aiven instance) needs ?sslmode=require; " <>
        "a Render internal URL is postgresql://user:pass@host.render.internal:5432/database " <>
        "and only resolves when the database is in the same region as this service."
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
    |> add_problem.(pool_problem != nil, pool_problem)
    |> add_problem.(port_problem != nil, port_problem)

  if problems != [] do
    raise """
    Cannot start Robinah's Shop. Fix these settings in Render → service → Environment:

    #{Enum.map_join(problems, "\n", &("  - " <> &1))}

    Required: DATABASE_URL, SECRET_KEY_BASE (or SECRET_BASE_KEY), JWT_SECRET,
    LIVE_SIGNING_SALT. On a database without an owner yet: ADMIN_EMAIL,
    ADMIN_PASSWORD (checked by the release before the account is created).
    Optional: PHX_HOST (defaults to RENDER_EXTERNAL_HOSTNAME), PORT, POOL_SIZE,
    ERL_FLAGS.
    """
  end

  # Production always connects with the complete URL validated above: an
  # external server over the internet (sslmode=require) or a Render internal
  # URL, which only resolves when the database is in the same region as this
  # service.
  config :robinahs_shop, RobinahsShop.Repo,
    url: database_url,
    pool_size: pool_size,
    ssl: repo_ssl

  config :robinahs_shop, RobinahsShopWeb.Endpoint,
    server: System.get_env("PHX_SERVER") in ["true", "1"],
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0}, port: http_port],
    check_origin: ["https://#{host}"]
end
