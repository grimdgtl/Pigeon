defmodule Keila.Repo.Migrations.AddInvitesAndUserFields do
  use Ecto.Migration

  def change do
    # Add fields to users table
    alter table(:users) do
      add :first_login_required, :boolean, default: false, null: false
      add :invited_at, :naive_datetime
    end

    # Create auth_invites table
    create table(:auth_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :email, :string, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :role, :string, default: "admin", null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :metadata, :map, default: %{}
      add :created_by_user_id, references(:users, on_delete: :delete_all), null: false
      
      timestamps(type: :utc_datetime)
    end

    # Create indexes
    create unique_index(:auth_invites, [:token])
    create index(:auth_invites, [:email])
    create index(:auth_invites, [:project_id])
    create index(:auth_invites, [:expires_at])
    create index(:auth_invites, [:used_at])
    create index(:auth_invites, [:created_by_user_id])
  end
end