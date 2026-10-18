[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "mix.exs",
    ".formatter.exs",
    "config/**/*.exs",
    "lib/**/*.ex",
    "lib/**/*.heex",
    "priv/repo/**/*.exs",
    "test/**/*.exs",
    "test/**/*.ex"
  ]
]
