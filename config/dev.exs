import Config

# --- DB (DevContainer) ---
# Kači se na Postgres iz .devcontainer/docker-compose.yml (service: db)
config :keila, Keila.Repo,
  username: "postgres",
  password: "postgres",
  database: "app",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# U dev-u želimo migracije
config :keila, skip_migrations: false

# --- Endpoint (slušaj na svim interfejsima da bi radio localhost:4000) ---
config :keila, KeilaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4001"))],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  secret_key_base:
    "Jzq3cQ2c4T1bYqv8w3JcTjv6Vtq1gJ4C1b8yQ2xU9mA7pL2kS9nD3fG6hM9rT2wX7yZ1vB4kN6sM8pR2tU5vX8zC1dF3gH6",
  live_view: [signing_salt: "dev_signing_salt_123"],
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
    Keila.Mailings.SenderAdapters.Postmark
  ],
  shared_adapters: [
    Keila.Mailings.SenderAdapters.Shared.SES
  ]

# --- SMTP podešavanje ---
# --- SMTP podešavanje za Pigeon ---
config :keila, Keila.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("MAILER_SMTP_HOST", "localhost"),
  username: System.get_env("MAILER_SMTP_USERNAME", ""),
  password: System.get_env("MAILER_SMTP_PASSWORD", ""),
  port: String.to_integer(System.get_env("MAILER_SMTP_PORT", "1025")),
  ssl: false,
  tls: :never,
  auth: :never,
  from: System.get_env("MAILER_SMTP_FROM_EMAIL", "dev@localhost")

# Watch static and templates for browser reloading.
config :keila, KeilaWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"lib/keila_web/(live|views|controllers|components)/.*(ex)$",
      ~r"lib/keila_web/templates/.*(eex|heex)$",
      ~r"lib/keila/.*(ex)$",
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"assets/.*(js|css|scss|png|jpg|svg)$"
    ]
  ]

# Dev logger (čist output)
config :logger, :console, format: "[$level] $message\n"

# Veći stacktrace u dev-u
config :phoenix, :stacktrace_depth, 20

# Brži dev build (plugs u runtime-u)
config :phoenix, :plug_init_mode, :runtime

# Omogući kredite u dev-u
config :keila, Keila.Accounts, credits_enabled: true