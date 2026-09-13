defmodule Smith.MixProject do
  use Mix.Project

  def project do
    [
      app: :smith,
      version: "0.1.0",
      elixir: "~> 1.18",
      name: "Smith",
      description:
        "Composable, native Elixir CAD with sketches, assemblies, and verified printable exports",
      source_url: "https://github.com/ntodd/smith",
      homepage_url: "https://hexdocs.pm/smith",
      deps: deps(),
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/ntodd/smith"},
        files: ~w(lib priv guides examples mix.exs .formatter.exs README.md CHANGELOG.md LICENSE)
      ],
      docs: [
        main: "readme",
        assets: %{"guides/images" => "guides/images", "guides/figures" => "figures"},
        source_ref: "v0.1.0",
        source_url_pattern: "https://github.com/ntodd/smith/blob/v0.1.0/%{path}#L%{line}",
        extras: [
          "README.md",
          "guides/getting-started.md",
          "guides/modeling.md",
          "guides/sketches.md",
          "guides/paths-and-shells.md",
          "guides/mechanical-parts.md",
          "guides/forming.md",
          "guides/extrusion.md",
          "guides/projection.md",
          "guides/drawings.md",
          "guides/assemblies.md",
          "guides/joints.md",
          "guides/exporting.md",
          "guides/livebook.md",
          "guides/errors-and-limits.md",
          "CHANGELOG.md",
          "LICENSE"
        ],
        groups_for_modules: [
          Modeling: [Smith, Smith.Model, Smith.Result, Smith.Error],
          Sketches: [Smith.Plane, Smith.Sketch, Smith.Path],
          Selection: [Smith.Selector],
          Internals: [Smith.Features.Hole, Smith.Assembly.Frame],
          Assemblies: [
            Smith.Assembly,
            Smith.Assembly.Result,
            Smith.Assembly.Joint,
            Smith.Assembly.Export
          ],
          Export: [Smith.Export, Smith.Mesh, Smith.Drawing],
          Livebook: [Smith.Kino]
        ]
      ]
    ]
  end

  defp deps do
    # An explicit opt-in for repository development; published consumers use Hex.
    ocex =
      case System.get_env("OCEX_PATH") do
        nil -> {:ocex, "~> 0.1.0"}
        path -> {:ocex, path: path}
      end

    [ocex, {:kino, "~> 0.19.0", optional: true}, {:ex_doc, "~> 0.40", only: :dev, runtime: false}]
  end

  def application, do: [extra_applications: [:crypto]]
end
