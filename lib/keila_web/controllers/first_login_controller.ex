defmodule KeilaWeb.FirstLoginController do
  use KeilaWeb, :controller

  alias Keila.Auth
  alias Keila.Auth.User

  def show(conn, %{"token" => token}) do
    case Auth.validate_first_login_token(token) do
      {:ok, user} ->
        changeset = User.update_password_changeset(user, %{})
        render(conn, "show.html", user: user, changeset: changeset, token: token)
      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid or expired password setup link.")
        |> redirect(to: Routes.auth_path(conn, :login))
    end
  end

  def set(conn, %{"token" => token, "user" => user_params}) do
    case Auth.consume_first_login_token(token, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password set successfully! You can now log in.")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_flash(:error, "Invalid or expired password setup link.")
        |> redirect(to: Routes.auth_path(conn, :login))

      {:error, changeset} ->
        case Auth.validate_first_login_token(token) do
          {:ok, user} ->
            conn
            |> put_flash(:error, "Failed to set password. Please check the errors below.")
            |> render("show.html", user: user, changeset: changeset, token: token)
          {:error, _} ->
            conn
            |> put_flash(:error, "Invalid or expired password setup link.")
            |> redirect(to: Routes.auth_path(conn, :login))
        end
    end
  end
end
