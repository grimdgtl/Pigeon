# lib/keila/auth/reset_token.ex
defmodule Keila.Auth.ResetToken do
  @salt "password-reset"
  @max_age 60 * 60 * 2 # 2h

  def sign(user_id) do
    Phoenix.Token.sign(KeilaWeb.Endpoint, @salt, user_id)
  end

  def verify(token) do
    Phoenix.Token.verify(KeilaWeb.Endpoint, @salt, token, max_age: @max_age)
  end
end