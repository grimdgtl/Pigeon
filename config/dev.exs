import Config

# --- DB (Docker dev) ---
# Kači se na Postgres iz docker-compose.dev.yml (service: db)
config :keila, Keila.Repo,
  # možeš i url: System.get_env("DB_URL"), ali ovako je eksplicitno
  username: "keila",
  password: "devpass",
  database: "keila",
  hostname: "db",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# U dev-u želimo migracije
config :keila, skip_migrations: false

# --- Endpoint (slušaj na svim interfejsima da bi radio localhost:4000) ---
config :keila, KeilaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    npx: [
      "tailwindcss",
      "--input=css/app.scss",
      "--output=../priv/static/css/app.css",
      "--postcss",
      "--watch",
      cd: Path.expand("../assets", __DIR__)
    ],
    npx: [
      "cpx",
      "static/**",
      "../priv/static",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :keila, Keila.Mailings.SenderAdapters,
  adapters: [
    Keila.Mailings.SenderAdapters.SMTP,
    Keila.Mailings.SenderAdapters.Sendgrid,
    Keila.Mailings.SenderAdapters.SES,
    Keila.Mailings.SenderAdapters.Mailgun,
    Keila.Mailings.SenderAdapters.Postmark,
    Keila.Mailings.SenderAdapters.Local
  ],
  shared_adapters: [
    Keila.Mailings.SenderAdapters.Shared.SES,
    Keila.Mailings.SenderAdapters.Shared.Local
  ]

# Watch static and templates for browser reloading.
config :keila, KeilaWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/keila_web/(live|views)/.*(ex)$",
      ~r"lib/keila_web/templates/.*(eex|heex)$"
    ]
  ]

# Dev logger (čist output)
config :logger, :console, format: "[$level] $message\n"

# Veći stacktrace u dev-u
config :phoenix, :stacktrace_depth, 20

# Brži dev build (plugs u runtime-u)
config :phoenix, :plug_init_mode, :runtime

# Lokalni mail adapter (MailHog u compose-u)
config :keila, Keila.Mailer, adapter: Swoosh.Adapters.Local

# Omogući kredite u dev-u
config :keila, Keila.Accounts, credits_enabled: true