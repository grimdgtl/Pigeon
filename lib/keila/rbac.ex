defmodule Keila.RBAC do
  @moduledoc """
  Role-Based Access Control (RBAC) module for Keila.

  This module provides functions to manage and verify user permissions across
  multiple tenants, with role-based feature flags for frontend consumption.

  ## Roles

  - `super_admin`: Full access to all tenants and system administration
  - `admin`: Full access to their own tenant's resources
  - `editor`: Can edit content (campaigns/forms) but not manage users or billing
  - `viewer`: Read-only access to campaigns and reports

  ## Feature Flags

  Each role exposes a JSON map of permissions that can be consumed by the frontend
  to show/hide UI elements and control user actions.
  """

  alias Keila.{Auth, Accounts, Repo}
  import Ecto.Query

  @type role_name :: :super_admin | :admin | :editor | :viewer
  @type permission_map :: %{
    can_manage_users: boolean(),
    can_edit_projects: boolean(),
    can_view_reports: boolean(),
    can_manage_billing: boolean()
  }

  @doc """
  Returns the feature flags/permissions map for a given role.

  This map can be consumed by the frontend to control UI visibility and user actions.
  """
  @spec get_role_permissions(role_name()) :: permission_map()
  def get_role_permissions(:super_admin) do
    %{
      can_manage_users: true,
      can_edit_projects: true,
      can_view_reports: true,
      can_manage_billing: true
    }
  end

  def get_role_permissions(:admin) do
    %{
      can_manage_users: false,
      can_edit_projects: true,
      can_view_reports: true,
      can_manage_billing: true
    }
  end

  def get_role_permissions(:editor) do
    %{
      can_manage_users: false,
      can_edit_projects: true,
      can_view_reports: true,
      can_manage_billing: false
    }
  end

  def get_role_permissions(:viewer) do
    %{
      can_manage_users: false,
      can_edit_projects: false,
      can_view_reports: true,
      can_manage_billing: false
    }
  end

  @doc """
  Returns the feature flags/permissions map for a user within a specific account.

  This combines the user's role permissions with multi-tenant access control.
  """
  @spec get_user_permissions(Auth.User.id(), Accounts.Account.id()) :: permission_map()
  def get_user_permissions(user_id, account_id) do
    case get_user_role_in_account(user_id, account_id) do
      {:ok, role_name} -> get_role_permissions(role_name)
      {:error, :no_role} -> %{
        can_manage_users: false,
        can_edit_projects: false,
        can_view_reports: false,
        can_manage_billing: false
      }
    end
  end

  @doc """
  Checks if a user has a specific permission within an account.
  """
  @spec user_has_permission?(Auth.User.id(), Accounts.Account.id(), atom()) :: boolean()
  def user_has_permission?(user_id, account_id, permission) do
    permissions = get_user_permissions(user_id, account_id)
    Map.get(permissions, permission, false)
  end

  @doc """
  Gets the role name for a user within a specific account.

  Returns `{:ok, role_name}` or `{:error, :no_role}`.
  """
  @spec get_user_role_in_account(Auth.User.id(), Accounts.Account.id()) :: 
    {:ok, role_name()} | {:error, :no_role}
  def get_user_role_in_account(user_id, account_id) do
    account = Accounts.get_account(account_id)
    
    if is_nil(account) do
      {:error, :no_role}
    else
      query = from r in Auth.Role,
        join: ugr in Auth.UserGroupRole, on: ugr.role_id == r.id,
        join: ug in Auth.UserGroup, on: ug.id == ugr.user_group_id,
        where: ug.user_id == ^user_id and ug.group_id == ^account.group_id,
        select: r.name

      case Repo.one(query) do
        role_name when role_name in ["super_admin", "admin", "editor", "viewer"] ->
          {:ok, String.to_existing_atom(role_name)}
        _ ->
          {:error, :no_role}
      end
    end
  end

  @doc """
  Checks if a user is a super admin (has access to all tenants).
  """
  @spec is_super_admin?(Auth.User.id()) :: boolean()
  def is_super_admin?(user_id) do
    query = from r in Auth.Role,
      join: ugr in Auth.UserGroupRole, on: ugr.role_id == r.id,
      join: ug in Auth.UserGroup, on: ug.id == ugr.user_group_id,
      where: ug.user_id == ^user_id and r.name == "super_admin",
      select: 1

    case Repo.one(query) do
      1 -> true
      _ -> false
    end
  end

  @doc """
  Lists all accounts that a user has access to.

  Super admins have access to all accounts, while other users only have access
  to their own account.
  """
  @spec list_user_accessible_accounts(Auth.User.id()) :: [Accounts.Account.t()]
  def list_user_accessible_accounts(user_id) do
    if is_super_admin?(user_id) do
      # Super admins can access all accounts
      Repo.all(Accounts.Account)
    else
      # Regular users can only access their own account
      case Accounts.get_user_account(user_id) do
        nil -> []
        account -> [account]
      end
    end
  end

  @doc """
  Checks if a user can access a specific account.

  Super admins can access all accounts, while other users can only access
  their own account.
  """
  @spec can_access_account?(Auth.User.id(), Accounts.Account.id()) :: boolean()
  def can_access_account?(user_id, account_id) do
    accessible_accounts = list_user_accessible_accounts(user_id)
    Enum.any?(accessible_accounts, &(&1.id == account_id))
  end

  @doc """
  Gets all users in an account with their roles.

  Returns a list of `{user, role_name}` tuples.
  """
  @spec list_account_users_with_roles(Accounts.Account.id()) :: [{Auth.User.t(), role_name()}]
  def list_account_users_with_roles(account_id) do
    account = Accounts.get_account(account_id)
    
    if is_nil(account) do
      []
    else
      query = from u in Auth.User,
        join: ug in Auth.UserGroup, on: ug.user_id == u.id,
        join: ugr in Auth.UserGroupRole, on: ugr.user_group_id == ug.id,
        join: r in Auth.Role, on: r.id == ugr.role_id,
        where: ug.group_id == ^account.group_id and r.name in ["super_admin", "admin", "editor", "viewer"],
        select: {u, r.name}

      Repo.all(query)
      |> Enum.map(fn {user, role_name} -> {user, String.to_existing_atom(role_name)} end)
    end
  end

  @doc """
  Verifies that the multi-tenant setup is correct according to the requirements.

  This function checks:
  1. All 3 tenants exist with correct names
  2. All required users exist with correct emails and roles
  3. Role-based permissions are correctly configured

  Returns `{:ok, verification_results}` or `{:error, issues}`.
  """
  @spec verify_multi_tenant_setup() :: {:ok, map()} | {:error, [String.t()]}
  def verify_multi_tenant_setup() do
    issues = []
    
    # Check tenants
    tenant_issues = verify_tenants()
    issues = issues ++ tenant_issues
    
    # Check users and roles
    user_issues = verify_users_and_roles()
    issues = issues ++ user_issues
    
    # Check role permissions
    permission_issues = verify_role_permissions()
    issues = issues ++ permission_issues
    
    if Enum.empty?(issues) do
      {:ok, %{
        tenants: get_tenant_summary(),
        users: get_user_summary(),
        role_permissions: get_all_role_permissions()
      }}
    else
      {:error, issues}
    end
  end

  # Private helper functions

  defp verify_tenants() do
    required_tenants = ["Grim Digital", "Dijagnoza", "Slikaj i Cirkaj"]
    
    Enum.reduce(required_tenants, [], fn tenant_name, acc_issues ->
      case get_account_by_name(tenant_name) do
        nil -> 
          acc_issues ++ ["Tenant '#{tenant_name}' not found"]
        _account -> 
          acc_issues
      end
    end)
  end

  defp verify_users_and_roles() do
    required_users = [
      {"pigeon@grim-digital.com", "Grim Digital", :super_admin},
      {"newsletter@dijagnoza.com", "Dijagnoza", :admin},
      {"editor@dijagnoza.com", "Dijagnoza", :editor},
      {"viewer@dijagnoza.com", "Dijagnoza", :viewer},
      {"newsletter@slikajicirkaj.com", "Slikaj i Cirkaj", :admin},
      {"editor@slikajicirkaj.com", "Slikaj i Cirkaj", :editor},
      {"viewer@slikajicirkaj.com", "Slikaj i Cirkaj", :viewer}
    ]
    
    Enum.reduce(required_users, [], fn {email, tenant_name, expected_role}, acc_issues ->
      case Auth.find_user_by_email(email) do
        nil ->
          acc_issues ++ ["User '#{email}' not found"]
        user ->
          case get_account_by_name(tenant_name) do
            nil ->
              acc_issues ++ ["Tenant '#{tenant_name}' not found for user '#{email}'"]
            account ->
              case get_user_role_in_account(user.id, account.id) do
                {:ok, ^expected_role} -> acc_issues
                {:ok, actual_role} ->
                  acc_issues ++ ["User '#{email}' has role '#{actual_role}' but expected '#{expected_role}'"]
                {:error, :no_role} ->
                  acc_issues ++ ["User '#{email}' has no role in tenant '#{tenant_name}'"]
              end
          end
      end
    end)
  end

  defp verify_role_permissions() do
    # Verify that each role has the expected permissions
    expected_permissions = %{
      super_admin: %{can_manage_users: true, can_edit_projects: true, can_view_reports: true, can_manage_billing: true},
      admin: %{can_manage_users: false, can_edit_projects: true, can_view_reports: true, can_manage_billing: true},
      editor: %{can_manage_users: false, can_edit_projects: true, can_view_reports: true, can_manage_billing: false},
      viewer: %{can_manage_users: false, can_edit_projects: false, can_view_reports: true, can_manage_billing: false}
    }
    
    Enum.reduce(expected_permissions, [], fn {role, expected}, acc_issues ->
      actual = get_role_permissions(role)
      if actual != expected do
        acc_issues ++ ["Role '#{role}' has incorrect permissions. Expected: #{inspect(expected)}, Got: #{inspect(actual)}"]
      else
        acc_issues
      end
    end)
  end

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

  defp get_tenant_summary() do
    tenant_names = ["Grim Digital", "Dijagnoza", "Slikaj i Cirkaj"]
    
    for name <- tenant_names do
      case get_account_by_name(name) do
        nil -> %{name: name, status: "missing"}
        account -> 
          users = list_account_users_with_roles(account.id)
          %{name: name, status: "exists", user_count: length(users)}
      end
    end
  end

  defp get_user_summary() do
    required_users = [
      "pigeon@grim-digital.com",
      "newsletter@dijagnoza.com", 
      "editor@dijagnoza.com",
      "viewer@dijagnoza.com",
      "newsletter@slikajicirkaj.com",
      "editor@slikajicirkaj.com",
      "viewer@slikajicirkaj.com"
    ]
    
    for email <- required_users do
      case Auth.find_user_by_email(email) do
        nil -> %{email: email, status: "missing"}
        user -> %{email: email, status: "exists", activated: not is_nil(user.activated_at)}
      end
    end
  end

  defp get_all_role_permissions() do
    roles = [:super_admin, :admin, :editor, :viewer]
    
    for role <- roles do
      %{role: role, permissions: get_role_permissions(role)}
    end
  end
end
