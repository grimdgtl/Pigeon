# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :keila, ecto_repos: [Keila.Repo]

config :keila, KeilaWeb.ContactsCsvExport, chunk_size: 100

# Invite configuration
config :keila, :invite_ttl_hours, System.get_env("INVITE_TTL_HOURS", "72") |> String.to_integer()

# Configures the endpoint
config :keila, KeilaWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: System.get_env("SECRET_KEY_BASE", "dev_secret_key_base_change_me_in_production"),
  render_errors: [view: KeilaWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Keila.PubSub,
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SALT", "dev_live_view_salt_change_me")]

# Configure file uploads and serving of files
config :keila, Keila.Files, adapter: Keila.Files.StorageAdapters.Local

config :keila, Keila.Files.StorageAdapters.Local,
  serve: true,
  dir: "./uploads"

config :esbuild,
  version: "0.12.18",
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :keila, Keila.Id,
  alphabet: "abcdefghijkmnopqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ",
  min_len: 8

config :keila, Keila.Mailings,
  # Minimum offset in seconds between current time and allowed scheduling time
  min_campaign_schedule_offset: 300,
  # Set Precedence: Bulk header
  enable_precedence_header: true

config :keila, Keila.Mailings.SenderAdapters,
  adapters: [
    Keila.Mailings.SenderAdapters.SMTP,
    Keila.Mailings.SenderAdapters.Sendgrid,
    Keila.Mailings.SenderAdapters.SES,
    Keila.Mailings.SenderAdapters.Mailgun,
    Keila.Mailings.SenderAdapters.Postmark
  ],
  shared_adapters: [
    Keila.Mailings.SenderAdapters.Shared.SES
  ]

config :keila, Keila.Accounts,
  # Disable sending quotas by default
  credits_enabled: false

config :keila, Keila.Billing,
  # Disable subscriptions by default
  enabled: false,
  paddle_vendor: "2518",
  paddle_environment: "sandbox"

# Staging configuration for hCaptcha or FriendlyCaptcha
config :keila, KeilaWeb.Captcha,
  secret_key: "0x0000000000000000000000000000000000000000",
  site_key: "10000000-ffff-ffff-ffff-000000000001",
  url: "https://hcaptcha.com/siteverify",
  provider: :hcaptcha

# Configures Elixir's Logger
config :logger, :console,
  format: "$dateT$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :keila, Oban,
  queues: [
    mailer: 50,
    mailer_scheduler: 1,
    updater: 1
  ],
  repo: Keila.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 1800},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Keila.Mailings.DeliverScheduledCampaignsWorker},
       {"* * * * *", Keila.Mailings.ScheduleWorker},
       {"0 0 * * *", Keila.Instance.UpdateCronWorker}
     ]}
  ]

# Use Timezone database
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Add tsv MIME type
config :mime, :types, %{
  "text/tab-separated-values" => ["tsv"]
}

# Configure locales
config :keila, KeilaWeb.Gettext,
  default_locale: "en",
  locales: ["de", "en", "fr"]

config :ex_cldr,
  default_backend: Keila.Cldr

# ===== Mailer (SMTP) =====
config :keila, Keila.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("MAILER_SMTP_HOST", "mailhog"),
  port: String.to_integer(System.get_env("MAILER_SMTP_PORT", "1025")),
  username: System.get_env("MAILER_SMTP_USERNAME", ""),
  password: System.get_env("MAILER_SMTP_PASSWORD", ""),
  ssl: false,
  tls: :never,
  auth: :never

# From adresa za auth mejlove (može da se prepiše env varijablom)
config :keila, Keila.Auth.Emails,
  from_email: System.get_env("MAILER_SMTP_FROM_EMAIL", "dev@localhost")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"