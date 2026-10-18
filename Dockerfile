# Build and run on the same Linux/OTP base; the database is PostgreSQL.
ARG ELIXIR_IMAGE=elixir:1.19-slim
FROM ${ELIXIR_IMAGE} AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /build
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY lib lib
COPY priv priv
COPY assets assets
COPY config/runtime.exs config/runtime.exs
RUN mix compile && mix assets.deploy && mix release

FROM ${ELIXIR_IMAGE} AS runner
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl libstdc++6 openssl && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 shop && useradd --uid 10001 --gid shop --home-dir /app --no-create-home shop \
    && mkdir -p /app /data && chown -R shop:shop /app /data
WORKDIR /app
COPY --from=builder --chown=shop:shop /build/_build/prod/rel/robinahs_shop ./
COPY --chown=shop:shop scripts/docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
USER shop
ENV PHX_SERVER=true PORT=4000
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD curl -fsS http://127.0.0.1:4000/healthz || exit 1
ENTRYPOINT ["/app/entrypoint.sh"]
