defmodule Keila.RBACDemo do
  @moduledoc """
  Demonstration script for the Keila RBAC (Role-Based Access Control) system.

  This module provides examples of how to use the RBAC system to manage
  multi-tenant user permissions and role-based access control.

  ## Usage

  ```elixir
  # Run the demo to see the RBAC system in action
  Keila.RBACDemo.run_demo()
  ```

  ## Features Demonstrated

  1. **Role-based permissions**: Different roles have different permission sets
  2. **Multi-tenant isolation**: Users can only access their own tenant's resources
  3. **Super admin access**: Super admins can access all tenants
  4. **Feature flags**: JSON permissions for frontend consumption
  5. **Account management**: Listing users and their roles within accounts
  """

  alias Keila.{RBAC, Auth, Accounts, Repo}
  import Ecto.Query

  @doc """
  Runs a comprehensive demonstration of the RBAC system.
  """
  def run_demo() do
    IO.puts("🚀 Keila RBAC System Demonstration")
    IO.puts("=" |> String.duplicate(50))
    IO.puts()

    # 1. Show role permissions
    demonstrate_role_permissions()
    IO.puts()

    # 2. Show multi-tenant setup verification
    demonstrate_multi_tenant_verification()
    IO.puts()

    # 3. Show user permission checking
    demonstrate_user_permissions()
    IO.puts()

    # 4. Show account access control
    demonstrate_account_access()
    IO.puts()

    IO.puts("✅ RBAC Demonstration Complete!")
  end

  defp demonstrate_role_permissions() do
    IO.puts("📋 Role-Based Permissions")
    IO.puts("-" |> String.duplicate(30))

    roles = [:super_admin, :admin, :editor, :viewer]

    for role <- roles do
      permissions = RBAC.get_role_permissions(role)
      IO.puts("#{role}:")
      IO.puts("  • Manage Users: #{permissions.can_manage_users}")
      IO.puts("  • Edit Projects: #{permissions.can_edit_projects}")
      IO.puts("  • View Reports: #{permissions.can_view_reports}")
      IO.puts("  • Manage Billing: #{permissions.can_manage_billing}")
      IO.puts()
    end
  end

  defp demonstrate_multi_tenant_verification() do
    IO.puts("🏢 Multi-Tenant Setup Verification")
    IO.puts("-" |> String.duplicate(35))

    case RBAC.verify_multi_tenant_setup() do
      {:ok, verification_results} ->
        IO.puts("✅ Multi-tenant setup is correct!")
        IO.puts()
        
        IO.puts("Tenants:")
        for tenant <- verification_results.tenants do
          IO.puts("  • #{tenant.name} (#{tenant.user_count} users)")
        end
        IO.puts()
        
        IO.puts("Users:")
        for user <- verification_results.users do
          status = if user.activated, do: "✅", else: "❌"
          IO.puts("  #{status} #{user.email}")
        end
        IO.puts()
        
        IO.puts("Role Permissions:")
        for role_perm <- verification_results.role_permissions do
          IO.puts("  • #{role_perm.role}: #{inspect(role_perm.permissions)}")
        end

      {:error, issues} ->
        IO.puts("❌ Multi-tenant setup has issues:")
        for issue <- issues do
          IO.puts("  • #{issue}")
        end
    end
  end

  defp demonstrate_user_permissions() do
    IO.puts("👤 User Permission Checking")
    IO.puts("-" |> String.duplicate(30))

    # Try to find a super admin user
    case find_super_admin_user() do
      nil ->
        IO.puts("No super admin user found. Run seeds first:")
        IO.puts("  mix run priv/repo/seeds.exs")
      user ->
        IO.puts("Found super admin: #{user.email}")
        
        # Get their permissions in their account
        case Accounts.get_user_account(user.id) do
          nil ->
            IO.puts("User has no account assigned")
          account ->
            permissions = RBAC.get_user_permissions(user.id, account.id)
            IO.puts("Permissions in account:")
            IO.puts("  • Manage Users: #{permissions.can_manage_users}")
            IO.puts("  • Edit Projects: #{permissions.can_edit_projects}")
            IO.puts("  • View Reports: #{permissions.can_view_reports}")
            IO.puts("  • Manage Billing: #{permissions.can_manage_billing}")
        end
    end
  end

  defp demonstrate_account_access() do
    IO.puts("🔐 Account Access Control")
    IO.puts("-" |> String.duplicate(30))

    # List all accounts
    accounts = Repo.all(Accounts.Account)
    IO.puts("Available accounts: #{length(accounts)}")
    
    for account <- accounts do
      account_name = get_account_name(account)
      users_with_roles = RBAC.list_account_users_with_roles(account.id)
      
      IO.puts("  • #{account_name} (#{length(users_with_roles)} users)")
      
      for {user, role} <- users_with_roles do
        IO.puts("    - #{user.email} (#{role})")
      end
    end
  end

  # Helper functions

  defp find_super_admin_user() do
    query = from u in Auth.User,
      join: ug in Auth.UserGroup, on: ug.user_id == u.id,
      join: ugr in Auth.UserGroupRole, on: ugr.user_group_id == ug.id,
      join: r in Auth.Role, on: r.id == ugr.role_id,
      where: r.name == "super_admin",
      select: u,
      limit: 1

    Repo.one(query)
  end

  defp get_account_name(account) do
    Repo.one(
      from g in Auth.Group,
        where: g.id == ^account.group_id,
        select: g.name
    ) || "Unnamed Account"
  end

  @doc """
  Creates a simple test scenario to demonstrate RBAC functionality.
  """
  def create_test_scenario() do
    IO.puts("🧪 Creating Test Scenario...")
    
    # Create root group
    _root_group = Repo.insert!(%Auth.Group{name: "root", parent_id: nil})
    
    # Create test account
    {:ok, account} = Accounts.create_account()
    {:ok, _group} = Auth.update_group(account.group_id, %{name: "Test Company"})
    
    # Create test users
    {:ok, admin_user} = Auth.create_user(%{email: "admin@test.com", password: "password123"}, 
      url_fn: & &1, skip_activation_email: true)
    {:ok, _} = Auth.activate_user(admin_user.id)
    
    {:ok, editor_user} = Auth.create_user(%{email: "editor@test.com", password: "password123"}, 
      url_fn: & &1, skip_activation_email: true)
    {:ok, _} = Auth.activate_user(editor_user.id)
    
    # Assign users to account
    :ok = Accounts.set_user_account(admin_user.id, account.id)
    :ok = Accounts.set_user_account(editor_user.id, account.id)
    
    # Create roles
    {:ok, admin_role} = Auth.create_role(%{name: "admin"})
    {:ok, editor_role} = Auth.create_role(%{name: "editor"})
    
    # Assign roles
    :ok = Auth.assign_role_to_user(admin_user.id, %{account_id: account.id, role_id: admin_role.id})
    :ok = Auth.assign_role_to_user(editor_user.id, %{account_id: account.id, role_id: editor_role.id})
    
    IO.puts("✅ Test scenario created!")
    IO.puts("  • Account: Test Company")
    IO.puts("  • Admin: admin@test.com")
    IO.puts("  • Editor: editor@test.com")
    
    %{
      account: account,
      admin_user: admin_user,
      editor_user: editor_user,
      admin_role: admin_role,
      editor_role: editor_role
    }
  end

  @doc """
  Demonstrates the test scenario.
  """
  def demonstrate_test_scenario() do
    scenario = create_test_scenario()
    
    IO.puts()
    IO.puts("🔍 Testing Permissions...")
    
    # Test admin permissions
    admin_perms = RBAC.get_user_permissions(scenario.admin_user.id, scenario.account.id)
    IO.puts("Admin permissions:")
    IO.puts("  • Manage Users: #{admin_perms.can_manage_users}")
    IO.puts("  • Edit Projects: #{admin_perms.can_edit_projects}")
    IO.puts("  • View Reports: #{admin_perms.can_view_reports}")
    IO.puts("  • Manage Billing: #{admin_perms.can_manage_billing}")
    
    # Test editor permissions
    editor_perms = RBAC.get_user_permissions(scenario.editor_user.id, scenario.account.id)
    IO.puts("Editor permissions:")
    IO.puts("  • Manage Users: #{editor_perms.can_manage_users}")
    IO.puts("  • Edit Projects: #{editor_perms.can_edit_projects}")
    IO.puts("  • View Reports: #{editor_perms.can_view_reports}")
    IO.puts("  • Manage Billing: #{editor_perms.can_manage_billing}")
    
    # Test account access
    IO.puts()
    IO.puts("🔐 Account Access:")
    admin_accessible = RBAC.list_user_accessible_accounts(scenario.admin_user.id)
    editor_accessible = RBAC.list_user_accessible_accounts(scenario.editor_user.id)
    
    IO.puts("Admin can access #{length(admin_accessible)} account(s)")
    IO.puts("Editor can access #{length(editor_accessible)} account(s)")
    
    # Test role detection
    IO.puts()
    IO.puts("🎭 Role Detection:")
    case RBAC.get_user_role_in_account(scenario.admin_user.id, scenario.account.id) do
      {:ok, role} -> IO.puts("Admin user has role: #{role}")
      {:error, reason} -> IO.puts("Admin user role error: #{reason}")
    end
    
    case RBAC.get_user_role_in_account(scenario.editor_user.id, scenario.account.id) do
      {:ok, role} -> IO.puts("Editor user has role: #{role}")
      {:error, reason} -> IO.puts("Editor user role error: #{reason}")
    end
  end
end
