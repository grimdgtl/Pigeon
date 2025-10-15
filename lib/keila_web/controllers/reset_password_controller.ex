# lib/keila_web/controllers/reset_password_controller.ex
defmodule KeilaWeb.ResetPasswordController do
  use KeilaWeb, :controller
  alias Keila.Auth
  alias Keila.Auth.ResetToken

  def verify(conn, %{"token" => token}) do
    case ResetToken.verify(token) do
      {:ok, _user_id} -> json(conn, %{valid: true})
      _ -> json(conn, %{valid: false})
    end
  end

  def update(conn, %{"token" => token, "password" => pass}) do
    with {:ok, user_id} <- ResetToken.verify(token),
         :ok <- Auth.reset_password(user_id, pass) do
      json(conn, %{status: "ok"})
    else
      _ -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_token_or_password"})
    end
  end
end