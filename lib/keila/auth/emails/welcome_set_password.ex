defmodule Keila.Auth.Emails.WelcomeSetPassword do
  @moduledoc """
  Email template for welcome messages with password setup.
  """

  import Swoosh.Email

  def welcome_set_password(%{user: user, reset_url: reset_url}) do
    new()
    |> to(user.email)
    |> from({"Keila", "noreply@keila.io"})
    |> subject("Welcome to Keila - Set up your password")
    |> html_body(html_content(user, reset_url))
    |> text_body(text_content(user, reset_url))
  end

  defp html_content(user, reset_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Welcome to Keila</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #4f46e5; color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #4f46e5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; margin: 20px 0; }
        .footer { text-align: center; margin-top: 30px; color: #6b7280; font-size: 14px; }
        .security { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Welcome to Keila!</h1>
        </div>
        <div class="content">
          <h2>Hello #{user.email}!</h2>
          <p>Your Keila account has been created and you're ready to get started.</p>
          <p>To complete your account setup, please set up your password by clicking the button below:</p>
          <a href="#{reset_url}" class="button">Set Up Password</a>
          <div class="security">
            <strong>🔒 Security Note:</strong> This link will expire in 24 hours for your security.
          </div>
          <p>If the button doesn't work, you can copy and paste this link into your browser:</p>
          <p><a href="#{reset_url}">#{reset_url}</a></p>
          <p>Once you've set up your password, you'll be able to access all the features of your Keila account.</p>
        </div>
        <div class="footer">
          <p>This email was sent by Keila</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp text_content(user, reset_url) do
    """
    Welcome to Keila!

    Hello #{user.email}!

    Your Keila account has been created and you're ready to get started.

    To complete your account setup, please set up your password by visiting:
    #{reset_url}

    🔒 Security Note: This link will expire in 24 hours for your security.

    Once you've set up your password, you'll be able to access all the features of your Keila account.

    --
    This email was sent by Keila
    """
  end
end
