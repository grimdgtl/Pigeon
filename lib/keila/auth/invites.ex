defmodule Keila.Auth.Invites do
  @moduledoc """
  Context module for managing user invites.
  """

  import Ecto.Query, warn: false
  alias Keila.Repo
  alias Keila.Auth.Schemas.Invite
  alias Keila.Auth.User
  alias Keila.Auth
  alias Keila.Projects
  alias Keila.Accounts

  @doc """
  Creates a new invite with the given attributes.
  """
  def create_invite!(attrs) do
    # Set default values
    attrs = 
      attrs
      |> Map.put_new("role", "admin")
      |> Map.put_new("expires_at", DateTime.add(DateTime.utc_now(), invite_ttl_hours() * 3600))
      |> Map.put_new("token", generate_secure_token())

    attrs
    |> Invite.create_changeset()
    |> Repo.insert!()
  end

  @doc """
  Revokes an invite by setting its expiry to the past.
  """
  def revoke_invite!(token) do
    case get_invite_by_token(token) do
      nil -> 
        {:error, :not_found}
      invite ->
        updated_invite = invite
        |> Invite.changeset(%{expires_at: DateTime.add(DateTime.utc_now(), -1)})
        |> Repo.update!()
        {:ok, updated_invite}
    end
  end

  @doc """
  Accepts an invite by creating a user and marking the invite as used.
  """
  def accept_invite!(token, password_params) do
    case get_invite_by_token(token) do
      nil ->
        {:error, :not_found}

      invite ->
        cond do
          Invite.used?(invite) ->
            {:error, :already_used}

          Invite.expired?(invite) ->
            {:error, :expired}

          true ->
            case Repo.transaction(fn ->
              # Create user if not exists
              user = case Auth.find_user_by_email(invite.email) do
                nil ->
                  user_attrs = %{
                    email: invite.email,
                    password: password_params["password"],
                    password_confirmation: password_params["password_confirmation"],
                    first_login_required: false,
                    invited_at: DateTime.utc_now()
                  }
                  case Auth.create_user(user_attrs) do
                    {:ok, user} -> user
                    {:error, _} -> Repo.rollback(:user_creation_failed)
                  end

                existing_user ->
                  # Update existing user with new password
                  existing_user
                  |> User.update_password_changeset(%{
                    password: password_params["password"]
                  })
                  |> Repo.update!()
              end

              # Mark invite as used
              updated_invite = invite
              |> Invite.accept_changeset(%{used_at: DateTime.utc_now()})
              |> Repo.update!()

              # Assign role to user in the project
              project = Projects.get_project(invite.project_id)
              # Get the account from the project's group
              account = Accounts.get_project_account(project.id)
              Auth.assign_role_to_user(user.id, %{account_id: account.id, role_name: invite.role})

              {user, updated_invite}
            end) do
              {:ok, {user, updated_invite}} -> {:ok, user, updated_invite}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  @doc """
  Gets an invite by token.
  """
  def get_invite_by_token(token) do
    Repo.get_by(Invite, token: token)
  end

  @doc """
  Lists invites for a project.
  """
  def list_project_invites(project_id) do
    from(i in Invite,
      where: i.project_id == ^project_id,
      order_by: [desc: i.inserted_at],
      preload: [:created_by_user]
    )
    |> Repo.all()
  end

  @doc """
  Lists pending invites for a project.
  """
  def list_pending_invites(project_id) do
    now = DateTime.utc_now()
    
    from(i in Invite,
      where: i.project_id == ^project_id and is_nil(i.used_at) and i.expires_at > ^now,
      order_by: [desc: i.inserted_at],
      preload: [:created_by_user]
    )
    |> Repo.all()
  end

  @doc """
  Deletes an invite.
  """
  def delete_invite!(invite) do
    Repo.delete!(invite)
  end

  @doc """
  Generates a secure random token for invites.
  """
  def generate_secure_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Gets the invite TTL in hours from config.
  """
  def invite_ttl_hours do
    Application.get_env(:keila, :invite_ttl_hours, 72)
  end

  @doc """
  Validates an invite token and returns the invite if valid.
  """
  def validate_invite_token(token) do
    case get_invite_by_token(token) do
      nil ->
        {:error, :not_found}

      invite ->
        cond do
          Invite.used?(invite) ->
            {:error, :already_used}

          Invite.expired?(invite) ->
            {:error, :expired}

          true ->
            {:ok, invite}
        end
    end
  end

  @doc """
  Lists all invites (for super admin use only).
  """
  def list_all_invites do
    from(i in Invite,
      order_by: [desc: i.inserted_at],
      preload: [:created_by_user, :project]
    )
    |> Repo.all()
  end
end
