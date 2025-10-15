defmodule Keila.Auth.Emails.InviteAdmin do
  @moduledoc """
  Email template for admin invites.
  """

  import Swoosh.Email

  def invite_admin(%{email: email, project_name: project_name, invite_url: invite_url, expires_at: expires_at}) do
    new()
    |> to(email)
    |> from({"Keila", "noreply@keila.io"})
    |> subject("You're invited to Keila - #{project_name}")
    |> html_body(html_content(project_name, invite_url, expires_at))
    |> text_body(text_content(project_name, invite_url, expires_at))
  end

  defp html_content(project_name, invite_url, expires_at) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>You're invited to Keila</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #4f46e5; color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #4f46e5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; margin: 20px 0; }
        .footer { text-align: center; margin-top: 30px; color: #6b7280; font-size: 14px; }
        .expiry { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 6px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>You're invited to Keila</h1>
        </div>
        <div class="content">
          <h2>Welcome to #{project_name}!</h2>
          <p>You've been invited to join <strong>#{project_name}</strong> as an administrator on Keila.</p>
          <p>Click the button below to accept your invitation and set up your account:</p>
          <a href="#{invite_url}" class="button">Accept Invitation</a>
          <div class="expiry">
            <strong>⏰ This invitation expires on #{format_datetime(expires_at)}</strong>
          </div>
          <p>If the button doesn't work, you can copy and paste this link into your browser:</p>
          <p><a href="#{invite_url}">#{invite_url}</a></p>
          <p>If you didn't expect this invitation, you can safely ignore this email.</p>
        </div>
        <div class="footer">
          <p>This email was sent by Keila</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp text_content(project_name, invite_url, expires_at) do
    """
    You're invited to Keila - #{project_name}

    Welcome to #{project_name}!

    You've been invited to join #{project_name} as an administrator on Keila.

    To accept your invitation and set up your account, visit:
    #{invite_url}

    ⏰ This invitation expires on #{format_datetime(expires_at)}

    If you didn't expect this invitation, you can safely ignore this email.

    --
    This email was sent by Keila
    """
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.replace("T", " at ")
    |> String.replace("Z", " UTC")
  end
end
