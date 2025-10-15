import Config
require Logger
:ok = Application.ensure_started(:logger)
{:ok, _} = Application.ensure_all_started(:tls_certificate_check)

exit_from_exception = fn exception, message ->
  Logger.error(exception.message)
  Logger.error(message)
  Logger.flush()
  System.halt(1)
end

maybe_to_int = fn
  string when string not in [nil, ""] -> String.to_integer(string)
  _ -> nil
end

put_if_not_empty = fn
  enumerable, key, value when value not in [nil, ""] -> put_in(enumerable, [key], value)
  enumerable, _, _ -> enumerable
end

# ------------------------------
# Shared SMTP config builder
# ------------------------------
build_smtp_config = fn ->
  host = System.fetch_env!("MAILER_SMTP_HOST")
  from_email = System.fetch_env!("MAILER_SMTP_FROM_EMAIL")
  user =
    System.get_env("MAILER_SMTP_USERNAME") ||
      System.get_env("MAILER_SMTP_USER") ||
      from_email

  password = System.fetch_env!("MAILER_SMTP_PASSWORD")
  port = String.to_integer(System.get_env("MAILER_SMTP_PORT", "587"))

  enable_ssl = System.get_env("MAILER_ENABLE_SSL", "false") in ["true", "TRUE", "1"]
  enable_starttls = System.get_env("MAILER_ENABLE_STARTTLS", "true") in ["true", "TRUE", "1"]

  verify_mode =
    case (System.get_env("SMTP_VERIFY") || System.get_env("MAILER_TLS_VERIFY") || "peer")
         |> String.downcase() do
      "none" -> :verify_none
      _ -> :verify_peer
    end

  # Heuristika: ako se konektujemo na *.dwhost.net a SNI nije eksplicitno zadat,
  # pretpostavi da treba "mail.grim-digital.com" (po izdatom cert-u).
  sni_env =
    System.get_env("MAILER_SMTP_SNI") ||
      System.get_env("MAILER_SNI") ||
      System.get_env("SMTP_SNI")

  sni_guess =
    cond do
      is_binary(sni_env) and sni_env != "" ->
        sni_env

      String.contains?(host, "dwhost.net") ->
        "mail.grim-digital.com"

      true ->
        host
    end

  tls_versions =
    case System.get_env("MAILER_TLS_VERSIONS", "tlsv1.3,tlsv1.2") do
      v when is_binary(v) ->
        v
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn
          "tlsv1.3" -> :"tlsv1.3"
          "tlsv1.2" -> :"tlsv1.2"
          other when is_binary(other) -> String.to_atom(other)
        end)

      _ ->
        [:"tlsv1.3", :"tlsv1.2"]
    end

  auth_types =
    (System.get_env("SMTP_AUTH_TYPES") || "login")
    |> String.downcase()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn
      "plain" -> :plain
      "login" -> :login
      "cram_md5" -> :cram_md5
      other -> String.to_atom(other)
    end)

  mailer_config =
    [
      adapter: Swoosh.Adapters.SMTP,
      relay: host,
      username: user,
      password: password,
      port: port,
      auth: :always,
      auth_types: auth_types,
      from: from_email,
      # 465 => ssl: true,  587 => STARTTLS
      ssl: enable_ssl,
      tls: if(enable_starttls, do: :always, else: :never),
      tls_options: [
        server_name_indication: String.to_charlist(sni_guess),
        verify: verify_mode,
        versions: tls_versions
      ]
    ]

  {mailer_config, from_email}
end

