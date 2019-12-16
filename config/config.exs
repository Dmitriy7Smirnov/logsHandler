import Config

config :logs, Logs.Repo,
  database: "logs_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

  config :logs, ecto_repos: [Logs.Repo]
