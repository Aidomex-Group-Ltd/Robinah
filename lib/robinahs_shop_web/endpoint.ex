defmodule RobinahsShopWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :robinahs_shop

  @session_options [
    store: :cookie,
    key: "_robinahs_shop",
    signing_salt: "staff-session-sign",
    encryption_salt: "staff-session-crypt",
    same_site: "Lax",
    http_only: true,
    max_age: 28_800,
    secure: Application.compile_env(:robinahs_shop, :secure_cookies, false)
  ]
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :robinahs_shop,
    gzip: true,
    only: RobinahsShopWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 1_000_000

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug RobinahsShopWeb.Router
end
