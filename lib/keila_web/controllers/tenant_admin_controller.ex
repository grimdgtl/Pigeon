defmodule KeilaWeb.TenantAdminController do
  use KeilaWeb, :controller
  alias Keila.Auth
  alias Keila.Projects
  alias Keila.Auth.Invites

  defmodule TenantForm do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name, :string
      # which onboarding flow to use
      field :onboarding_flow, Ecto.Enum, values: [:create_admin_now, :send_admin_invite], default: :create_admin_now
      # virtual inputs for each flow:
      field :admin_email, :string, virtual: true
      field :invite_email, :string, virtual: true
    end

    def changeset(struct \\ %__MODULE__{}, attrs \\ %{}) do
      struct
      |> cast(attrs, [:name, :onboarding_flow, :admin_email, :invite_email])
      |> validate_required([:name, :onboarding_flow])
    end
  end

  def index(conn, _params) do
    tenants = list_all_tenants()
    render(conn, "index.html", tenants: tenants)
  end

  defp list_all_tenants do
    import Ecto.Query
    alias Keila.Repo
    alias Keila.Projects.Project

    Repo.all(
      from p in Project,
        preload: [:account, :group]
    )
  end

  def new(conn, _params) do
    changeset = TenantForm.changeset(%TenantForm{}, %{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"tenant" => params}) do
    cs = TenantForm.changeset(%TenantForm{}, params)

    with {:valid, true} <- {:valid, cs.valid?},
         form <- Ecto.Changeset.apply_changes(cs)
    do
      case form.onboarding_flow do
        :create_admin_now ->
          # expects: name, admin_email
          case Auth.create_tenant_with_admin!(%{"name" => form.name}, %{"email" => form.admin_email}, current_user_id(conn)) do
            {account, project, user} ->
              conn
              |> put_flash(:info, "Tenant '#{account.name}' created successfully with admin user '#{user.email}'")
              |> redirect(to: Routes.tenant_admin_path(conn, :show, project.id))

            {:error, reason} ->
              conn
              |> put_flash(:error, "Failed to create tenant: #{inspect(reason)}")
              |> render("new.html", changeset: cs)
          end

        :send_admin_invite ->
          # expects: name, invite_email
          case Auth.create_tenant_with_admin!(%{"name" => form.name}, %{}, current_user_id(conn)) do
            {_account, project, _user} ->
              case Auth.send_admin_invite!(project.id, form.invite_email, current_user_id(conn), role: "admin") do
                {:error, reason} ->
                  conn
                  |> put_flash(:error, "Failed to send invite: #{inspect(reason)}")
                  |> render("new.html", changeset: cs)

                _invite ->
                  conn
                  |> put_flash(:info, "Tenant created and invite sent to '#{form.invite_email}'")
                  |> redirect(to: Routes.tenant_admin_path(conn, :show, project.id))
              end

            {:error, reason} ->
              conn
              |> put_flash(:error, "Failed to create tenant: #{inspect(reason)}")
              |> render("new.html", changeset: cs)
          end
      end
    else
      {:valid, false} ->
        render(conn, "new.html", changeset: cs)
    end
  end

  def show(conn, %{"id" => project_id}) do
        project = Projects.get_project(project_id)
    invites = Invites.list_project_invites(project_id)
    
    render(conn, "show.html", project: project, invites: invites)
  end

  def create_admin(conn, %{"project_id" => project_id, "user" => user_params}) do
        project = Projects.get_project(project_id)
    
    case Auth.create_tenant_with_admin!(%{"name" => project.name}, user_params, conn.assigns.current_user.id) do
      {_account, _project, user} ->
        conn
        |> put_flash(:info, "Admin user '#{user.email}' created successfully")
        |> redirect(to: Routes.tenant_admin_path(conn, :show, project_id))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create admin user: #{inspect(reason)}")
        |> redirect(to: Routes.tenant_admin_path(conn, :show, project_id))
    end
  end

  def send_invite(conn, %{"project_id" => project_id, "invite" => invite_params}) do
    _project = Projects.get_project(project_id)
    
    case Auth.send_admin_invite!(project_id, invite_params["email"], conn.assigns.current_user.id, 
           role: invite_params["role"] || "admin") do
      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to send invite: #{inspect(reason)}")
        |> redirect(to: Routes.tenant_admin_path(conn, :show, project_id))

      _invite ->
        conn
        |> put_flash(:info, "Invite sent to '#{invite_params["email"]}'")
        |> redirect(to: Routes.tenant_admin_path(conn, :show, project_id))
    end
  end

  def revoke_invite(conn, %{"token" => token}) do
    case Invites.revoke_invite!(token) do
      {:ok, _invite} ->
        conn
        |> put_flash(:info, "Invite revoked successfully")
        |> redirect(to: Routes.tenant_admin_path(conn, :index))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invite not found")
        |> redirect(to: Routes.tenant_admin_path(conn, :index))
    end
  end

  defp current_user_id(conn), do: conn.assigns.current_user.id

end
