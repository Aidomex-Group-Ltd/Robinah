defmodule RobinahsShopWeb.Auth do
  import Plug.Conn
  import Phoenix.LiveView
  alias RobinahsShop.Accounts
  def init(action), do: action

  def call(conn, :fetch_current_user) do
    assign(conn, :current_user, current_user_for(get_session(conn, :staff_token)))
  end

  defp current_user_for(token) do
    case Accounts.public_access_user() do
      nil -> Accounts.user_for_token(token)
      user -> user
    end
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
    case current_user_for(session["staff_token"]) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Sign in with an authorised staff account.")
         |> redirect(to: "/staff/sign-in")}

      user ->
        socket = Phoenix.Component.assign(socket, :current_user, user)

        if Accounts.public_access_enabled?() do
          {:cont, socket}
        else
          token = session["staff_token"]

          socket =
            socket
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
end
