defmodule KeilaWeb.TenantAdminControllerTest do
  use KeilaWeb.ConnCase, async: true
  alias Keila.Auth
  alias Keila.Auth.Invites
  alias Keila.Projects
  alias Keila.Accounts

  setup do
    # Create a super admin user
    super_admin = Auth.create_user!(%{email: "superadmin@example.com", password: "password123"})
    
    # Create a regular admin user
    account = Accounts.create_account!("Test Account")
    project = Projects.create_project!(%{"name" => "Test Project", "account_id" => account.id})
    regular_admin = Auth.create_user!(%{email: "admin@example.com", password: "password123"})
    Auth.assign_role_to_user(regular_admin.id, project.group_id, "admin")

    %{super_admin: super_admin, regular_admin: regular_admin, project: project}
  end

  describe "GET /admin/tenants/new" do
    test "allows super admin to access new tenant form", %{conn: conn, super_admin: super_admin} do
      conn = log_in_user(conn, super_admin)
      conn = assign(conn, :current_user_is_super_admin, true)
      
      conn = get(conn, Routes.tenant_admin_path(conn, :new))
      assert html_response(conn, 200) =~ "Create New Tenant"
    end

    test "denies access to regular admin", %{conn: conn, regular_admin: regular_admin} do
      conn = log_in_user(conn, regular_admin)
      conn = assign(conn, :current_user_is_super_admin, false)
      
      conn = get(conn, Routes.tenant_admin_path(conn, :new))
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "Access denied"
    end
  end

  describe "POST /admin/tenants" do
    test "creates a new tenant with admin user", %{conn: conn, super_admin: super_admin} do
      conn = log_in_user(conn, super_admin)
      conn = assign(conn, :current_user_is_super_admin, true)
      
      tenant_params = %{"name" => "New Tenant"}
      
      conn = post(conn, Routes.tenant_admin_path(conn, :create), tenant: tenant_params)
      
      # Should redirect to the tenant show page
      assert redirected_to(conn) =~ "/admin/tenants/"
      assert get_flash(conn, :info) =~ "Tenant 'New Tenant' created successfully"
    end

    test "denies access to regular admin", %{conn: conn, regular_admin: regular_admin} do
      conn = log_in_user(conn, regular_admin)
      conn = assign(conn, :current_user_is_super_admin, false)
      
      tenant_params = %{"name" => "New Tenant"}
      
      conn = post(conn, Routes.tenant_admin_path(conn, :create), tenant: tenant_params)
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "Access denied"
    end
  end

  describe "POST /admin/tenants/:project_id/admins" do
    test "creates an admin user for existing tenant", %{conn: conn, super_admin: super_admin, project: project} do
      conn = log_in_user(conn, super_admin)
      conn = assign(conn, :current_user_is_super_admin, true)
      
      user_params = %{
        "email" => "newadmin@example.com",
        "password" => "password123",
        "password_confirmation" => "password123"
      }
      
      conn = post(conn, Routes.tenant_admin_path(conn, :create_admin, project.id), user: user_params)
      
      assert redirected_to(conn) =~ "/admin/tenants/#{project.id}"
      assert get_flash(conn, :info) =~ "Admin user 'newadmin@example.com' created successfully"
    end
  end

  describe "POST /admin/tenants/:project_id/invites" do
    test "sends an admin invite", %{conn: conn, super_admin: super_admin, project: project} do
      conn = log_in_user(conn, super_admin)
      conn = assign(conn, :current_user_is_super_admin, true)
      
      invite_params = %{
        "email" => "invited@example.com",
        "role" => "admin"
      }
      
      conn = post(conn, Routes.tenant_admin_path(conn, :send_invite, project.id), invite: invite_params)
      
      assert redirected_to(conn) =~ "/admin/tenants/#{project.id}"
      assert get_flash(conn, :info) =~ "Invite sent to 'invited@example.com'"
    end
  end

  describe "DELETE /admin/invites/:token" do
    test "revokes an invite", %{conn: conn, super_admin: super_admin, project: project} do
      conn = log_in_user(conn, super_admin)
      conn = assign(conn, :current_user_is_super_admin, true)
      
      # Create an invite
      invite_attrs = %{
        "email" => "user@example.com",
        "project_id" => project.id,
        "created_by_user_id" => super_admin.id
      }
      
      invite = Invites.create_invite!(invite_attrs)
      
      conn = delete(conn, Routes.tenant_admin_path(conn, :revoke_invite, invite.token))
      
      assert redirected_to(conn) =~ "/admin/tenants"
      assert get_flash(conn, :info) =~ "Invite revoked successfully"
    end
  end

  defp log_in_user(conn, user) do
    # Mock the session token
    token = "test_token_#{user.id}"
    conn = put_session(conn, :token, token)
    conn
  end
end
