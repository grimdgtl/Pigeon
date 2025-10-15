defmodule Keila.Auth do
  @moduledoc """
  Functions for authentication and authorization.

  ## Authentication
  The `Auth` module includes functions to create, modify and
  authenticate users. Users may be referenced by their ID from other
  contexts to define ownership, membership, etc.

  ### User Registration/Sign-up Flow

  1. Create a `User` by specifying an email address and an optional
     password.
     Provide a callback function for  generating the verification link.
        {:ok, user} = Auth.create_user(%{email: "foo@example.com", password: "BatteryHorseStaple"}, url_fn: &url_fn/1)

  2. The User is sent an email notification with the activation link.
     Verify the User with the provided token:
        {:ok, user} = Auth.activate_user_from_token(token)

  3. The User has now been activated. You can now use other methods
     from this module.

  ### User Management

  #### Send password reset link
      :ok = Auth.send_password_reset_link(user_id, &url_fn/1)

  #### Send login link (for passwordless login)
      :ok = Auth.send_login_link(user_id, &url_fn/1)

  #### Change user email
  This uses a token to confirm the user’s new email address. The token
  is sent to the new email address. The address change is not applied
  until `update_user_email_from_token/1` is called.

      {:ok, _token} = Auth.update_user_email(user_id, %{"email" => "new@example.com"}, &url_fn/1)

      {:ok, updated_user} = Auth.update_user_email_from_token(token)


  ## Authorization
  The second part of this module allows you to implement granular role-based authorization in your application.
  Every `User` can be part of one or several `Group`s. In each `Group`, they may have one or several `Role`s which, in turn, have one or several `Permission`s attached:function()

  ### Example
      # Create users *Alice* and *Bob*
      {:ok, alice} = Auth.create_user(%{email: "alice@example.com"})
      {:ok, bob} = Auth.create_user(%{email: "alice@example.com"})

      # Create group *Employees*
      {:ok, employees_group} = Auth.create_group(%{name: employees})
  """
   require Logger
  import Ecto.Query
  use Keila.Repo

  alias Keila.Auth.{
    Emails,
    User,
    Group,
    Role,
    Permission,
    UserGroup,
    UserGroupRole,
    Token
  }

  alias Keila.Auth.ResetToken
  alias Keila.Repo
  alias Keila.Accounts

  @type token_url_fn :: (String.t() -> String.t())

  @reset_base (System.get_env("RESET_URL_BASE") || "http://localhost:4000")

  @doc """
  Pokreće reset lozinke na osnovu email adrese.

  Ako korisnik postoji, šalje link za reset lozinke.
  Uvek vraća :ok da se ne odaje da li nalog postoji.
  """
  @spec send_password_reset(String.t()) :: :ok
  def send_password_reset(email) when is_binary(email) do
    case Repo.one(from u in User, where: u.email == ^email) do
      nil ->
        :ok

      %User{id: id} = user ->
        token = ResetToken.sign(id)
        url = "#{@reset_base}/auth/reset/#{URI.encode_www_form(token)}"
        Emails.send!(:password_reset_link, %{user: user, url: url})
        :ok
    end
  end

  defp default_url_function(token) do
    Logger.debug("No URL function given")
    token
  end

  @doc """
  Returns root group.
  """
  @spec root_group() :: Group.t()
  def root_group() do
    Group.root_query()
    |> Repo.one!()
  end

  @spec create_group(Ecto.Changeset.data()) ::
          {:ok, Group.t()} | {:error, Ecto.Changeset.t(Group.t())}
  def create_group(params) do
    params
    |> Group.creation_changeset()
    |> Repo.insert()
  end

  @spec update_group(integer(), Ecto.Changeset.data()) ::
          {:ok, Group.t()} | {:error, Ecto.Changeset.t(Group.t())}
  def update_group(id, params) do
    Repo.get(Group, id)
    |> Group.update_changeset(params)
    |> Repo.update()
  end

  @spec create_role(Ecto.Changeset.data()) :: {:ok, Role.t()} | Ecto.Changeset.t(Role.t())
  def create_role(params) do
    params
    |> Role.changeset()
    |> Repo.insert()
  end

  @spec update_role(integer, Ecto.Changeset.data()) ::
          {:ok, Role.t()} | Ecto.Changeset.t(Role.t())
  def update_role(id, params) do
    Repo.get(Role, id)
    |> Role.changeset(params)
    |> Repo.update()
  end

  @spec create_permission(Ecto.Changeset.data()) ::
          {:ok, Role.t()} | Ecto.Changeset.t(Permission.t())
  def create_permission(params) do
    params
    |> Permission.changeset()
    |> Repo.insert()
  end

  @spec update_permission(integer(), Ecto.Changeset.data()) ::
          {:ok, Permission.t()} | Ecto.Changeset.t(Permission.t())
  def update_permission(id, params) do
    Repo.get(Permission, id)
    |> Permission.changeset(params)
    |> Repo.update()
  end

  @doc """
  Creates a new Account and optionally sets its display name via the backing `Group`.

  Returns `{:ok, account}`.
  """
  @spec create_account(%{optional(:name) => String.t()}) :: {:ok, Accounts.Account.t()}
  def create_account(params \\ %{}) do
    with {:ok, account} <- Accounts.create_account() do
      case Map.get(params, :name) || Map.get(params, "name") do
        name when is_binary(name) and byte_size(name) > 0 ->
          update_group(account.group_id, %{name: name})
          {:ok, account}

        _ ->
          {:ok, account}
      end
    end
  end

  @doc """
  Lists all Users belonging to the given `account_id`.
  """
  @spec list_account_users(Accounts.Account.id()) :: [User.t()]
  def list_account_users(account_id) do
    Accounts.list_account_users(account_id)
  end

  @doc """
  Lists distinct Roles that are used within the given `account_id` group.
  """
  @spec list_roles(Accounts.Account.id()) :: [Role.t()]
  def list_roles(account_id) do
    account = Accounts.get_account(account_id)

    from(r in Role,
      join: ugr in UserGroupRole, on: ugr.role_id == r.id,
      join: ug in UserGroup, on: ug.id == ugr.user_group_id,
      where: ug.group_id == ^account.group_id,
      distinct: r.id,
      select: r
    )
    |> Repo.all()
  end

  @doc """
  Assigns a Role to a User within the given Account's group. Idempotent.

  Accepts either `role_id` or `role_name` in the second argument map.
  """
  @spec assign_role_to_user(User.id(), map()) :: :ok | {:error, Ecto.Changeset.t()}
  def assign_role_to_user(user_id, %{account_id: account_id} = args) do
    account = Accounts.get_account(account_id)
    role_id =
      case args do
        %{role_id: rid} when not is_nil(rid) -> rid
        %{role_name: rname} when is_binary(rname) ->
          Repo.one(from r in Role, where: r.name == ^rname, select: r.id)
        _ -> nil
      end

    if is_nil(role_id) do
      {:error, Ecto.Changeset.change(%User{}, %{})}
    else
      add_user_group_role(user_id, account.group_id, role_id)
    end
  end

  @doc """
  Removes a Role from a User within the given Account's group. Idempotent.
  """
  @spec remove_role_from_user(User.id(), map()) :: :ok
  def remove_role_from_user(user_id, %{account_id: account_id} = args) do
    account = Accounts.get_account(account_id)
    role_id =
      case args do
        %{role_id: rid} when not is_nil(rid) -> rid
        %{role_name: rname} when is_binary(rname) ->
          Repo.one(from r in Role, where: r.name == ^rname, select: r.id)
        _ -> nil
      end

    if is_nil(role_id) do
      :ok
    else
      remove_user_group_role(user_id, account.group_id, role_id)
    end
  end

  @doc """
  Creates a Permission and assigns it to the given Role. Optionally mark as inherited.
  """
  @spec assign_permission_to_role(map()) :: :ok
  def assign_permission_to_role(%{role_id: role_id, permission_name: permission_name} = params) do
    permission =
      Repo.get_by(Permission, name: permission_name) ||
        case create_permission(%{name: permission_name}) do
          {:ok, p} -> p
          _ -> Repo.get_by!(Permission, name: permission_name)
        end

    is_inherited = Map.get(params, :is_inherited, false)

    %Keila.Auth.RolePermission{role_id: role_id, permission_id: permission.id, is_inherited: is_inherited}
    |> Repo.insert(on_conflict: :nothing)
    :ok
  end

  @doc """
  Checks if a User has a given permission within the Account's group.
  """
  @spec user_has_permission?(User.id(), %{account_id: Accounts.Account.id(), permission: String.t()}) :: boolean()
  def user_has_permission?(user_id, %{account_id: account_id, permission: permission_name}) do
    account = Accounts.get_account(account_id)
    has_permission?(user_id, account.group_id, permission_name)
  end

  @doc """
  Adds User with given `user_id` to Group specified with `group_id`.

  This function is idempotent.
  """
  @spec add_user_to_group(integer(), integer()) :: :ok | {:error, Changeset.t()}
  def add_user_to_group(user_id, group_id) do
    %{user_id: user_id, group_id: group_id}
    |> UserGroup.changeset()
    |> idempotent_insert()
  end

  @doc """
  Removes User with given `user_id` from Group specified with `group_id`.

  This function is idempotent.
  """
  @spec remove_user_from_group(integer(), integer()) :: :ok
  def remove_user_from_group(user_id, group_id) do
    from(ug in UserGroup)
    |> where([ug], ug.user_id == ^user_id and ug.group_id == ^group_id)
    |> idempotent_delete()
  end

  @doc """
  Grants User with given `user_id` Role specified with `role_id` in Group specified with `group_id`.

  If User is not yet a member of Group, User is added to Group.

  This function is idempotent.
  """
  @spec add_user_group_role(integer(), integer(), integer()) :: :ok
  def add_user_group_role(user_id, group_id, role_id) do
    :ok = add_user_to_group(user_id, group_id)
    user_group_id = UserGroup.find(user_id, group_id) |> select([ug], ug.id) |> Repo.one()

    %{user_group_id: user_group_id, role_id: role_id}
    |> UserGroupRole.changeset()
    |> idempotent_insert()
  end

  @doc """
  Removes from User with given `user_id` Role specified with `role_id` in Group specified with `group_id`.

  User is not removed as a member of Group.

  This function is idempotent.
  """
  @spec remove_user_group_role(integer(), integer(), integer()) :: :ok
  def remove_user_group_role(user_id, group_id, role_id) do
    UserGroupRole.find(user_id, group_id, role_id)
    |> idempotent_delete()
  end

  @doc """
  Returns a list with all `Groups` the User specified with `user_id`
  has a direct membership in.
  """
  @spec list_user_groups(User.id()) :: [Group.t()]
  def list_user_groups(user_id) do
    from(g in Group)
    |> join(:inner, [g], ug in UserGroup, on: ug.group_id == g.id)
    |> where([g, ug], ug.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Returns a list of all `User`s who have a direct membership in the `Group`
  specified by `group_id`.
  """
  @spec list_group_users(Group.id()) :: [User.t()]
  def list_group_users(group_id) do
    from(g in Group)
    |> join(:inner, [g], ug in UserGroup, on: ug.group_id == g.id)
    |> where([g, ug], ug.group_id == ^group_id)
    |> join(:inner, [g, ug], u in User, on: u.id == ug.user_id)
    |> select([g, ug, u], u)
    |> Repo.all()
  end

  @doc """
  Checks if User specified with `user_id` is a direct member of Group
  specified with `group_id`. Returns `true` or `false` accordingly.
  """
  @spec user_in_group?(User.id(), Group.id()) :: boolean()
  def user_in_group?(user_id, group_id) do
    from(g in Group)
    |> join(:inner, [g], ug in UserGroup, on: ug.group_id == g.id)
    |> where([g, ug], g.id == ^group_id and ug.user_id == ^user_id)
    |> Repo.exists?()
  end

  defp idempotent_insert(changeset) do
    changeset
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, %Changeset{errors: [{_, {_, [{:constraint, :unique}, _]}}]}} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp idempotent_delete(query) do
    query
    |> Repo.delete_all()
    |> case do
      {_, nil} -> :ok
    end
  end

  @doc """
  Returns `true` if `User` with `user_id` has `Permission` specified by `permission_name` in `Group` with `group_id`
  """
  @spec has_permission?(integer(), integer(), String.t(), Keyword.t()) :: boolean
  def has_permission?(user_id, group_id, permission_name, _opts \\ []) do
    groups_with_permission_query(user_id, permission_name)
    |> where([g], g.id == ^group_id)
    |> Repo.exists?()
  end

  @spec groups_with_permission(integer(), String.t(), Keyword.t()) :: [integer()]
  def groups_with_permission(user_id, permission_name, _opts \\ []) do
    groups_with_permission_query(user_id, permission_name)
    |> Repo.all()
  end

  defp groups_with_permission_query(user_id, permission_name) do
    groups_with_direct_permission =
      from(g in Group)
      |> join(:inner, [g], ug in UserGroup, on: ug.group_id == g.id)
      |> where([g, ug], ug.user_id == ^user_id)
      |> join(:inner, [g, ug], ugr in assoc(ug, :user_group_roles))
      |> join(:inner, [g, ug, ugr], r in assoc(ugr, :role))
      |> join(:inner, [g, ug, ugr, r], p in assoc(r, :role_permissions))
      |> join(:inner, [g, ug, ugr, r, rp], p in assoc(rp, :permission))
      |> where([g, ug, ugr, r, rp, p], p.name == ^permission_name)

    groups_with_inherited_permission =
      groups_with_direct_permission
      |> where([g, ug, ugr, r, rp, p], rp.is_inherited == true)

    groups_without_inherited_permission =
      groups_with_direct_permission
      |> where([g, ug, ugr, r, rp, p], rp.is_inherited == false)

    recursion = join(Group, :inner, [g], gt in "with-inherited", on: g.parent_id == gt.id)

    cte = union_all(groups_with_inherited_permission, ^recursion)

    from({"with-inherited", Group})
    |> recursive_ctes(true)
    |> with_cte("with-inherited", as: ^cte)
    |> union(^groups_without_inherited_permission)
  end

  @doc """
  Retrieves user with given ID. If no such user exists, returns `nil`
  """
  @spec get_user(User.id()) :: User.t() | nil
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Creates a new user and sends an verification email using `Tuser.Mailings`.
  Also creates a new Account and associates user with it.

  Specify the `url_fn` callback function to generate the verification token URL.

  ## Options
   - `:skip_activation_email` - Don’t send activation email if set to `true`


  ## Example

  params = %{email: "foo@bar.com"}
  url_fn = KeilaWeb.Router.Helpers.auth_activate_url/1
  """
  @spec create_user(map(), Keyword.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t(User.t())}
  def create_user(params, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, user} <- do_create_user(params),
           {:ok, account} <- Keila.Accounts.create_account(),
           :ok <- Keila.Accounts.set_user_account(user.id, account.id) do
        unless Keyword.get(opts, :skip_activation_email) do
          url_fn = Keyword.get(opts, :url_fn, &default_url_function/1)
          send_activation_link(user.id, url_fn)
        end

        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_create_user(params) do
    params
    |> User.creation_changeset()
    |> Repo.insert()
  end

  @doc """
  Returns a list of all users, sorted by creation date.

  ## Options
  - `:paginate` - `true` or Pagination options.

  If `:pagination` is not `true` or a list of options, a list of all results is returned.
  """
  @spec list_users() :: [User.t()] | Keila.Pagination.t(User.t())
  def list_users() do
    query = from(u in User, order_by: u.inserted_at)
    Repo.all(query)
  end

  @spec list_users(keyword()) :: [User.t()] | Keila.Pagination.t(User.t())
  def list_users(opts) when is_list(opts) do
    query = from(u in User, order_by: u.inserted_at)

    case Keyword.get(opts, :paginate) do
      true -> Keila.Pagination.paginate(query)
      opts when is_list(opts) -> Keila.Pagination.paginate(query, opts)
      _ -> Repo.all(query)
    end
  end

  @doc """
  Deletes a user.
  This does not delete user project data.

  This function is idempotent and always returns `:ok`.
  """
  @spec delete_user(User.id()) :: :ok
  def delete_user(id) do
    from(u in User, where: u.id == ^id)
    |> idempotent_delete()
  end

  @doc """
  Activates user with given ID.

  Returns `{:ok, user} if successful; `:error` otherwise.
  """
  @spec activate_user(User.id()) :: {:ok, User.t()} | :error
  def activate_user(id) do
    case Repo.get(User, id) do
      user = %User{activated_at: nil} ->
        case User.activation_changeset(user) |> Repo.update() do
          {:ok, user} -> {:ok, user}
          _ -> :error
        end
    end
  end

  @doc """
  Looks up given `auth.activate` token and activates associated user.

  Returns `{:ok, user}` if successful; `:error` otherwise.
  """
  @spec activate_user_from_token(String.t()) :: {:ok, User.t()} | :error
  def activate_user_from_token(token) do
    case find_and_delete_token(token, "auth.activate") do
      token = %Token{} -> activate_user(token.user_id)
      _ -> :error
    end
  end

  @doc """
  Updates user password from params.

  ## Example
      update_user_password(user_id, %{"password" => "NewSecurePassword"})
  """
  @spec update_user_password(User.id(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t(User.t())}
  def update_user_password(id, params) do
    Repo.get(User, id)
    |> User.update_password_changeset(params)
    |> Repo.update()
  end

  @doc """
  Updates user email from params.

  The user email is not immediately updated. Instead, an `auth.udpate_email`
  token is generated and sent via email.

  Only once this token is confirmed via `update_user_email_from_token/1` is the
  new email address persisted.

  Returns `{:ok, user}` if new email is identical to current email;
  `{:ok, token}` if the token was created and sent out via email;
  `{:error, changeset}` if the change was invalid.

  ## Example
      update_user_password(user_id, %{"email" => "new@example.com"})
  """
  @spec update_user_email(User.id(), %{:email => String.t()}, token_url_fn) ::
          {:ok, Token.t()} | {:ok, User.t()} | {:error, Changeset.t(User.t())}
  def update_user_email(id, params, url_fn \\ &default_url_function/1) do
    user = Repo.get(User, id)
    changeset = User.update_email_changeset(user, params)

    if changeset.valid? do
      email = Changeset.get_change(changeset, :email)

      if not is_nil(email) do
        {:ok, token} =
          create_token(%{user_id: user.id, scope: "auth.update_email", data: %{email: email}})

        Emails.send!(:update_email, %{user: user, url: url_fn.(token.key)})
        {:ok, token}
      else
        {:ok, user}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Looks up and deletes given `auth.update_email` token and updates associated
  user email address.

  Returns `{:ok, user}` if successful; `:error` otherwise.
  """
  @spec update_user_email_from_token(String.t()) ::
          {:ok, User.t()} | {:error, Changeset.t()} | :error
  def update_user_email_from_token(token) do
    case find_and_delete_token(token, "auth.update_email") do
      token = %Token{} ->
        user = Repo.get(User, token.user_id)
        params = %{email: token.data["email"]}
        Repo.update(User.update_email_changeset(user, params))

      _ ->
        :error
    end
  end

  @doc """
  Returns `User` with given `email` or `nil` if no such `User` exists.
  """
  @spec find_user_by_email(String.t()) :: User.t() | nil
  def find_user_by_email(email) when is_binary(email) do
    Repo.one(from(u in User, where: u.email == ^email))
  end

  def find_user_by_email(_), do: nil


  @doc """
  Returns `User` with given credentials or `nil` if no such `User` exists.

  ## Example

  find_user_by_credentials(%{"email" => "foo@bar.com", password: "BatteryHorseStaple"})
  # => %User{}
  """
  @spec find_user_by_credentials(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t(User.t())}
  def find_user_by_credentials(params) do
    user = find_user_by_email(params["email"] || params[:email]) || %User{}

    case User.validate_password_changeset(user, params) do
      %{valid?: true} -> {:ok, user}
      changeset -> Changeset.apply_action(changeset, :update)
    end
  end

  @doc """
  Updates the `given_name` and `family_name` properites of a given `User`.
  """
  @spec update_user_name(User.id(), map()) :: {:ok, User.t()} | {:error, Changeset.t(User.t())}
  def update_user_name(id, params) do
    id
    |> get_user()
    |> User.update_name_changeset(params)
    |> Repo.update()
  end

  @spec set_user_locale(User.id(), String.t()) ::
          {:ok, User.t()} | {:error, Changeset.t(User.t())}
  def set_user_locale(id, locale) do
    id
    |> get_user()
    |> User.update_locale_changeset(%{locale: locale})
    |> Repo.update()
  end

  @doc """
  Creates a token for given `scope` and `user_id`.

  `:expires_at` may be specified to change the default expiration of one day.
  `:data` may be specified to store JSON data alongside the token.
  """
  @spec create_token(%{
          :scope => binary,
          :user_id => User.id(),
          optional(:data) => map(),
          optional(:expires_at) => DateTime.t()
        }) :: {:ok, Token.t()} | {:error, Ecto.Changeset.t(Token.t())}
  def create_token(params) do
    Token.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Finds and returns `Token` specified by `key` and `scope`. Returns `nil` if no such `Token` exists.
  """
  @spec find_token(String.t(), String.t()) :: Token.t() | nil
  def find_token(key, scope) do
    Token.find_token_query(key, scope)
    |> Repo.one()
  end

  @doc """
  Finds, deletes, and returns `Token` specified by `key` and `scope`. Returns `nil` if no such `Token` exists.

  Use this instead of `find_token/2` when you want to ensure a token can only be used once.
  """
  @spec find_and_delete_token(String.t(), String.t()) :: Token.t() | nil
  def find_and_delete_token(key, scope) do
    Token.find_token_query(key, scope)
    |> select([t], t)
    |> Repo.delete_all(returning: :all)
    |> case do
      {0, _} -> nil
      {1, [token]} -> token
    end
  end

  # TODO: The API Key functions should probably be extracted to a different module
  #       because they make assumptions about other domains and don't fit well
  #        within the Auth module
  @doc """
  Creates new API key for given User and Project.

  API Keys are Auth Tokens with the scope `"api"`.
  """
  @spec create_api_key(Keila.Auth.User.id(), Keila.Projects.Project.id(), String.t()) ::
          {:ok, Token.t()}
  def create_api_key(user_id, project_id, name \\ nil) do
    create_token(%{
      scope: "api",
      user_id: user_id,
      data: %{"project_id" => project_id, "name" => name},
      expires_at: ~U[9999-12-31 23:59:00Z]
    })
  end

  @doc """
  Lists all API keys for given User and Project.
  """
  @spec get_user_project_api_keys(Keila.Auth.User.id(), Keila.Projects.Project.id()) :: [
          Token.t()
        ]
  def get_user_project_api_keys(user_id, project_id) do
    from(t in Token,
      where: t.user_id == ^user_id and fragment("?->>?", t.data, "project_id") == ^project_id,
      order_by: [desc: t.inserted_at]
    )
    |> Keila.Repo.all()
  end

  @doc """
  Finds and returns Token for given API key. Returns `nil` if Token doesn’t exist.
  """
  @spec find_api_key(String.t()) :: Token.t() | nil
  def find_api_key(key) do
    find_token(key, "api")
  end

  @doc """
  Deletes given API key.

  This function is idempotent and always returns `:ok`.
  """
  @spec delete_project_api_key(Keila.Projects.Project.id(), Token.id()) :: :ok
  def delete_project_api_key(project_id, token_id) do
    from(t in Token,
      where: t.id == ^token_id and fragment("?->>?", t.data, "project_id") == ^project_id
    )
    |> Keila.Repo.delete_all()

    :ok
  end

  @doc """
  Sends an email with the activation link to the given User.
  """
  @spec send_activation_link(User.id(), token_url_fn) :: :ok
  def send_activation_link(id, url_fn \\ &default_url_function/1) do
    user = Repo.get(User, id)

    if user.activated_at == nil do
      {:ok, token} = create_token(%{scope: "auth.activate", user_id: user.id})
      Emails.send!(:activate, %{user: user, url: url_fn.(token.key)})
    end

    :ok
  end

  @doc """
  Sends an email with a password reset token to given User.
  
  Verify the token with `find_and_delete_token("auth.reset", token_key)`
  """
  @spec send_password_reset_link(User.id(), token_url_fn) :: :ok
  def send_password_reset_link(id, url_fn \\ &default_url_function/1) do
    user = Repo.get(User, id)
    {:ok, token} = create_token(%{scope: "auth.reset", user_id: user.id})
    Emails.send!(:password_reset_link, %{user: user, url: url_fn.(token.key)})
    :ok
  end

  @doc """
  Menja lozinku na osnovu reset tokena i postavlja novu lozinku.
  
  Vraća :ok ili {:error, reason}.
  """
  @spec reset_password_from_token(String.t(), String.t()) :: :ok | {:error, term()}
  def reset_password_from_token(token_key, new_password) when is_binary(new_password) do
    case find_and_delete_token(token_key, "auth.reset") do
      %Token{user_id: user_id} ->
        case update_user_password(user_id, %{"password" => new_password}) do
          {:ok, _user} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
  
      _ ->
        {:error, :invalid_or_expired_token}
    end
  end

  @doc """
  Sends an email with a login token to given User.

  This can be useful for implementing a "magic link" login.

  Verify the token with `find_and_delete_token("auth.login", token_key)`
  """
  @spec send_login_link(User.id(), token_url_fn) :: :ok
  def send_login_link(id, url_fn \\ &default_url_function/1) do
    user = Repo.get(User, id)
    {:ok, token} = create_token(%{scope: "auth.login", user_id: user.id})
    Emails.send!(:login_link, %{user: user, url: url_fn.(token.key)})
    :ok
  end

  defp build_reset_url(token_key) do
    base = System.get_env("RESET_URL_BASE") || "http://localhost:4000"
    "#{base}/auth/reset/#{URI.encode_www_form(token_key)}"
  end

  def reset_password(user_id, new_password) when byte_size(new_password) >= 10 do
    alias Keila.Auth.User
    alias Keila.Repo

    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user ->
        changeset = User.update_password_changeset(user, %{password: new_password})
        case Repo.update(changeset) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def reset_password(_, _), do: {:error, :weak_password}

  # ============================================================================
  # TENANT MANAGEMENT AND INVITES
  # ============================================================================

  @doc """
  Creates a new tenant (Account/Group/Project) with an admin user.
  This is used for the "Create Admin Now" flow.
  """
  def create_tenant_with_admin!(tenant_attrs, user_attrs, created_by_user_id) do
    alias Keila.Accounts
    alias Keila.Projects
    alias Keila.Auth.Emails

    case Repo.transaction(fn ->
      # Create the account/group
      {:ok, account} = Accounts.create_account()

      # Create the project
      project_attrs = %{
        "name" => tenant_attrs["name"]
      }
      {:ok, project} = Projects.create_project(created_by_user_id, project_attrs)

      # Create the admin user
      user_attrs = 
        user_attrs
        |> Map.put("first_login_required", true)
        |> Map.put("email", user_attrs["email"])

      {:ok, user} = create_user(user_attrs, skip_activation_email: true)

      # Assign admin role to the user in the project's group
      project_account = Accounts.get_project_account(project.id)
      assign_role_to_user(user.id, %{account_id: project_account.id, role_name: "admin"})

      {account, project, user}
    end) do
      {:ok, {account, project, user}} -> 
        # Send welcome email with first login token (outside transaction)
        token = issue_first_login_token!(user.id)
        welcome_url = build_first_login_url(token)
        Emails.send!(:welcome_set_password, %{user: user, reset_url: welcome_url})
        {account, project, user}
      {:error, reason} -> raise "Failed to create tenant: #{inspect(reason)}"
    end
  end

  @doc """
  Sends an admin invite for a tenant.
  This is used for the "Send Admin Invite" flow.
  """
  def send_admin_invite!(tenant_id, email, created_by_user_id, opts \\ []) do
    alias Keila.Auth.Invites
    alias Keila.Projects

    role = Keyword.get(opts, :role, "admin")

    # Get the project to ensure it exists
    project = Projects.get_project(tenant_id)

    # Create the invite
    invite_attrs = %{
      "email" => email,
      "project_id" => project.id,
      "role" => role,
      "created_by_user_id" => created_by_user_id
    }

    invite = Invites.create_invite!(invite_attrs)

    # Send the invite email
    invite_url = build_invite_url(invite.token)
    Emails.send!(:invite_admin, %{
      email: email,
      project_name: project.name,
      invite_url: invite_url,
      expires_at: invite.expires_at
    })

    invite
  end

  @doc """
  Creates a user with the given attributes.
  """
  def create_user!(attrs) do
    %User{}
    |> User.creation_changeset(attrs)
    |> Repo.insert!()
  end

  defp build_invite_url(token) do
    base = System.get_env("INVITE_URL_BASE") || "http://localhost:4000"
    "#{base}/invites/#{URI.encode_www_form(token)}"
  end

  defp build_first_login_url(token) do
    base = System.get_env("INVITE_URL_BASE") || "http://localhost:4000"
    "#{base}/set-password/#{URI.encode_www_form(token)}"
  end

  @doc """
  Issues a first login token for a user who needs to set their password.
  """
  def issue_first_login_token!(user_id) do
    {:ok, token} = create_token(%{scope: "auth.first_login", user_id: user_id})
    token.key
  end

  @doc """
  Validates a first login token and returns the user if valid.
  """
  def validate_first_login_token(token_key) do
    case find_token(token_key, "auth.first_login") do
      %Token{user_id: user_id} ->
        user = get_user(user_id)
        if user && user.first_login_required do
          {:ok, user}
        else
          {:error, :invalid_or_expired_token}
        end
      nil ->
        {:error, :invalid_or_expired_token}
    end
  end

  @doc """
  Consumes a first login token by setting the user's password and marking first login as complete.
  """
  def consume_first_login_token(token_key, password_params) do
    case validate_first_login_token(token_key) do
      {:ok, user} ->
        case user
             |> User.update_password_changeset(password_params)
             |> Repo.update() do
          {:ok, updated_user} ->
            # Mark first login as no longer required
            updated_user
            |> User.changeset(%{first_login_required: false})
            |> Repo.update()
            |> case do
              {:ok, final_user} ->
                # Delete the token to make it single-use
                find_and_delete_token(token_key, "auth.first_login")
                {:ok, final_user}
              {:error, changeset} ->
                {:error, changeset}
            end

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end