# ============================
# PROD konfiguracija
# ============================
if config_env() == :prod do
  # Database
  try do
    db_url = System.fetch_env!("DB_URL")
    ssl = System.get_env("DB_ENABLE_SSL") in [1, "1", "true", "TRUE"]

    ssl_opts =
      []
      |> then(fn opts ->
        verify_peer? = System.get_env("DB_VERIFY_SSL_HOST", "TRUE") in [1, "1", "true", "TRUE"]
        if verify_peer?, do: Keyword.put(opts, :verify, :verify_peer), else: Keyword.put(opts, :verify, :verify_none)
      end)
      |> then(fn opts ->
        ca_cert_pem = System.get_env("DB_CA_CERT")

        cacerts =
          if ca_cert_pem not in [nil, ""] do
            ca_cert_pem
            |> :public_key.pem_decode()
            |> Enum.map(fn {_, der_or_encrypted_der, _} -> der_or_encrypted_der end)
          end

        if cacerts, do: Keyword.put(opts, :cacerts, cacerts), else: opts
      end)

    config :keila, Keila.Repo, url: db_url, ssl: ssl, ssl_opts: ssl_opts
  rescue
    e ->
      exit_from_exception.(e, """
      You must provide the DB_URL environment variable in the format:
      postgres://user:password/database
      """)
  end

  # System Mailer (SMTP)
  try do
    {mailer_config, from_email} = build_smtp_config.()
    config(:keila, Keila.Mailer, mailer_config)
    config(:keila, Keila.Auth.Emails, from_email: from_email)
  rescue
    e ->
      exit_from_exception.(e, """
      You must configure a mailer for system emails.

      Required env:
        MAILER_SMTP_HOST
        MAILER_SMTP_FROM_EMAIL
        MAILER_SMTP_PASSWORD
      Optional:
        MAILER_SMTP_USERNAME (defaults to FROM)
        MAILER_SMTP_PORT (default 587)
        MAILER_ENABLE_SSL (true for SMTPS/465)
        MAILER_ENABLE_STARTTLS (true for 587 STARTTLS)
        MAILER_TLS_VERIFY or SMTP_VERIFY (peer|none)
        MAILER_SMTP_SNI / MAILER_SNI / SMTP_SNI
        MAILER_TLS_VERSIONS (e.g. "tlsv1.3,tlsv1.2")
        SMTP_AUTH_TYPES (e.g. "login,plain")
      Original error: #{Exception.message(e)}
      """)
  end

  # Captcha
  captcha_site_key = System.get_env("CAPTCHA_SITE_KEY") || System.get_env("HCAPTCHA_SITE_KEY")
  captcha_secret_key = System.get_env("CAPTCHA_SECRET_KEY") || System.get_env("HCAPTCHA_SECRET_KEY")
  captcha_verify_url = System.get_env("CAPTCHA_VERIFY_URL") || System.get_env("CAPTCHA_URL") || System.get_env("HCAPTCHA_URL")
  captcha_script_url = System.get_env("CAPTCHA_SCRIPT_URL")

  if captcha_site_key not in [nil, ""] and captcha_secret_key not in [nil, ""] do
    captcha_provider =
      System.get_env("CAPTCHA_PROVIDER", "hcaptcha")
      |> String.downcase()
      |> case do
        "friendly_captcha" -> :friendly_captcha
        _other -> :hcaptcha
      end

    Logger.info("Using the #{captcha_provider} captcha provider")

    captcha_config =
      [
        secret_key: captcha_secret_key,
        site_key: captcha_site_key,
        provider: captcha_provider
      ]
      |> put_if_not_empty.(:verify_url, captcha_verify_url)
      |> put_if_not_empty.(:script_url, captcha_script_url)

    config :keila, KeilaWeb.Captcha, captcha_config
  else
    Logger.warning("""
    Captcha not configured.
    Keila will fall back to using hCaptcha’s staging configuration.

    To configure a captcha, use the following environment variables:

    - CAPTCHA_SITE_KEY
    - CAPTCHA_SECRET_KEY
    - CAPTCHA_VERIFY_URL (defaults...)
    - CAPTCHA_SCRIPT_URL (defaults...)
    - CAPTCHA_PROVIDER (defaults to hCaptcha)
    """)
  end

  # Secret Key Base
  try do
    secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

    live_view_salt =
      :crypto.hash(:sha384, secret_key_base <> "live_view_salt") |> Base.url_encode64()

    config(:keila, KeilaWeb.Endpoint,
      secret_key_base: secret_key_base,
      live_view: [signing_salt: live_view_salt]
    )
  rescue
    e ->
      exit_from_exception.(e, """
      You must set SECRET_KEY_BASE.

      This should be a strong secret (>=64 chars).
      One way:
      head -c 48 /dev/urandom | base64
      """)
  end

  # Hashids
  secret_key_base =
    Application.get_env(:keila, KeilaWeb.Endpoint) |> Keyword.fetch!(:secret_key_base)

  hashid_salt =
    case System.get_env("HASHID_SALT") do
      empty when empty in [nil, ""] ->
        Logger.warning("""
        You have not configured a Hashid salt. Defaulting to
        :crypto.hash(:sha256, SECRET_KEY_BASE <> "hashid_salt") |> Base.url_encode64()
        """)
        :crypto.hash(:sha256, secret_key_base <> "hashid_salt") |> Base.url_encode64()
      salt -> salt
    end

  config(:keila, Keila.Id, salt: hashid_salt)

  # Main Endpoint
  url_host = System.get_env("URL_HOST")
  url_port = System.get_env("URL_PORT") |> maybe_to_int.()
  url_schema = System.get_env("URL_SCHEMA")
  url_path = System.get_env("URL_PATH")

  url_port =
    cond do
      url_port not in [nil, ""] -> url_port
      url_schema == "https" -> 443
      true -> System.get_env("PORT") |> maybe_to_int.() || 4000
    end

  url_schema =
    cond do
      url_schema not in [nil, ""] -> url_schema
      url_port == 443 -> "https"
      true -> "http"
    end

  if url_host not in [nil, ""] do
    endpoint_url =
      [host: url_host, scheme: url_schema]
      |> put_if_not_empty.(:port, url_port)
      |> put_if_not_empty.(:path, url_path)

    config(:keila, KeilaWeb.Endpoint, url: endpoint_url)
  else
    Logger.warning("""
    You have not configured the application URL. Defaulting to http://localhost.
    """)
  end

  # File Storage
  user_content_dir = System.get_env("USER_CONTENT_DIR")
  default_user_content_dir =
    Application.get_env(:keila, Keila.Files.StorageAdapters.Local, []) |> Keyword.get(:dir)

  if user_content_dir not in [nil, ""] do
    config(:keila, Keila.Files.StorageAdapters.Local, dir: user_content_dir)
  else
    Logger.warning("""
    You have not configured a directory for user uploads.
    Default directory "#{default_user_content_dir}" will be used.
    """)
  end

  user_content_base_url = System.get_env("USER_CONTENT_BASE_URL")

  if user_content_base_url not in [nil, ""] do
    config(:keila, Keila.Files.StorageAdapters.Local, serve: false)
    config(:keila, Keila.Files.StorageAdapters.Local, base_url: user_content_base_url)
  else
    config(:keila, Keila.Files.StorageAdapters.Local, serve: true)
  end

  # Application Port
  port = System.get_env("PORT") |> maybe_to_int.()
  if not is_nil(port), do: config(:keila, KeilaWeb.Endpoint, http: [port: port])

  # Deployment toggles
  config :keila,
    registration_disabled:
      System.get_env("DISABLE_REGISTRATION") not in [nil, "", "0", "false", "FALSE"],
    sender_creation_disabled:
      System.get_env("DISABLE_SENDER_CREATION") not in [nil, "", "0", "false", "FALSE"]

  config :keila, Keila.Accounts,
    credits_enabled: System.get_env("ENABLE_QUOTAS") in [1, "1", "true", "TRUE"]

  config :keila, Keila.Billing,
    enabled: System.get_env("ENABLE_BILLING") in [1, "1", "true", "TRUE"]

  config :keila,
         :update_checks_enabled,
         System.get_env("DISABLE_UPDATE_CHECKS") not in [nil, "", "0", "false", "FALSE"]

  paddle_vendor = System.get_env("PADDLE_VENDOR")
  if paddle_vendor not in [nil, ""], do: config(:keila, Keila.Billing, paddle_vendor: paddle_vendor)

  paddle_environment = System.get_env("PADDLE_ENVIRONMENT")
  if paddle_environment not in [nil, ""], do: config(:keila, Keila.Billing, paddle_environment: paddle_environment)

  if System.get_env("DISABLE_PRECEDENCE_HEADER") in [1, "1", "true", "TRUE"] do
    config(:keila, Keila.Mailings, enable_precedence_header: false)
  end

  case System.get_env("LOG_LEVEL") do
    level when level in ["info", "error", "debug"] -> config :logger, level: String.to_existing_atom(level)
    _ -> config :logger, level: :info
  end
end

# ============================
# DEV mailer konfiguracija
# ============================
if config_env() == :dev do
  try do
    {mailer_config, from_email} = build_smtp_config.()
    config(:keila, Keila.Mailer, mailer_config)
    config(:keila, Keila.Auth.Emails, from_email: from_email)
    Logger.debug("Dev mailer configured with STARTTLS/SSL from ENV.")
  rescue
    e ->
      Logger.warning("Dev mailer not configured from ENV: #{Exception.message(e)}")
  end
end

# ============================
# TEST (kao ranije)
# ============================
if config_env() == :test do
  db_url = System.get_env("DB_URL")
  if db_url do
    db_url = db_url <> "#{System.get_env("MIX_TEST_PARTITION")}"
    config(:keila, Keila.Repo, url: db_url)
  end
end