defmodule Keila.Repo.Migrations.AddUniqueConstraintToTokensKey do
  use Ecto.Migration

  def change do
    # Add unique constraint to tokens.key to prevent duplicate tokens
    create unique_index(:tokens, [:key])
  end
end
