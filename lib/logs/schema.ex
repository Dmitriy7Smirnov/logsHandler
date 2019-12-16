defmodule Logs.Log do
  use Ecto.Schema

  schema "logs" do
    field :app, :string
    field :component, :string
    field :branch, :string
    field :version, :integer
    field :level, :integer
    field :msg, :string
  end
end
