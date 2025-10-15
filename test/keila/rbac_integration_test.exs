defmodule Keila.RBACIntegrationTest do
  use Keila.DataCase, async: false
  alias Keila.{RBAC, RBACTestHelper, Auth, Accounts, Repo}
  import Ecto.Query

  @tag :rbac_integration
  describe "Complete Multi-Tenant RBAC Integration" do
    setup do
      # Set up the complete multi-tenant environment
      setup_data = RBACTestHelper.setup_multi_tenant_environment()
      
      # Verify the setup is correct
      {:ok, verification_results} = RBAC.verify_multi_tenant_setup()
      
      %{
        setup_data: setup_data,
        verification: verification_results
      }
    end

    test "verifies all tenants exist with correct structure", %{verification: verification} do
      # Check that all 3 tenants exist
      assert length(verification.tenants) == 3
      
      tenant_names = Enum.map(verification.tenants, & &1.name)
      assert "Grim Digital" in tenant_names
      assert "Dijagnoza" in tenant_names
      assert "Slikaj i Cirkaj" in tenant_names
      
      # Check that all tenants have users
      for tenant <- verification.tenants do
        assert tenant.status == "exists"
        assert tenant.user_count > 0
      end
    end

    test "verifies all users exist with correct roles", %{verification: verification} do
      # Check that all 7 users exist
      assert length(verification.users) == 7
      
      user_emails = Enum.map(verification.users, & &1.email)
      expected_emails = [
        "pigeon@grim-digital.com",
        "newsletter@dijagnoza.com",
        "editor@dijagnoza.com",
        "viewer@dijagnoza.com",
        "newsletter@slikajicirkaj.com",
        "editor@slikajicirkaj.com",
        "viewer@slikajicirkaj.com"
      ]
      
      for email <- expected_emails do
        assert email in user_emails
      end
      
      # Check that all users are activated
      for user <- verification.users do
        assert user.status == "exists"
        assert user.activated == true
      end
    end

    test "verifies role-based permissions are correctly configured", %{verification: verification} do
      # Check that all 4 roles have correct permissions
      assert length(verification.role_permissions) == 4
      
      role_permissions_map = Enum.into(verification.role_permissions, %{}, fn rp ->
        {rp.role, rp.permissions}
      end)
      
      # Super admin should have all permissions
      super_admin_perms = role_permissions_map[:super_admin]
      assert super_admin_perms.can_manage_users == true
      assert super_admin_perms.can_edit_projects == true
      assert super_admin_perms.can_view_reports == true
      assert super_admin_perms.can_manage_billing == true
      
      # Admin should have most permissions except user management
      admin_perms = role_permissions_map[:admin]
      assert admin_perms.can_manage_users == false
      assert admin_perms.can_edit_projects == true
      assert admin_perms.can_view_reports == true
      assert admin_perms.can_manage_billing == true
      
      # Editor should have content editing permissions
      editor_perms = role_permissions_map[:editor]
      assert editor_perms.can_manage_users == false
      assert editor_perms.can_edit_projects == true
      assert editor_perms.can_view_reports == true
      assert editor_perms.can_manage_billing == false
      
      # Viewer should have read-only permissions
      viewer_perms = role_permissions_map[:viewer]
      assert viewer_perms.can_manage_users == false
      assert viewer_perms.can_edit_projects == false
      assert viewer_perms.can_view_reports == true
      assert viewer_perms.can_manage_billing == false
    end
  end

  @tag :rbac_integration
  describe "Multi-Tenant Access Control Scenarios" do
    setup do
      RBACTestHelper.setup_multi_tenant_environment()
      :ok
    end

    test "super admin can access all tenants and has full permissions" do
      super_admin = Auth.find_user_by_email("pigeon@grim-digital.com")
      
      # Should be detected as super admin
      assert RBAC.is_super_admin?(super_admin.id) == true
      
      # Should be able to access all accounts
      accessible_accounts = RBAC.list_user_accessible_accounts(super_admin.id)
      assert length(accessible_accounts) >= 3
      
      account_names = Enum.map(accessible_accounts, &get_account_name/1)
      assert "Grim Digital" in account_names
      assert "Dijagnoza" in account_names
      assert "Slikaj i Cirkaj" in account_names
      
      # Should have super admin permissions in all accounts
      for account <- accessible_accounts do
        permissions = RBAC.get_user_permissions(super_admin.id, account.id)
        assert permissions.can_manage_users == true
        assert permissions.can_edit_projects == true
        assert permissions.can_view_reports == true
        assert permissions.can_manage_billing == true
      end
    end

    test "admin users can only access their own tenant with admin permissions" do
      dij_admin = Auth.find_user_by_email("newsletter@dijagnoza.com")
      sic_admin = Auth.find_user_by_email("newsletter@slikajicirkaj.com")
      
      # Should not be super admins
      assert RBAC.is_super_admin?(dij_admin.id) == false
      assert RBAC.is_super_admin?(sic_admin.id) == false
      
      # Should only be able to access their own accounts
      dij_accessible = RBAC.list_user_accessible_accounts(dij_admin.id)
      sic_accessible = RBAC.list_user_accessible_accounts(sic_admin.id)
      
      assert length(dij_accessible) == 1
      assert length(sic_accessible) == 1
      
      assert get_account_name(hd(dij_accessible)) == "Dijagnoza"
      assert get_account_name(hd(sic_accessible)) == "Slikaj i Cirkaj"
      
      # Should have admin permissions in their own accounts
      dij_account = get_account_by_name("Dijagnoza")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      dij_permissions = RBAC.get_user_permissions(dij_admin.id, dij_account.id)
      assert dij_permissions.can_manage_users == false
      assert dij_permissions.can_edit_projects == true
      assert dij_permissions.can_view_reports == true
      assert dij_permissions.can_manage_billing == true
      
      sic_permissions = RBAC.get_user_permissions(sic_admin.id, sic_account.id)
      assert sic_permissions.can_manage_users == false
      assert sic_permissions.can_edit_projects == true
      assert sic_permissions.can_view_reports == true
      assert sic_permissions.can_manage_billing == true
      
      # Should not be able to access other tenants
      assert RBAC.can_access_account?(dij_admin.id, sic_account.id) == false
      assert RBAC.can_access_account?(sic_admin.id, dij_account.id) == false
    end

    test "editor users can edit content but not manage users or billing" do
      dij_editor = Auth.find_user_by_email("editor@dijagnoza.com")
      sic_editor = Auth.find_user_by_email("editor@slikajicirkaj.com")
      
      dij_account = get_account_by_name("Dijagnoza")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      # Should have editor permissions
      dij_permissions = RBAC.get_user_permissions(dij_editor.id, dij_account.id)
      assert dij_permissions.can_manage_users == false
      assert dij_permissions.can_edit_projects == true
      assert dij_permissions.can_view_reports == true
      assert dij_permissions.can_manage_billing == false
      
      sic_permissions = RBAC.get_user_permissions(sic_editor.id, sic_account.id)
      assert sic_permissions.can_manage_users == false
      assert sic_permissions.can_edit_projects == true
      assert sic_permissions.can_view_reports == true
      assert sic_permissions.can_manage_billing == false
      
      # Should only be able to access their own accounts
      assert RBAC.can_access_account?(dij_editor.id, dij_account.id) == true
      assert RBAC.can_access_account?(dij_editor.id, sic_account.id) == false
      assert RBAC.can_access_account?(sic_editor.id, sic_account.id) == true
      assert RBAC.can_access_account?(sic_editor.id, dij_account.id) == false
    end

    test "viewer users have read-only access" do
      dij_viewer = Auth.find_user_by_email("viewer@dijagnoza.com")
      sic_viewer = Auth.find_user_by_email("viewer@slikajicirkaj.com")
      
      dij_account = get_account_by_name("Dijagnoza")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      # Should have viewer permissions
      dij_permissions = RBAC.get_user_permissions(dij_viewer.id, dij_account.id)
      assert dij_permissions.can_manage_users == false
      assert dij_permissions.can_edit_projects == false
      assert dij_permissions.can_view_reports == true
      assert dij_permissions.can_manage_billing == false
      
      sic_permissions = RBAC.get_user_permissions(sic_viewer.id, sic_account.id)
      assert sic_permissions.can_manage_users == false
      assert sic_permissions.can_edit_projects == false
      assert sic_permissions.can_view_reports == true
      assert sic_permissions.can_manage_billing == false
      
      # Should only be able to access their own accounts
      assert RBAC.can_access_account?(dij_viewer.id, dij_account.id) == true
      assert RBAC.can_access_account?(dij_viewer.id, sic_account.id) == false
      assert RBAC.can_access_account?(sic_viewer.id, sic_account.id) == true
      assert RBAC.can_access_account?(sic_viewer.id, dij_account.id) == false
    end
  end

  @tag :rbac_integration
  describe "Account User Management" do
    setup do
      RBACTestHelper.setup_multi_tenant_environment()
      :ok
    end

    test "lists all users with correct roles in each account" do
      # Grim Digital should have 1 user (super admin)
      grim_account = get_account_by_name("Grim Digital")
      grim_users = RBAC.list_account_users_with_roles(grim_account.id)
      assert length(grim_users) == 1
      
      {user, role} = hd(grim_users)
      assert user.email == "pigeon@grim-digital.com"
      assert role == :super_admin
      
      # Dijagnoza should have 3 users (admin, editor, viewer)
      dij_account = get_account_by_name("Dijagnoza")
      dij_users = RBAC.list_account_users_with_roles(dij_account.id)
      assert length(dij_users) == 3
      
      dij_emails = Enum.map(dij_users, fn {u, _r} -> u.email end)
      assert "newsletter@dijagnoza.com" in dij_emails
      assert "editor@dijagnoza.com" in dij_emails
      assert "viewer@dijagnoza.com" in dij_emails
      
      dij_roles = Enum.map(dij_users, fn {_u, r} -> r end)
      assert :admin in dij_roles
      assert :editor in dij_roles
      assert :viewer in dij_roles
      
      # Slikaj i Cirkaj should have 3 users (admin, editor, viewer)
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      sic_users = RBAC.list_account_users_with_roles(sic_account.id)
      assert length(sic_users) == 3
      
      sic_emails = Enum.map(sic_users, fn {u, _r} -> u.email end)
      assert "newsletter@slikajicirkaj.com" in sic_emails
      assert "editor@slikajicirkaj.com" in sic_emails
      assert "viewer@slikajicirkaj.com" in sic_emails
      
      sic_roles = Enum.map(sic_users, fn {_u, r} -> r end)
      assert :admin in sic_roles
      assert :editor in sic_roles
      assert :viewer in sic_roles
    end
  end

  @tag :rbac_integration
  describe "Permission Checking Integration" do
    setup do
      RBACTestHelper.setup_multi_tenant_environment()
      :ok
    end

    test "permission checking works correctly across all roles and tenants" do
      test_cases = [
        # {email, tenant, role, expected_permissions}
        {"pigeon@grim-digital.com", "Grim Digital", :super_admin, %{
          can_manage_users: true, can_edit_projects: true, can_view_reports: true, can_manage_billing: true
        }},
        {"newsletter@dijagnoza.com", "Dijagnoza", :admin, %{
          can_manage_users: false, can_edit_projects: true, can_view_reports: true, can_manage_billing: true
        }},
        {"editor@dijagnoza.com", "Dijagnoza", :editor, %{
          can_manage_users: false, can_edit_projects: true, can_view_reports: true, can_manage_billing: false
        }},
        {"viewer@dijagnoza.com", "Dijagnoza", :viewer, %{
          can_manage_users: false, can_edit_projects: false, can_view_reports: true, can_manage_billing: false
        }},
        {"newsletter@slikajicirkaj.com", "Slikaj i Cirkaj", :admin, %{
          can_manage_users: false, can_edit_projects: true, can_view_reports: true, can_manage_billing: true
        }},
        {"editor@slikajicirkaj.com", "Slikaj i Cirkaj", :editor, %{
          can_manage_users: false, can_edit_projects: true, can_view_reports: true, can_manage_billing: false
        }},
        {"viewer@slikajicirkaj.com", "Slikaj i Cirkaj", :viewer, %{
          can_manage_users: false, can_edit_projects: false, can_view_reports: true, can_manage_billing: false
        }}
      ]
      
      for {email, tenant_name, expected_role, expected_permissions} <- test_cases do
        user = Auth.find_user_by_email(email)
        account = get_account_by_name(tenant_name)
        
        # Verify role detection
        assert {:ok, ^expected_role} = RBAC.get_user_role_in_account(user.id, account.id)
        
        # Verify permissions
        actual_permissions = RBAC.get_user_permissions(user.id, account.id)
        assert actual_permissions == expected_permissions
        
        # Verify individual permission checks
        for {permission, expected_value} <- expected_permissions do
          assert RBAC.user_has_permission?(user.id, account.id, permission) == expected_value
        end
      end
    end
  end

  @tag :rbac_integration
  describe "Cross-Tenant Isolation" do
    setup do
      RBACTestHelper.setup_multi_tenant_environment()
      :ok
    end

    test "users cannot access other tenants' resources" do
      # Dijagnoza users should not be able to access Slikaj i Cirkaj resources
      dij_users = [
        "newsletter@dijagnoza.com",
        "editor@dijagnoza.com", 
        "viewer@dijagnoza.com"
      ]
      
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      for email <- dij_users do
        user = Auth.find_user_by_email(email)
        
        # Should not be able to access the account
        assert RBAC.can_access_account?(user.id, sic_account.id) == false
        
        # Should have no permissions in the other tenant
        permissions = RBAC.get_user_permissions(user.id, sic_account.id)
        assert permissions.can_manage_users == false
        assert permissions.can_edit_projects == false
        assert permissions.can_view_reports == false
        assert permissions.can_manage_billing == false
        
        # Should not have a role in the other tenant
        assert {:error, :no_role} = RBAC.get_user_role_in_account(user.id, sic_account.id)
      end
    end

    test "super admin can access all tenants but others cannot" do
      super_admin = Auth.find_user_by_email("pigeon@grim-digital.com")
      regular_admin = Auth.find_user_by_email("newsletter@dijagnoza.com")
      
      all_accounts = [
        get_account_by_name("Grim Digital"),
        get_account_by_name("Dijagnoza"),
        get_account_by_name("Slikaj i Cirkaj")
      ]
      
      # Super admin should be able to access all accounts
      for account <- all_accounts do
        assert RBAC.can_access_account?(super_admin.id, account.id) == true
      end
      
      # Regular admin should only be able to access their own account
      dij_account = get_account_by_name("Dijagnoza")
      grim_account = get_account_by_name("Grim Digital")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      assert RBAC.can_access_account?(regular_admin.id, dij_account.id) == true
      assert RBAC.can_access_account?(regular_admin.id, grim_account.id) == false
      assert RBAC.can_access_account?(regular_admin.id, sic_account.id) == false
    end
  end

  # Helper functions

  defp get_account_by_name(name) do
    Repo.one(
      from a in Accounts.Account,
        join: g in Auth.Group,
        on: g.id == a.group_id,
        where: g.name == ^name,
        select: a,
        limit: 1
    )
  end

  defp get_account_name(account) do
    Repo.one(
      from g in Auth.Group,
        where: g.id == ^account.group_id,
        select: g.name
    )
  end
end
