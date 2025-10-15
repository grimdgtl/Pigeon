defmodule Keila.OnboardingFlowsTest do
  use Keila.DataCase, async: false

  import Swoosh.TestAssertions
  import Phoenix.ConnTest
  import Plug.Conn

  alias Keila.Auth
  alias Keila.Auth.Invites
  alias Keila.Projects
  alias Keila.Accounts
  alias Keila.Repo
  alias Keila.RBAC

  setup context do
    # Set up Swoosh global mode for email testing
    :ok = Swoosh.TestAssertions.set_swoosh_global(context)
    
    # Create root group that's required for account creation
    root_group = Repo.insert!(%Auth.Group{name: "root", parent_id: nil})
    
    # Create super admin user
    {:ok, super_admin} = Auth.create_user(%{
      email: "pigeon@grim-digital.com",
      password: "password123"
    }, skip_activation_email: true)
    
    # Create super admin role if it doesn't exist
    _super_admin_role = case Repo.get_by(Auth.Role, name: "super_admin") do
      nil -> 
        {:ok, role} = Auth.create_role(%{name: "super_admin"})
        role
      role -> role
    end
    
    # Create admin role if it doesn't exist
    _admin_role = case Repo.get_by(Auth.Role, name: "admin") do
      nil -> 
        {:ok, role} = Auth.create_role(%{name: "admin"})
        role
      role -> role
    end
    
    # Create account for super admin
    {:ok, super_admin_account} = Accounts.create_account()
    
    # Add super admin to the account's group
    Auth.add_user_to_group(super_admin.id, super_admin_account.group_id)
    
    # Assign super admin role to the user
    Auth.assign_role_to_user(super_admin.id, %{account_id: super_admin_account.id, role_name: "super_admin"})
    
    # Create tenant admin user
    {:ok, tenant_admin} = Auth.create_user(%{
      email: "newsletter@dijagnoza.com", 
      password: "password123"
    }, skip_activation_email: true)
    
    # Create account and project for tenant admin
    {:ok, _account} = Accounts.create_account()
    {:ok, project} = Projects.create_project(tenant_admin.id, %{"name" => "Dijagnoza"})
    account = Accounts.get_project_account(project.id)
    Auth.assign_role_to_user(tenant_admin.id, %{account_id: account.id, role_name: "admin"})
    
    %{
      root_group: root_group,
      super_admin: super_admin,
      tenant_admin: tenant_admin,
      project: project
    }
  end

  describe "Create Admin Now flow" do
    test "creates tenant and admin user, sends welcome email with set-password link", %{super_admin: super_admin} do
      tenant_attrs = %{"name" => "Acme Corp"}
      user_attrs = %{
        "email" => "admin@acme.com",
        "password" => "temp_password",
        "password_confirmation" => "temp_password"
      }
      
      # Create tenant with admin
      {_account, project, user} = Auth.create_tenant_with_admin!(tenant_attrs, user_attrs, super_admin.id)
      
      # Verify user was created with first_login_required
      assert user.first_login_required == true
      assert user.email == "admin@acme.com"
      
      # Verify project was created
      assert project.name == "Acme Corp"
      
      # Check that welcome email was sent
      receive do
        {:email, email} ->
          assert email.subject =~ ~r/Welcome to Keila/
          assert email.to == [{"", "admin@acme.com"}]
          assert email.text_body =~ ~r/set-password/
      after
        1000 -> flunk("No email received")
      end
      
      # Verify token works for password setting
      # We can't easily extract the token from the email in this test setup,
      # but we can verify the email was sent with the correct content
    end

    test "password setting flow works end-to-end", %{super_admin: super_admin} do
      # Create tenant with admin
      tenant_attrs = %{"name" => "Test Corp"}
      user_attrs = %{
        "email" => "test@test.com",
        "password" => "temp_password",
        "password_confirmation" => "temp_password"
      }
      
      {_account, _project, user} = Auth.create_tenant_with_admin!(tenant_attrs, user_attrs, super_admin.id)
      
      # Verify user was created with first_login_required
      assert user.first_login_required == true
      
      # Issue first login token
      token = Auth.issue_first_login_token!(user.id)
      
      # Set password using token
      password_params = %{
        "password" => "new_password123",
        "password_confirmation" => "new_password123"
      }
      
      assert {:ok, updated_user} = Auth.consume_first_login_token(token, password_params)
      assert updated_user.first_login_required == false
      
      # Verify token is now invalid (single-use)
      assert {:error, :invalid_or_expired_token} = Auth.validate_first_login_token(token)
      
      # Verify user can login with new password
      assert {:ok, _user} = Auth.find_user_by_credentials(%{"email" => "test@test.com", "password" => "new_password123"})
    end
  end

  describe "Send Admin Invite flow" do
    test "creates invite and sends email with invite link", %{super_admin: super_admin, project: project} do
      # Send admin invite
      invite = Auth.send_admin_invite!(project.id, "invited@acme.com", super_admin.id, role: "admin")
      
      # Verify invite was created
      assert invite.email == "invited@acme.com"
      assert invite.project_id == project.id
      assert invite.role == "admin"
      assert is_nil(invite.used_at)
      
      # Check that invite email was sent
      receive do
        {:email, email} ->
          assert email.subject =~ ~r/invited to Keila/
          assert email.to == [{"", "invited@acme.com"}]
          assert email.text_body =~ ~r/invites/
      after
        1000 -> flunk("No email received")
      end
      
      # Verify token works for invite validation
      assert {:ok, _invite} = Invites.validate_invite_token(invite.token)
    end

    test "invite acceptance flow works end-to-end", %{super_admin: super_admin, project: project} do
      # Create invite
      invite = Auth.send_admin_invite!(project.id, "newuser@acme.com", super_admin.id, role: "admin")
      
      # Accept invite
      password_params = %{
        "password" => "new_password123",
        "password_confirmation" => "new_password123"
      }
      
      assert {:ok, user, updated_invite} = Invites.accept_invite!(invite.token, password_params)
      
      # Verify user was created
      assert user.email == "newuser@acme.com"
      assert user.first_login_required == false
      
      # Verify invite was marked as used
      assert updated_invite.used_at != nil
      
      # Verify token is now invalid
      assert {:error, :already_used} = Invites.validate_invite_token(invite.token)
      
      # Verify user can login
      assert {:ok, _user} = Auth.find_user_by_credentials(%{"email" => "newuser@acme.com", "password" => "new_password123"})
      
          # Verify user has admin role in the project
          account = Accounts.get_project_account(project.id)
          assert {:ok, :admin} = RBAC.get_user_role_in_account(user.id, account.id)
    end
  end

  describe "RBAC verification" do
    test "super admin role is correctly assigned", %{super_admin: super_admin} do
      # Verify super admin role is assigned
      assert RBAC.is_super_admin?(super_admin.id) == true
    end

        test "tenant admin role is correctly assigned", %{tenant_admin: tenant_admin, project: project} do
          # Verify tenant admin role is assigned
          account = Accounts.get_project_account(project.id)
          assert {:ok, :admin} = RBAC.get_user_role_in_account(tenant_admin.id, account.id)
          assert RBAC.is_super_admin?(tenant_admin.id) == false
        end
  end

  describe "Email content verification" do
    test "welcome email contains correct set-password link", %{super_admin: super_admin} do
      tenant_attrs = %{"name" => "Email Test Corp"}
      user_attrs = %{
        "email" => "emailtest@test.com",
        "password" => "temp_password",
        "password_confirmation" => "temp_password"
      }
      
      Auth.create_tenant_with_admin!(tenant_attrs, user_attrs, super_admin.id)
      
      # Verify email content
      receive do
        {:email, email} ->
          assert email.subject =~ ~r/Welcome to Keila/
          assert email.text_body =~ ~r/set your password/
          assert email.text_body =~ ~r/set-password/
          refute String.contains?(email.text_body, "/auth/login")
      after
        1000 -> flunk("No email received")
      end
    end

    test "invite email contains correct invite link", %{super_admin: super_admin, project: project} do
      Auth.send_admin_invite!(project.id, "invitetest@test.com", super_admin.id)
      
      # Verify email content
      receive do
        {:email, email} ->
          assert email.subject =~ ~r/invited to Keila/
          assert email.text_body =~ ~r/invited to join/
          assert email.text_body =~ ~r/invites/
          refute String.contains?(email.text_body, "/auth/login")
      after
        1000 -> flunk("No email received")
      end
    end
  end

  # Helper function to log in a user
  defp log_in_user(conn, user) do
    {:ok, token} = Auth.create_token(%{scope: "web.session", user_id: user.id})
    conn
    |> fetch_session()
    |> put_session(:token, token.key)
  end
end
