defmodule RobinahsShop.MixProject do
  use Mix.Project

  def project do
    [
      app: :robinahs_shop,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application,
    do: [
      mod: {RobinahsShop.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]

  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22.4"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:floki, "~> 0.38", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.deploy"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["assets.copy", "phx.digest"]
    ]
  end
end

defmodule Mix.Tasks.Assets.Copy do
  use Mix.Task
  @shortdoc "Copy version-matched browser clients without a Node toolchain"
  def run(_) do
    File.mkdir_p!("priv/static/assets")

    for {source, target} <- [
          {"deps/phoenix/priv/static/phoenix.mjs", "phoenix.mjs"},
          {"deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js",
           "phoenix_live_view.mjs"},
          {"assets/js/app.js", "app.js"},
          {"assets/css/app.css", "app.css"}
        ],
        do: File.cp!(source, Path.join("priv/static/assets", target))
  end
end
