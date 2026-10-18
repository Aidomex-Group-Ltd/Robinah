defmodule RobinahsShopWeb.Auth do
  import Plug.Conn
  import Phoenix.LiveView
  alias RobinahsShop.Accounts
  def init(action), do: action

  def call(conn, :fetch_current_user) do
    assign(conn, :current_user, Accounts.user_for_token(get_session(conn, :staff_token)))
  end

  defp guard_session(socket, token) do
    if Accounts.user_for_token(token) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Your session has ended. Please sign in again.")
       |> redirect(to: "/staff/sign-in")}
    end
  end

  def on_mount(:require_staff, _params, session, socket) do
    case Accounts.user_for_token(session["staff_token"]) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Sign in with an authorised staff account.")
         |> redirect(to: "/staff/sign-in")}

      user ->
        token = session["staff_token"]

        socket =
          socket
          |> Phoenix.Component.assign(:current_user, user)
          |> attach_hook(:session_guard, :handle_event, fn _, _, sock ->
            guard_session(sock, token)
          end)
          |> attach_hook(:session_guard, :handle_params, fn _, _, sock ->
            guard_session(sock, token)
          end)
          |> attach_hook(:session_guard, :handle_info, fn _, sock ->
            guard_session(sock, token)
          end)

        {:cont, socket}
    end
  end
end
