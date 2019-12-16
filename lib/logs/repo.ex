defmodule Logs.Repo do
  use Ecto.Repo,
    otp_app: :logs,
    adapter: Ecto.Adapters.Postgres
end
