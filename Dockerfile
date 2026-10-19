# Build and run on the same Linux/OTP base; the database is PostgreSQL.
# builder: the full Elixir image (already ships build-essential, git, ca-certificates)
# runner:  slim image with only the runtime essentials installed
# Pinned by digest so the build resolves base images locally without a registry lookup
ARG BUILDER_IMAGE=elixir@sha256:d170fadffd75b36146ff40b6e8d5cc881c59d136ae5a2c34a1b394ec33b6cffa # elixir:1.19.5
ARG RUNNER_IMAGE=elixir@sha256:5ac9237ec0de4af06336b31cb54e232c76f16bcda53dbd509f567a44f6d6e8af # elixir:1.19-slim
FROM ${BUILDER_IMAGE} AS builder
WORKDIR /build
ENV MIX_ENV=prod
# hex + rebar ship preinstalled in the full elixir image; avoid re-downloading them
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY lib lib
COPY priv priv
COPY assets assets
COPY config/runtime.exs config/runtime.exs
RUN mix compile && mix assets.deploy && mix release

FROM ${RUNNER_IMAGE} AS runner
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
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD curl -fsS "http://127.0.0.1:${PORT:-4000}/healthz" || exit 1
ENTRYPOINT ["/app/entrypoint.sh"]
