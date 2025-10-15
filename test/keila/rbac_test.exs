defmodule Keila.RBACTest do
  use Keila.DataCase, async: false
  alias Keila.{RBAC, Auth, Accounts, Repo}
  import Ecto.Query

  @tag :rbac
  describe "role permissions" do
    test "super_admin has all permissions" do
      permissions = RBAC.get_role_permissions(:super_admin)
      
      assert permissions.can_manage_users == true
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == true
    end

    test "admin has limited permissions" do
      permissions = RBAC.get_role_permissions(:admin)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == true
    end

    test "editor has content editing permissions" do
      permissions = RBAC.get_role_permissions(:editor)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == false
    end

    test "viewer has read-only permissions" do
      permissions = RBAC.get_role_permissions(:viewer)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == false
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == false
    end
  end

  @tag :rbac
  describe "multi-tenant setup verification" do
    setup do
      # Run the seeds to ensure we have the required data
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "verifies complete multi-tenant setup" do
      assert {:ok, verification_results} = RBAC.verify_multi_tenant_setup()
      
      # Check tenants
      assert length(verification_results.tenants) == 3
      tenant_names = Enum.map(verification_results.tenants, & &1.name)
      assert "Grim Digital" in tenant_names
      assert "Dijagnoza" in tenant_names
      assert "Slikaj i Cirkaj" in tenant_names
      
      # Check users
      assert length(verification_results.users) == 7
      user_emails = Enum.map(verification_results.users, & &1.email)
      assert "pigeon@grim-digital.com" in user_emails
      assert "newsletter@dijagnoza.com" in user_emails
      assert "editor@dijagnoza.com" in user_emails
      assert "viewer@dijagnoza.com" in user_emails
      assert "newsletter@slikajicirkaj.com" in user_emails
      assert "editor@slikajicirkaj.com" in user_emails
      assert "viewer@slikajicirkaj.com" in user_emails
      
      # Check role permissions
      assert length(verification_results.role_permissions) == 4
      role_names = Enum.map(verification_results.role_permissions, & &1.role)
      assert :super_admin in role_names
      assert :admin in role_names
      assert :editor in role_names
      assert :viewer in role_names
    end

    test "detects missing tenants" do
      # Delete a tenant to test error detection
      grim_account = get_account_by_name("Grim Digital")
      Repo.delete!(grim_account)
      
      assert {:error, issues} = RBAC.verify_multi_tenant_setup()
      assert Enum.any?(issues, &String.contains?(&1, "Grim Digital"))
    end

    test "detects missing users" do
      # Delete a user to test error detection
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      Repo.delete!(user)
      
      assert {:error, issues} = RBAC.verify_multi_tenant_setup()
      assert Enum.any?(issues, &String.contains?(&1, "pigeon@grim-digital.com"))
    end

    test "detects incorrect roles" do
      # Change a user's role to test error detection
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      grim_account = get_account_by_name("Grim Digital")
      
      # Remove super_admin role and add admin role
      Auth.remove_role_from_user(user.id, %{account_id: grim_account.id, role_name: "super_admin"})
      Auth.assign_role_to_user(user.id, %{account_id: grim_account.id, role_name: "admin"})
      
      assert {:error, issues} = RBAC.verify_multi_tenant_setup()
      assert Enum.any?(issues, &String.contains?(&1, "pigeon@grim-digital.com"))
    end
  end

  @tag :rbac
  describe "user role detection" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "detects super_admin role correctly" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      grim_account = get_account_by_name("Grim Digital")
      
      assert {:ok, :super_admin} = RBAC.get_user_role_in_account(user.id, grim_account.id)
    end

    test "detects admin role correctly" do
      user = Auth.find_user_by_email("newsletter@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert {:ok, :admin} = RBAC.get_user_role_in_account(user.id, dijagnoza_account.id)
    end

    test "detects editor role correctly" do
      user = Auth.find_user_by_email("editor@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert {:ok, :editor} = RBAC.get_user_role_in_account(user.id, dijagnoza_account.id)
    end

    test "detects viewer role correctly" do
      user = Auth.find_user_by_email("viewer@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert {:ok, :viewer} = RBAC.get_user_role_in_account(user.id, dijagnoza_account.id)
    end

    test "returns error for user without role" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert {:error, :no_role} = RBAC.get_user_role_in_account(user.id, dijagnoza_account.id)
    end
  end

  @tag :rbac
  describe "user permissions" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "super_admin has all permissions in their account" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      grim_account = get_account_by_name("Grim Digital")
      
      permissions = RBAC.get_user_permissions(user.id, grim_account.id)
      
      assert permissions.can_manage_users == true
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == true
    end

    test "admin has limited permissions in their account" do
      user = Auth.find_user_by_email("newsletter@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      permissions = RBAC.get_user_permissions(user.id, dijagnoza_account.id)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == true
    end

    test "editor has content editing permissions in their account" do
      user = Auth.find_user_by_email("editor@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      permissions = RBAC.get_user_permissions(user.id, dijagnoza_account.id)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == true
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == false
    end

    test "viewer has read-only permissions in their account" do
      user = Auth.find_user_by_email("viewer@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      permissions = RBAC.get_user_permissions(user.id, dijagnoza_account.id)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == false
      assert permissions.can_view_reports == true
      assert permissions.can_manage_billing == false
    end

    test "user without role has no permissions" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      permissions = RBAC.get_user_permissions(user.id, dijagnoza_account.id)
      
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == false
      assert permissions.can_view_reports == false
      assert permissions.can_manage_billing == false
    end
  end

  @tag :rbac
  describe "permission checking" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "super_admin can manage users" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      grim_account = get_account_by_name("Grim Digital")
      
      assert RBAC.user_has_permission?(user.id, grim_account.id, :can_manage_users) == true
    end

    test "admin cannot manage users" do
      user = Auth.find_user_by_email("newsletter@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert RBAC.user_has_permission?(user.id, dijagnoza_account.id, :can_manage_users) == false
    end

    test "editor can edit projects" do
      user = Auth.find_user_by_email("editor@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert RBAC.user_has_permission?(user.id, dijagnoza_account.id, :can_edit_projects) == true
    end

    test "viewer cannot edit projects" do
      user = Auth.find_user_by_email("viewer@dijagnoza.com")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert RBAC.user_has_permission?(user.id, dijagnoza_account.id, :can_edit_projects) == false
    end

    test "all roles can view reports" do
      roles_and_users = [
        {"pigeon@grim-digital.com", "Grim Digital"},
        {"newsletter@dijagnoza.com", "Dijagnoza"},
        {"editor@dijagnoza.com", "Dijagnoza"},
        {"viewer@dijagnoza.com", "Dijagnoza"}
      ]
      
      for {email, tenant_name} <- roles_and_users do
        user = Auth.find_user_by_email(email)
        account = get_account_by_name(tenant_name)
        
        assert RBAC.user_has_permission?(user.id, account.id, :can_view_reports) == true
      end
    end
  end

  @tag :rbac
  describe "super admin detection" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "detects super admin correctly" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      assert RBAC.is_super_admin?(user.id) == true
    end

    test "detects non-super admin correctly" do
      user = Auth.find_user_by_email("newsletter@dijagnoza.com")
      assert RBAC.is_super_admin?(user.id) == false
    end
  end

  @tag :rbac
  describe "account access control" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "super admin can access all accounts" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      accessible_accounts = RBAC.list_user_accessible_accounts(user.id)
      
      assert length(accessible_accounts) >= 3
      account_names = Enum.map(accessible_accounts, &get_account_name/1)
      assert "Grim Digital" in account_names
      assert "Dijagnoza" in account_names
      assert "Slikaj i Cirkaj" in account_names
    end

    test "admin can only access their own account" do
      user = Auth.find_user_by_email("newsletter@dijagnoza.com")
      accessible_accounts = RBAC.list_user_accessible_accounts(user.id)
      
      assert length(accessible_accounts) == 1
      account_name = get_account_name(hd(accessible_accounts))
      assert account_name == "Dijagnoza"
    end

    test "super admin can access specific accounts" do
      user = Auth.find_user_by_email("pigeon@grim-digital.com")
      grim_account = get_account_by_name("Grim Digital")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      
      assert RBAC.can_access_account?(user.id, grim_account.id) == true
      assert RBAC.can_access_account?(user.id, dijagnoza_account.id) == true
    end

    test "admin cannot access other accounts" do
      user = Auth.find_user_by_email("newsletter@dijagnoza.com")
      grim_account = get_account_by_name("Grim Digital")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      assert RBAC.can_access_account?(user.id, grim_account.id) == false
      assert RBAC.can_access_account?(user.id, sic_account.id) == false
    end
  end

  @tag :rbac
  describe "account users listing" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "lists all users with roles in Grim Digital account" do
      grim_account = get_account_by_name("Grim Digital")
      users_with_roles = RBAC.list_account_users_with_roles(grim_account.id)
      
      assert length(users_with_roles) == 1
      {user, role} = hd(users_with_roles)
      assert user.email == "pigeon@grim-digital.com"
      assert role == :super_admin
    end

    test "lists all users with roles in Dijagnoza account" do
      dijagnoza_account = get_account_by_name("Dijagnoza")
      users_with_roles = RBAC.list_account_users_with_roles(dijagnoza_account.id)
      
      assert length(users_with_roles) == 3
      
      emails = Enum.map(users_with_roles, fn {user, _role} -> user.email end)
      assert "newsletter@dijagnoza.com" in emails
      assert "editor@dijagnoza.com" in emails
      assert "viewer@dijagnoza.com" in emails
      
      roles = Enum.map(users_with_roles, fn {_user, role} -> role end)
      assert :admin in roles
      assert :editor in roles
      assert :viewer in roles
    end

    test "lists all users with roles in Slikaj i Cirkaj account" do
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      users_with_roles = RBAC.list_account_users_with_roles(sic_account.id)
      
      assert length(users_with_roles) == 3
      
      emails = Enum.map(users_with_roles, fn {user, _role} -> user.email end)
      assert "newsletter@slikajicirkaj.com" in emails
      assert "editor@slikajicirkaj.com" in emails
      assert "viewer@slikajicirkaj.com" in emails
      
      roles = Enum.map(users_with_roles, fn {_user, role} -> role end)
      assert :admin in roles
      assert :editor in roles
      assert :viewer in roles
    end
  end

  @tag :rbac
  describe "multi-tenant isolation" do
    setup do
      Mix.Task.run("run", ["priv/repo/seeds.exs"])
      :ok
    end

    test "users cannot access other tenants' resources" do
      # Dijagnoza admin should not be able to access Slikaj i Cirkaj resources
      dij_admin = Auth.find_user_by_email("newsletter@dijagnoza.com")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      assert RBAC.can_access_account?(dij_admin.id, sic_account.id) == false
      
      permissions = RBAC.get_user_permissions(dij_admin.id, sic_account.id)
      assert permissions.can_manage_users == false
      assert permissions.can_edit_projects == false
      assert permissions.can_view_reports == false
      assert permissions.can_manage_billing == false
    end

    test "super admin can access all tenants' resources" do
      super_admin = Auth.find_user_by_email("pigeon@grim-digital.com")
      
      # Should be able to access all three accounts
      grim_account = get_account_by_name("Grim Digital")
      dijagnoza_account = get_account_by_name("Dijagnoza")
      sic_account = get_account_by_name("Slikaj i Cirkaj")
      
      assert RBAC.can_access_account?(super_admin.id, grim_account.id) == true
      assert RBAC.can_access_account?(super_admin.id, dijagnoza_account.id) == true
      assert RBAC.can_access_account?(super_admin.id, sic_account.id) == true
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
