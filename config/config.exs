import Config

config :logs, Logs.Repo,
  ecto_repos: [Logs.Repo],
  database: "logs_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :logger, level: :info
