defmodule RobinahsShopWeb.SessionController do
  use RobinahsShopWeb, :controller
  alias RobinahsShop.Accounts

  def new(conn, _) do
    if conn.assigns.current_user do
      redirect(conn, to: "/staff/pos")
    else
      conn
      |> put_resp_header("cache-control", "no-store")
      |> render(:new, page_title: "Staff sign-in")
    end
  end

  def create(conn, params) do
    login = Map.get(params, "login", %{})

    case Accounts.authenticate(login["email"], login["password"]) do
      {:ok, user} ->
        token = Accounts.create_session(user)
        Plug.CSRFProtection.delete_csrf_token()

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:staff_token, token)
        |> put_session(:live_socket_id, "staff_sessions:#{Accounts.token_hash(token)}")
        |> redirect(to: if(user.role == :receiver, do: "/staff/receiving", else: "/staff/pos"))

      {:error, reason} ->
        message =
          if reason == :locked,
            do: "Too many attempts. Try again after 15 minutes.",
            else: "Email or password was not recognised."

        conn |> put_flash(:error, message) |> redirect(to: "/staff/sign-in")
    end
  end

  def delete(conn, _) do
    Accounts.revoke_session(get_session(conn, :staff_token))
    conn |> configure_session(renew: true) |> clear_session() |> redirect(to: "/")
  end
end

defmodule RobinahsShopWeb.SessionHTML do
  use RobinahsShopWeb, :html
  embed_templates "session_html/*"
end
