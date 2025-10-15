defmodule KeilaWeb.InviteControllerTest do
  use KeilaWeb.ConnCase, async: true
  alias Keila.Auth
  alias Keila.Auth.Invites
  alias Keila.Projects
  alias Keila.Accounts

  setup do
    # Create test data
    account = Accounts.create_account!("Test Account")
    project = Projects.create_project!(%{"name" => "Test Project", "account_id" => account.id})
    admin_user = Auth.create_user!(%{email: "admin@example.com", password: "password123"})

    # Create a valid invite
    invite_attrs = %{
      "email" => "user@example.com",
      "project_id" => project.id,
      "created_by_user_id" => admin_user.id
    }

    invite = Invites.create_invite!(invite_attrs)

    %{account: account, project: project, admin_user: admin_user, invite: invite}
  end

  describe "GET /invites/:token" do
    test "shows invite form for valid token", %{conn: conn, invite: invite} do
      conn = get(conn, Routes.invite_path(conn, :show, invite.token))
      
      assert html_response(conn, 200) =~ "Accept Invitation"
      assert html_response(conn, 200) =~ invite.email
      assert html_response(conn, 200) =~ invite.project.name
    end

    test "redirects for invalid token", %{conn: conn} do
      conn = get(conn, Routes.invite_path(conn, :show, "invalid_token"))
      
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "Invalid invitation link"
    end

    test "redirects for used invite", %{conn: conn, invite: invite} do
      # Accept the invite first
      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }
      
      {:ok, _user, _invite} = Invites.accept_invite!(invite.token, password_params)
      
      # Try to show the used invite
      conn = get(conn, Routes.invite_path(conn, :show, invite.token))
      
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "This invitation has already been used"
    end

    test "redirects for expired invite", %{conn: conn, project: project, admin_user: admin_user} do
      # Create an expired invite
      expired_invite_attrs = %{
        "email" => "expired@example.com",
        "project_id" => project.id,
        "created_by_user_id" => admin_user.id,
        "expires_at" => DateTime.add(DateTime.utc_now(), -3600) # 1 hour ago
      }

      expired_invite = Invites.create_invite!(expired_invite_attrs)
      
      conn = get(conn, Routes.invite_path(conn, :show, expired_invite.token))
      
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "This invitation has expired"
    end
  end

  describe "POST /invites/:token" do
    test "accepts a valid invite and creates user", %{conn: conn, invite: invite} do
      user_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }
      
      conn = post(conn, Routes.invite_path(conn, :accept, invite.token), user: user_params)
      
      assert redirected_to(conn) == Routes.auth_path(conn, :login)
      assert get_flash(conn, :info) =~ "Welcome to Keila! Your account has been created successfully."
    end

    test "accepts invite for existing user", %{conn: conn, invite: invite} do
      # Create existing user
      existing_user = Auth.create_user!(%{email: invite.email, password: "oldpassword123"})
      
      user_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }
      
      conn = post(conn, Routes.invite_path(conn, :accept, invite.token), user: user_params)
      
      assert redirected_to(conn) == Routes.auth_path(conn, :login)
      assert get_flash(conn, :info) =~ "Welcome to Keila! Your account has been created successfully."
    end

    test "returns error for invalid token", %{conn: conn} do
      user_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }
      
      conn = post(conn, Routes.invite_path(conn, :accept, "invalid_token"), user: user_params)
      
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "Invalid invitation link"
    end

    test "returns error for used invite", %{conn: conn, invite: invite} do
      # Accept the invite first
      password_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }
      
      {:ok, _user, _invite} = Invites.accept_invite!(invite.token, password_params)
      
      # Try to accept again
      user_params = %{
        "password" => "anotherpassword123",
        "password_confirmation" => "anotherpassword123"
      }
      
      conn = post(conn, Routes.invite_path(conn, :accept, invite.token), user: user_params)
      
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "This invitation has already been used"
    end

    test "returns error for expired invite", %{conn: conn, project: project, admin_user: admin_user} do
      # Create an expired invite
      expired_invite_attrs = %{
        "email" => "expired@example.com",
        "project_id" => project.id,
        "created_by_user_id" => admin_user.id,
        "expires_at" => DateTime.add(DateTime.utc_now(), -3600) # 1 hour ago
      }

      expired_invite = Invites.create_invite!(expired_invite_attrs)
      
      user_params = %{
        "password" => "newpassword123",
        "password_confirmation" => "newpassword123"
      }
      
      conn = post(conn, Routes.invite_path(conn, :accept, expired_invite.token), user: user_params)
      
      assert redirected_to(conn) == Routes.page_path(conn, :index)
      assert get_flash(conn, :error) =~ "This invitation has expired"
    end
  end
end
