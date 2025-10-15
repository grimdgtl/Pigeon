defmodule Keila.Auth.InvitesTest do
  use Keila.DataCase, async: true
  alias Keila.Auth.Invites
  alias Keila.Auth
  alias Keila.Projects
  alias Keila.Accounts
  alias Keila.Repo

  setup do
    # Create root group that's required for account creation
    root_group = Repo.insert!(%Auth.Group{name: "root", parent_id: nil})
    %{root_group: root_group}
  end

  describe "create_invite!/1" do
    test "creates an invite with default values" do
        {:ok, _account} = Accounts.create_account()
      {:ok, user} = Auth.create_user(%{email: "admin@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(user.id, %{"name" => "Test Project"})

      attrs = %{
        "email" => "user@example.com",
        "project_id" => project.id,
        "created_by_user_id" => user.id
      }

      invite = Invites.create_invite!(attrs)

      assert invite.email == "user@example.com"
      assert invite.project_id == project.id
      assert invite.role == "admin"
      assert invite.created_by_user_id == user.id
      assert invite.token != nil
      assert String.length(invite.token) >= 32
      assert invite.expires_at > DateTime.utc_now()
      assert is_nil(invite.used_at)
    end

    test "creates an invite with custom role" do
        {:ok, _account} = Accounts.create_account()
      {:ok, user} = Auth.create_user(%{email: "admin@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(user.id, %{"name" => "Test Project"})

      attrs = %{
        "email" => "editor@example.com",
        "project_id" => project.id,
        "role" => "editor",
        "created_by_user_id" => user.id
      }

      invite = Invites.create_invite!(attrs)

      assert invite.role == "editor"
    end
  end

  describe "accept_invite!/2" do
    setup do
        {:ok, _account} = Accounts.create_account()
      {:ok, admin_user} = Auth.create_user(%{email: "admin@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(admin_user.id, %{"name" => "Test Project"})

      invite_attrs = %{
        "email" => "newuser@example.com",
        "project_id" => project.id,
        "created_by_user_id" => admin_user.id
      }

      invite = Invites.create_invite!(invite_attrs)

      %{project: project, admin_user: admin_user, invite: invite}
    end

    test "accepts a valid invite and creates user", %{invite: invite} do
      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }

      assert {:ok, user, updated_invite} = Invites.accept_invite!(invite.token, password_params)

      assert user.email == "newuser@example.com"
      assert updated_invite.used_at != nil
      assert updated_invite.id == invite.id
    end

    test "accepts invite for existing user and updates password", %{invite: invite} do
      # Create existing user
      {:ok, existing_user} = Auth.create_user(%{email: "newuser@example.com", password: "oldpassword123"})

      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }

      assert {:ok, user, updated_invite} = Invites.accept_invite!(invite.token, password_params)

      assert user.id == existing_user.id
      assert updated_invite.used_at != nil
    end

    test "returns error for used invite", %{invite: invite} do
      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }

      # Accept invite once
      {:ok, _user, _invite} = Invites.accept_invite!(invite.token, password_params)

      # Try to accept again
      assert {:error, :already_used} = Invites.accept_invite!(invite.token, password_params)
    end

    test "returns error for expired invite" do
        {:ok, _account} = Accounts.create_account()
      {:ok, admin_user} = Auth.create_user(%{email: "admin_expired@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(admin_user.id, %{"name" => "Test Project"})

      # Create expired invite
      expired_invite_attrs = %{
        "email" => "expired@example.com",
        "project_id" => project.id,
        "created_by_user_id" => admin_user.id,
        "expires_at" => DateTime.add(DateTime.utc_now(), -3600) # 1 hour ago
      }

      expired_invite = Invites.create_invite!(expired_invite_attrs)

      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }

      assert {:error, :expired} = Invites.accept_invite!(expired_invite.token, password_params)
    end

    test "returns error for non-existent invite" do
      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }

      assert {:error, :not_found} = Invites.accept_invite!("invalid_token", password_params)
    end
  end

  describe "revoke_invite!/1" do
    test "revokes a valid invite" do
        {:ok, _account} = Accounts.create_account()
      {:ok, user} = Auth.create_user(%{email: "admin_revoke@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(user.id, %{"name" => "Test Project"})

      invite_attrs = %{
        "email" => "user@example.com",
        "project_id" => project.id,
        "created_by_user_id" => user.id
      }

      invite = Invites.create_invite!(invite_attrs)

      assert {:ok, updated_invite} = Invites.revoke_invite!(invite.token)
      assert updated_invite.expires_at < DateTime.utc_now()
    end

    test "returns error for non-existent invite" do
      assert {:error, :not_found} = Invites.revoke_invite!("invalid_token")
    end
  end

  describe "validate_invite_token/1" do
    setup do
        {:ok, _account} = Accounts.create_account()
      {:ok, user} = Auth.create_user(%{email: "admin_validate@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(user.id, %{"name" => "Test Project"})

      invite_attrs = %{
        "email" => "user@example.com",
        "project_id" => project.id,
        "created_by_user_id" => user.id
      }

      invite = Invites.create_invite!(invite_attrs)

      %{invite: invite}
    end

    test "validates a valid invite token", %{invite: invite} do
      assert {:ok, validated_invite} = Invites.validate_invite_token(invite.token)
      assert validated_invite.id == invite.id
    end

    test "returns error for invalid token" do
      assert {:error, :not_found} = Invites.validate_invite_token("invalid_token")
    end

    test "returns error for used invite", %{invite: invite} do
      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }

      # Accept the invite
      {:ok, _user, _invite} = Invites.accept_invite!(invite.token, password_params)

      # Try to validate the used invite
      assert {:error, :already_used} = Invites.validate_invite_token(invite.token)
    end
  end

  describe "list_project_invites/1" do
    test "lists all invites for a project" do
        {:ok, _account} = Accounts.create_account()
      {:ok, user} = Auth.create_user(%{email: "admin_list@example.com", password: "password123"})
      {:ok, project} = Projects.create_project(user.id, %{"name" => "Test Project"})

      # Create multiple invites
      invite1_attrs = %{
        "email" => "user1@example.com",
        "project_id" => project.id,
        "created_by_user_id" => user.id
      }

      invite2_attrs = %{
        "email" => "user2@example.com",
        "project_id" => project.id,
        "created_by_user_id" => user.id
      }

      invite1 = Invites.create_invite!(invite1_attrs)
      invite2 = Invites.create_invite!(invite2_attrs)

      invites = Invites.list_project_invites(project.id)

      assert length(invites) == 2
      assert Enum.any?(invites, &(&1.id == invite1.id))
      assert Enum.any?(invites, &(&1.id == invite2.id))
    end
  end
end
