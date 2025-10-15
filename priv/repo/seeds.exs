# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

require Logger
import Ecto.Query
alias Keila.{Repo, Auth, Accounts}

default_email = "root@localhost"

if Repo.all(Auth.Group) == [] do
  group = Repo.insert!(%Auth.Group{name: "root"})
  role = Repo.insert!(%Auth.Role{name: "root"})
  permission = Repo.insert!(%Auth.Permission{name: "administer_keila"})
  Repo.insert!(%Auth.RolePermission{role_id: role.id, permission_id: permission.id, is_inherited: true})

  email =
    case System.get_env("KEILA_USER") do
      email when email not in ["", nil] ->
        email

      _empty ->
        Logger.warning("KEILA_USER not set. Creating root user with email: #{default_email}")
        default_email
    end

  password =
    case System.get_env("KEILA_PASSWORD") do
      password when password not in ["", nil] ->
        password

      _empty ->
        password = :crypto.strong_rand_bytes(24) |> Base.url_encode64()
        Logger.warning("KEILA_PASSWORD not set. Setting random root user password: #{password}")
        password
    end

  case Keila.Auth.create_user(%{email: email, password: password},
         url_fn: & &1,
         skip_activation_email: true
       ) do
    {:ok, user} ->
      Keila.Auth.activate_user(user.id)
      Keila.Auth.add_user_group_role(user.id, group.id, role.id)
      Logger.info("Created root user with #{email}")

    {:error, changeset} ->
      Keila.ReleaseTasks.rollback(0)

      errors =
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)

      Logger.error("Failed to create root user: #{inspect(errors)}")
      Logger.flush()
      System.halt(1)
  end
else
  Logger.info("Database already populated, not populating database.")
end

# -----------------------------------------------------------------------------
# Multi-tenant seed data (idempotent)
# -----------------------------------------------------------------------------

find_or_create_role = fn name ->
  Repo.get_by(Auth.Role, name: name) || Repo.insert!(%Auth.Role{name: name})
end

find_or_create_permission = fn name ->
  Repo.get_by(Auth.Permission, name: name) || Repo.insert!(%Auth.Permission{name: name})
end

ensure_role_has_permission = fn role, perm_name, is_inherited ->
  perm = find_or_create_permission.(perm_name)
  Repo.insert!(
    %Auth.RolePermission{role_id: role.id, permission_id: perm.id, is_inherited: is_inherited},
    on_conflict: :nothing
  )
end

ensure_account_named = fn account_name ->
  # Find an existing account whose backing group already has this name; otherwise create one
  existing =
    Repo.one(
      from a in Accounts.Account,
        join: g in Auth.Group,
        on: g.id == a.group_id,
        where: g.name == ^account_name,
        select: a,
        limit: 1
    )

  case existing do
    %Accounts.Account{} = a -> a
    nil ->
      {:ok, account} = Accounts.create_account()
      {:ok, _grp} = Auth.update_group(account.group_id, %{name: account_name})
      account
  end
end

ensure_user = fn email, password ->
  case Auth.find_user_by_email(email) do
    %Auth.User{} = u -> u
    nil ->
      {:ok, u} = Auth.create_user(%{email: email, password: password}, url_fn: & &1, skip_activation_email: true)
      {:ok, _} = Auth.activate_user(u.id)
      u
  end
end

ensure_user_in_account = fn user, account ->
  # Adds user to account group; tolerate :error in case of conflicting prior memberships
  _ = Accounts.set_user_account(user.id, account.id)
  :ok
end

assign_role = fn user, account, role_name ->
  role = find_or_create_role.(role_name)
  :ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})
end

# Ensure base roles and permissions
super_admin_role = find_or_create_role.("super_admin")
admin_role = find_or_create_role.("admin")
editor_role = find_or_create_role.("editor")
viewer_role = find_or_create_role.("viewer")

# Core permissions
ensure_role_has_permission.(super_admin_role, "administer_keila", true)
ensure_role_has_permission.(admin_role, "administer_keila", false)

# 1) Grim Digital with super admin
grim_account = ensure_account_named.("Grim Digital")
super_user = ensure_user.("pigeon@grim-digital.com", "SuperSecret123!")
ensure_user_in_account.(super_user, grim_account)
assign_role.(super_user, grim_account, "super_admin")

# 2) Dijagnoza tenant
dijagnoza_account = ensure_account_named.("Dijagnoza")
dij_admin = ensure_user.("newsletter@dijagnoza.com", "Dijagnoza123!")
ensure_user_in_account.(dij_admin, dijagnoza_account)
assign_role.(dij_admin, dijagnoza_account, "admin")

dij_editor = ensure_user.("editor@dijagnoza.com", "Dijagnoza123!")
ensure_user_in_account.(dij_editor, dijagnoza_account)
assign_role.(dij_editor, dijagnoza_account, "editor")

dij_viewer = ensure_user.("viewer@dijagnoza.com", "Dijagnoza123!")
ensure_user_in_account.(dij_viewer, dijagnoza_account)
assign_role.(dij_viewer, dijagnoza_account, "viewer")

# 3) Slikaj i Cirkaj tenant
sic_account = ensure_account_named.("Slikaj i Cirkaj")
sic_admin = ensure_user.("newsletter@slikajicirkaj.com", "Slikaj123!")
ensure_user_in_account.(sic_admin, sic_account)
assign_role.(sic_admin, sic_account, "admin")

sic_editor = ensure_user.("editor@slikajicirkaj.com", "Slikaj123!")
ensure_user_in_account.(sic_editor, sic_account)
assign_role.(sic_editor, sic_account, "editor")

sic_viewer = ensure_user.("viewer@slikajicirkaj.com", "Slikaj123!")
ensure_user_in_account.(sic_viewer, sic_account)
assign_role.(sic_viewer, sic_account, "viewer")

Logger.info("Multi-tenant seed data ensured (accounts, users, roles, permissions)")
