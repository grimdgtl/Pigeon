defmodule Keila.Auth.Schemas.Invite do
  use Ecto.Schema
  import Ecto.Changeset
  alias Keila.Auth.User
  alias Keila.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "auth_invites" do
    field :token, :string
    field :email, :string
    field :role, :string, default: "admin"
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :metadata, :map, default: %{}

        belongs_to :project, Project
        belongs_to :created_by_user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:token, :email, :project_id, :role, :expires_at, :used_at, :metadata, :created_by_user_id])
    |> validate_required([:token, :email, :project_id, :role, :expires_at, :created_by_user_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_inclusion(:role, ["admin", "editor", "viewer"], message: "must be admin, editor, or viewer")
    |> validate_length(:token, min: 32, max: 64)
    |> unique_constraint(:token)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_user_id)
  end

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc false
  def accept_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:used_at])
    |> validate_required([:used_at])
  end

  @doc """
  Checks if the invite is valid (not used and not expired)
  """
  def valid?(invite) do
    is_nil(invite.used_at) and 
    DateTime.compare(invite.expires_at, DateTime.utc_now()) == :gt
  end

  @doc """
  Checks if the invite is expired
  """
  def expired?(invite) do
    DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt
  end

  @doc """
  Checks if the invite has been used
  """
  def used?(invite) do
    not is_nil(invite.used_at)
  end
end
