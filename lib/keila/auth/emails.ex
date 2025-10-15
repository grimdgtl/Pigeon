defmodule Keila.Auth.Emails do
  import Swoosh.Email
  # Use Web Gettext backend without importing the module twice
  use Gettext, backend: KeilaWeb.Gettext

  @spec send!(atom(), map()) :: term() | no_return()
  def send!(email, params) do
    email
    |> build(params)
    |> Keila.Mailer.deliver!()
  end

  @spec build(:activate, %{url: String.t(), user: Keila.Auth.User.t()}) :: term() | no_return()
  def build(:activate, %{user: user, url: url}) do
    new()
    |> from({"Keila", system_from_email()})
    |> subject(dgettext("auth", "Please Verify Your Account"))
    |> to(user.email)
    |> text_body(
      dgettext(
        "auth",
        """
        Welcome to Keila,

        please confirm your new account by visiting the following link:

        %{url}

        If you weren’t trying to create an account, simply ignore this message.
        """,
        url: url
      )
    )
  end

  @spec build(:update_email, %{url: String.t(), user: Keila.Auth.User.t()}) ::
          term() | no_return()
  def build(:update_email, %{user: user, url: url}) do
    new()
    |> from({"Keila", system_from_email()})
    |> subject(dgettext("auth", "Please Verify Your Email"))
    |> to(user.email)
    |> text_body(
      dgettext(
        "auth",
        """
        Hey there,

        please confirm your new email address by visiting the following link:

        %{url}

        If you weren’t trying to change your email address, simply ignore this message.
        """,
        url: url
      )
    )
  end

  @spec build(:password_reset_link, %{url: String.t(), user: Keila.Auth.User.t()}) ::
          term() | no_return()
  def build(:password_reset_link, %{user: user, url: url}) do
    new()
    |> subject(dgettext("auth", "Your Account Reset Link"))
    |> to(user.email)
    |> from({"Keila", system_from_email()})
    |> text_body(
      dgettext(
        "auth",
        """
        Hey there,

        you have requested a password reset for your Keila account.

        You can set a new password by visiting the following link:

        %{url}

        If you weren’t trying to reset your password, simply ignore this message.
        """,
        url: url
      )
    )
  end

  @spec build(:login_link, %{url: String.t(), user: Keila.Auth.User.t()}) :: term() | no_return()
  def build(:login_link, %{user: user, url: url}) do
    new()
    |> subject(dgettext("auth", "Your Login Link"))
    |> to(user.email)
    |> from({"Keila", system_from_email()})
    |> text_body(
      dgettext(
        "auth",
        """
        Hey there,

        you can login to Keila with the following link:

        %{url}

        If you haven’t requested a login, simply ignore this message.
        """,
        url: url
      )
    )
  end

  @spec build(:welcome_set_password, %{user: Keila.Auth.User.t(), reset_url: String.t()}) ::
          term() | no_return()
  def build(:welcome_set_password, %{user: user, reset_url: reset_url}) do
    new()
    |> subject(dgettext("auth", "Welcome to Keila - Set up your password"))
    |> to(user.email)
    |> from({"Keila", system_from_email()})
    |> text_body(
      dgettext(
        "auth",
        """
        Welcome to Keila!

        Hello %{email}!

        Your account has been created. Please set your password by visiting the following link:
        %{url}

        This link will expire shortly.

        If you have any questions, please contact support.
        """,
        email: user.email,
        url: reset_url
      )
    )
  end

  @spec build(:invite_admin, %{email: String.t(), project_name: String.t(), invite_url: String.t(), expires_at: DateTime.t()}) ::
          term() | no_return()
  def build(:invite_admin, %{email: email, project_name: project_name, invite_url: invite_url, expires_at: expires_at}) do
    new()
    |> subject(dgettext("auth", "You're invited to Keila - %{project_name}", project_name: project_name))
    |> to(email)
    |> from({"Keila", system_from_email()})
    |> text_body(
      dgettext(
        "auth",
        """
        You're invited to Keila - %{project_name}

        Welcome to %{project_name}!

        You've been invited to join Keila as an administrator for the project "%{project_name}".

        To accept the invitation and set your password, please visit the following link:
        %{url}

        This invitation will expire on %{expires_at}.

        If you have any questions, please contact support.
        """,
        project_name: project_name,
        url: invite_url,
        expires_at: DateTime.to_string(expires_at)
      )
    )
  end

  defp system_from_email() do
    Application.get_env(:keila, __MODULE__) |> Keyword.fetch!(:from_email)
  end
end