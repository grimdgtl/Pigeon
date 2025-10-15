defmodule Keila.RBACTestHelper do
  @moduledoc """
  Helper functions for RBAC testing.

  This module provides utilities to set up test data and verify
  multi-tenant user management and role-based access control.
  """

  alias Keila.{Auth, Accounts, Repo}
  import Ecto.Query

  @doc """
  Sets up the complete multi-tenant test environment with all required
  tenants, users, and roles as specified in the requirements.
  """
  @spec setup_multi_tenant_environment() :: map()
  def setup_multi_tenant_environment() do
    # Ensure we have the required roles
    roles = ensure_roles()
    
    # Create the three tenants
    tenants = create_tenants()
    
    # Create users and assign roles
    users = create_users_with_roles(tenants, roles)
    
    %{
      roles: roles,
      tenants: tenants,
      users: users
    }
  end

  @doc """
  Creates a test user with the specified email and assigns them to the given account with the specified role.
  """
  @spec create_test_user(String.t(), String.t(), String.t(), String.t()) :: Auth.User.t()
  def create_test_user(email, password, tenant_name, role_name) do
    # Create user
    {:ok, user} = Auth.create_user(
      %{email: email, password: password},
      url_fn: & &1,
      skip_activation_email: true
    )
    
    {:ok, _} = Auth.activate_user(user.id)
    
    # Get account
    account = get_account_by_name(tenant_name)
    
    # Assign role
    role = Repo.get_by(Auth.Role, name: role_name)
    Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
    
    user
  end

  @doc """
  Verifies that all required tenants exist with the correct names.
  """
  @spec verify_tenants_exist() :: {:ok, [map()]} | {:error, [String.t()]}
  def verify_tenants_exist() do
    required_tenants = ["Grim Digital", "Dijagnoza", "Slikaj i Cirkaj"]
    issues = []
    found_tenants = []
    
    {issues, found_tenants} = Enum.reduce(required_tenants, {issues, found_tenants}, fn tenant_name, {acc_issues, acc_found} ->
      case get_account_by_name(tenant_name) do
        nil -> 
          {acc_issues ++ ["Tenant '#{tenant_name}' not found"], acc_found}
        account -> 
          {acc_issues, acc_found ++ [%{name: tenant_name, account: account}]}
      end
    end)
    
    if Enum.empty?(issues) do
      {:ok, found_tenants}
    else
      {:error, issues}
    end
  end

  @doc """
  Verifies that all required users exist with the correct emails and roles.
  """
  @spec verify_users_exist() :: {:ok, [map()]} | {:error, [String.t()]}
  def verify_users_exist() do
    required_users = [
      {"pigeon@grim-digital.com", "Grim Digital", "super_admin"},
      {"newsletter@dijagnoza.com", "Dijagnoza", "admin"},
      {"editor@dijagnoza.com", "Dijagnoza", "editor"},
      {"viewer@dijagnoza.com", "Dijagnoza", "viewer"},
      {"newsletter@slikajicirkaj.com", "Slikaj i Cirkaj", "admin"},
      {"editor@slikajicirkaj.com", "Slikaj i Cirkaj", "editor"},
      {"viewer@slikajicirkaj.com", "Slikaj i Cirkaj", "viewer"}
    ]
    
    issues = []
    found_users = []
    
    {issues, found_users} = Enum.reduce(required_users, {issues, found_users}, fn {email, tenant_name, expected_role}, {acc_issues, acc_found} ->
      case Auth.find_user_by_email(email) do
        nil ->
          {acc_issues ++ ["User '#{email}' not found"], acc_found}
        user ->
          case get_account_by_name(tenant_name) do
            nil ->
              {acc_issues ++ ["Tenant '#{tenant_name}' not found for user '#{email}'"], acc_found}
            account ->
              case get_user_role_in_account(user.id, account.id) do
                {:ok, actual_role} ->
                  expected_role_atom = String.to_atom(expected_role)
                  if actual_role == expected_role_atom do
                    {acc_issues, acc_found ++ [%{
                      email: email,
                      user: user,
                      tenant: tenant_name,
                      role: actual_role
                    }]}
                  else
                    {acc_issues ++ ["User '#{email}' has role '#{actual_role}' but expected '#{expected_role}'"], acc_found}
                  end
                {:error, :no_role} ->
                  {acc_issues ++ ["User '#{email}' has no role in tenant '#{tenant_name}'"], acc_found}
              end
          end
      end
    end)
    
    if Enum.empty?(issues) do
      {:ok, found_users}
    else
      {:error, issues}
    end
  end

  @doc """
  Creates a summary report of the current multi-tenant setup.
  """
  @spec create_setup_summary() :: map()
  def create_setup_summary() do
    {:ok, tenants} = verify_tenants_exist()
    {:ok, users} = verify_users_exist()
    
    %{
      tenants: Enum.map(tenants, & &1.name),
      users: Enum.map(users, fn u -> %{
        email: u.email,
        tenant: u.tenant,
        role: u.role,
        activated: not is_nil(u.user.activated_at)
      } end),
      total_tenants: length(tenants),
      total_users: length(users)
    }
  end

  # Private helper functions

  defp ensure_roles() do
    role_names = ["super_admin", "admin", "editor", "viewer"]
    
    for role_name <- role_names do
      Repo.get_by(Auth.Role, name: role_name) || Repo.insert!(%Auth.Role{name: role_name})
    end
  end

  defp create_tenants() do
    tenant_names = ["Grim Digital", "Dijagnoza", "Slikaj i Cirkaj"]
    
    for name <- tenant_names do
      case get_account_by_name(name) do
        nil ->
          {:ok, account} = Accounts.create_account()
          {:ok, _group} = Auth.update_group(account.group_id, %{name: name})
          account
        account ->
          account
      end
    end
  end

  defp create_users_with_roles(_tenants, _roles) do
    user_specs = [
      {"pigeon@grim-digital.com", "SuperSecret123!", "Grim Digital", "super_admin"},
      {"newsletter@dijagnoza.com", "Dijagnoza123!", "Dijagnoza", "admin"},
      {"editor@dijagnoza.com", "Dijagnoza123!", "Dijagnoza", "editor"},
      {"viewer@dijagnoza.com", "Dijagnoza123!", "Dijagnoza", "viewer"},
      {"newsletter@slikajicirkaj.com", "Slikaj123!", "Slikaj i Cirkaj", "admin"},
      {"editor@slikajicirkaj.com", "Slikaj123!", "Slikaj i Cirkaj", "editor"},
      {"viewer@slikajicirkaj.com", "Slikaj123!", "Slikaj i Cirkaj", "viewer"}
    ]
    
    for {email, password, tenant_name, role_name} <- user_specs do
      create_test_user(email, password, tenant_name, role_name)
    end
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

  defp get_user_role_in_account(user_id, account_id) do
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
end
