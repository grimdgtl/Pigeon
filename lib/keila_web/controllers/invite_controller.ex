defmodule KeilaWeb.InviteController do
  use KeilaWeb, :controller
  alias Keila.Auth.Invites

  def show(conn, %{"token" => token}) do
    case Invites.validate_invite_token(token) do
      {:ok, invite} ->
        render(conn, "show.html", invite: invite, token: token)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid invitation link")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, :already_used} ->
        conn
        |> put_flash(:error, "This invitation has already been used")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, :expired} ->
        conn
        |> put_flash(:error, "This invitation has expired")
        |> redirect(to: Routes.auth_path(conn, :login))
    end
  end

  def accept(conn, %{"token" => token, "user" => user_params}) do
    case Invites.accept_invite!(token, user_params) do
      {:ok, _user, _invite} ->
        conn
        |> put_flash(:info, "Welcome to Keila! Your account has been created successfully.")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid invitation link")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, :already_used} ->
        conn
        |> put_flash(:error, "This invitation has already been used")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, :expired} ->
        conn
        |> put_flash(:error, "This invitation has expired")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to accept invitation: #{inspect(reason)}")
        |> redirect(to: Routes.invite_path(conn, :show, token))
    end
  end
end
