defmodule Urania.Mixfile do
  use Mix.Project

  def project do
    [app: :urania,
     version: "0.1.0",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     consolidate_protocols: false,
     name: "Urania",
     source_url: "https://github.com/codegram/urania.ex",
     homepage_url: "https://codegram.github.io/urania.ex",
     docs: [main: "readme",
            extras: ["README.md"]],
     description: description(),
     package: package(),
     deps: deps()]
  end

  def application do
    []
  end

  defp deps do
    [{:pinky, "~> 0.2.0"},
     {:ex_doc, "~> 0.14", only: :dev}]
  end

  defp description do
    """
    Efficient and elegant data access inspired by Haxl. Port of funcool's Urania for Elixir.
    """
  end

  defp package do
    [name: :urania,
     files: ["lib", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Txus Bach"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/codegram/urania.ex",
              "Docs"=> "http://hexdocs.pm/urania"}]
  end
end
