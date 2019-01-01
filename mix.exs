defmodule Ane.MixProject do
  use Mix.Project

  def project do
    [
      app: :ane,
      version: "0.1.0",
      description: "A very efficient way to share mutable data with :atomics and :ets",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      name: "Ane",
      source_url: "https://github.com/gyson/ane"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 0.13", only: :dev},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: :dev, runtime: false}
    ]
  end

  def package do
    %{
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/gyson/ane"}
    }
  end
end
