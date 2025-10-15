defmodule Keila.RBACSimpleTest do
  use Keila.DataCase, async: false
  alias Keila.{RBAC, Auth, Accounts, Repo}
  import Ecto.Query

  @tag :rbac_simple
  describe "RBAC module basic functionality" do
    setup do
      # Create root group that's required for account creation
      root_group = Repo.insert!(%Auth.Group{name: "root", parent_id: nil})
      %{root_group: root_group}
    end

    test "role permissions are correctly defined" do
      # Test super_admin permissions
      super_admin_perms = RBAC.get_role_permissions(:super_admin)
      assert super_admin_perms.can_manage_users == true
      assert super_admin_perms.can_edit_projects == true
      assert super_admin_perms.can_view_reports == true
      assert super_admin_perms.can_manage_billing == true
      
      # Test admin permissions
      admin_perms = RBAC.get_role_permissions(:admin)
      assert admin_perms.can_manage_users == false
      assert admin_perms.can_edit_projects == true
      assert admin_perms.can_view_reports == true
      assert admin_perms.can_manage_billing == true
      
      # Test editor permissions
      editor_perms = RBAC.get_role_permissions(:editor)
      assert editor_perms.can_manage_users == false
      assert editor_perms.can_edit_projects == true
      assert editor_perms.can_view_reports == true
      assert editor_perms.can_manage_billing == false
      
      # Test viewer permissions
      viewer_perms = RBAC.get_role_permissions(:viewer)
      assert viewer_perms.can_manage_users == false
      assert viewer_perms.can_edit_projects == false
      assert viewer_perms.can_view_reports == true
      assert viewer_perms.can_manage_billing == false
    end

    test "user without role has no permissions" do
      # Create a test user and account
      {:ok, user} = Auth.create_user(%{email: "test@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign user to account
      :ok = Accounts.set_user_account(user.id, account.id)
      
      # User should have no permissions
      permissions = RBAC.get_user_permissions(user.id, account.id)
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == false
      assert permissions.can_view_reports == false
      assert permissions.can_manage_billing == false
      
      # User should not be detected as super admin
      assert RBAC.is_super_admin?(user.id) == false
      
      # User should only be able to access their own account
      accessible_accounts = RBAC.list_user_accessible_accounts(user.id)
      assert length(accessible_accounts) == 1
      assert hd(accessible_accounts).id == account.id
    end

    test "user with super_admin role has all permissions" do
      # Create test data
      {:ok, user} = Auth.create_user(%{email: "super@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign user to account
      :ok = Accounts.set_user_account(user.id, account.id)
      
      # Create super_admin role
      {:ok, role} = Auth.create_role(%{name: "super_admin"})
      
      # Assign role to user
      :ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
      
      # User should have super admin permissions
      permissions = RBAC.get_user_permissions(user.id, account.id)
      assert permissions.can_manage_users == true
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == true
      
      # User should be detected as super admin
      assert RBAC.is_super_admin?(user.id) == true
      
      # User should be able to access their account
      assert RBAC.can_access_account?(user.id, account.id) == true
      
      # User should have the correct role
      assert {:ok, :super_admin} = RBAC.get_user_role_in_account(user.id, account.id)
    end

    test "user with admin role has limited permissions" do
      # Create test data
      {:ok, user} = Auth.create_user(%{email: "admin@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign user to account
      :ok = Accounts.set_user_account(user.id, account.id)
      
      # Create admin role
      {:ok, role} = Auth.create_role(%{name: "admin"})
      
      # Assign role to user
      :ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
      
      # User should have admin permissions
      permissions = RBAC.get_user_permissions(user.id, account.id)
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == true
      
      # User should not be detected as super admin
      assert RBAC.is_super_admin?(user.id) == false
      
      # User should be able to access their account
      assert RBAC.can_access_account?(user.id, account.id) == true
      
      # User should have the correct role
      assert {:ok, :admin} = RBAC.get_user_role_in_account(user.id, account.id)
    end

    test "user with editor role has content editing permissions" do
      # Create test data
      {:ok, user} = Auth.create_user(%{email: "editor@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign user to account
      :ok = Accounts.set_user_account(user.id, account.id)
      
      # Create editor role
      {:ok, role} = Auth.create_role(%{name: "editor"})
      
      # Assign role to user
      :ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
      
      # User should have editor permissions
      permissions = RBAC.get_user_permissions(user.id, account.id)
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == false
      
      # User should not be detected as super admin
      assert RBAC.is_super_admin?(user.id) == false
      
      # User should be able to access their account
      assert RBAC.can_access_account?(user.id, account.id) == true
      
      # User should have the correct role
      assert {:ok, :editor} = RBAC.get_user_role_in_account(user.id, account.id)
    end

    test "user with viewer role has read-only permissions" do
      # Create test data
      {:ok, user} = Auth.create_user(%{email: "viewer@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign user to account
      :ok = Accounts.set_user_account(user.id, account.id)
      
      # Create viewer role
      {:ok, role} = Auth.create_role(%{name: "viewer"})
      
      # Assign role to user
      :ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
      
      # User should have viewer permissions
      permissions = RBAC.get_user_permissions(user.id, account.id)
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == false
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == false
      
      # User should not be detected as super admin
      assert RBAC.is_super_admin?(user.id) == false
      
      # User should be able to access their account
      assert RBAC.can_access_account?(user.id, account.id) == true
      
      # User should have the correct role
      assert {:ok, :viewer} = RBAC.get_user_role_in_account(user.id, account.id)
    end

    test "permission checking works correctly" do
      # Create test data
      {:ok, user} = Auth.create_user(%{email: "test@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign user to account
      :ok = Accounts.set_user_account(user.id, account.id)
      
      # Create admin role
      {:ok, role} = Auth.create_role(%{name: "admin"})
      
      # Assign role to user
      :ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
      
      # Test individual permission checks
      assert RBAC.user_has_permission?(user.id, account.id, :can_manage_users) == false
      assert RBAC.user_has_permission?(user.id, account.id, :can_edit_projects) == true
      assert RBAC.user_has_permission?(user.id, account.id, :can_view_reports) == true
      assert RBAC.user_has_permission?(user.id, account.id, :can_manage_billing) == true
    end

    test "account users listing works correctly" do
      # Create test data
      {:ok, user1} = Auth.create_user(%{email: "user1@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user1.id)
      
      {:ok, user2} = Auth.create_user(%{email: "user2@example.com", password: "password123"}, 
        url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(user2.id)
      
      {:ok, account} = Accounts.create_account()
      
      # Assign users to account
      :ok = Accounts.set_user_account(user1.id, account.id)
      :ok = Accounts.set_user_account(user2.id, account.id)
      
      # Create roles
      {:ok, admin_role} = Auth.create_role(%{name: "admin"})
      {:ok, editor_role} = Auth.create_role(%{name: "editor"})
      
      # Assign roles to users
      :ok = Auth.assign_role_to_user(user1.id, %{account_id: account.id, role_id: admin_role.id})
      :ok = Auth.assign_role_to_user(user2.id, %{account_id: account.id, role_id: editor_role.id})
      
      # List users with roles
      users_with_roles = RBAC.list_account_users_with_roles(account.id)
      assert length(users_with_roles) == 2
      
      # Check that both users are listed with correct roles
      emails = Enum.map(users_with_roles, fn {user, _role} -> user.email end)
      assert "user1@example.com" in emails
      assert "user2@example.com" in emails
      
      roles = Enum.map(users_with_roles, fn {_user, role} -> role end)
      assert :admin in roles
      assert :editor in roles
    end
  end
end
