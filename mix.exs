defmodule Exparic.MixProject do
  use Mix.Project

  def project do
    [
      app: :exparic,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
    ]
  end

  defp deps do
    [
      {:floki, "~> 0.20.0"},
      {:yaml_elixir, "~> 2.1"},
      {:httpoison, "~> 1.5"},
      {:stream_data, "~> 0.1", only: :test},
    ]
  end
end
