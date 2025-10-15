defmodule KeilaWeb.TenantAdminController.Plug.RequireSuperAdmin do
  @moduledoc """
  Plug that requires the current user to be a super admin.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user_is_super_admin] do
      conn
    else
      conn
      |> put_flash(:error, "Access denied. Super admin privileges required.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
