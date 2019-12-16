defmodule Logs.Repo.Migrations.CreateLogs do
  use Ecto.Migration

  def change do
    create table(:logs) do
      add :app, :string
      add :component, :string
      add :branch, :string
      add :version, :integer
      add :level, :integer
      add :msg, :string
    end
  end
end
