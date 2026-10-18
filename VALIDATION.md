# Validation — 18 October 2026

Verified against the delivered source:

- Hex dependencies resolved successfully and are pinned in `mix.lock` (Phoenix 1.8.15, LiveView 1.2.12, Ecto SQLite3 0.25.0).
- `mix compile --warnings-as-errors` completed successfully.
- `mix format` completed successfully.
- `mix assets.deploy` completed successfully, copying version-matched browser clients and fingerprinting assets.
- `mix test`: **17 tests, 0 failures**, including public LiveView search/enquiries, staff receiving-to-sale flow, price validation, rollback on insufficient stock, duplicate request handling, role checks, session expiry/revocation, reporting dates and protected HTTP routes.
- JavaScript entry point passed `node --check`.
- All four deployment shell scripts passed `bash -n` and use Linux line endings.
- Both Compose files parsed successfully together with `docker compose --env-file .env.example -f compose.yml -f compose.edge.yml config --quiet`.
- The referenced `elixir:1.19-slim` and `caddy:2-alpine` image tags were verified against Docker Hub manifests, including amd64 and arm64 support.
- The eight included images are recorded with original URLs and SHA-256 checksums in `reference/image-sources.json`.

## Verification limits

The Linux Docker image build and an actual VPS deployment were not run: no Docker daemon is available in this environment. Run the supplied deployment on the intended Linux VPS and check `/healthz` and container logs. A live browser visual comparison was not completed because browser automation timed out; the server-side LiveView interaction tests passed.

Tests ran with Elixir 1.19.5 and Erlang/OTP 28. The installed Windows runtime needed temporary, workspace-local launcher and filesystem compatibility workarounds to run the tooling. Those workarounds are not part of this project; no global runtime settings were modified. The deployment is intended for Linux and builds its release inside Docker.

Original private server code and database records were not accessible. This is a new Phoenix implementation of the recovered public app, with a fresh database. It cannot certify behaviour or data hidden in the inaccessible original backend.
