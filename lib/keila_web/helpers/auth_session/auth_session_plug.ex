defmodule KeilaWeb.AuthSession.Plug do
  alias Keila.Accounts
  alias Keila.Auth
  alias Keila.RBAC
  import Plug.Conn

  @spec init(any) :: list()
  def init(_), do: []

  @spec call(Plug.Conn.t(), any) :: Plug.Conn.t()
  def call(conn, _) do
    with session_token when is_binary(session_token) <- get_session(conn, :token),
         token = %Auth.Token{} <- Auth.find_token(session_token, "web.session"),
         user = %Auth.User{} <- Auth.get_user(token.user_id),
         account <- Accounts.get_user_account(user.id) do
      # Use RBAC system to determine if user is a super admin
      current_user_is_super_admin = RBAC.is_super_admin?(user.id)
      
      # Check if user is a tenant admin (has admin role in their current account)
      current_user_is_tenant_admin = case RBAC.get_user_role_in_account(user.id, account.id) do
        {:ok, "admin"} -> true
        _ -> false
      end

      conn
      |> assign(:current_user, user)
      |> assign(:current_account, account)
      |> assign(:current_user_is_super_admin, current_user_is_super_admin)
      |> assign(:current_user_is_tenant_admin, current_user_is_tenant_admin)
      |> assign(:is_admin?, current_user_is_super_admin)
    else
      _ ->
        conn
      |> assign(:current_user, nil)
      |> assign(:current_account, nil)
      |> assign(:current_user_is_super_admin, false)
      |> assign(:current_user_is_tenant_admin, false)
      |> assign(:is_admin?, false)
    end
  end
end
