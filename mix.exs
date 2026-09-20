defmodule Smith.MixProject do
  use Mix.Project

  def project do
    [
      app: :smith,
      version: "0.4.0",
      elixir: "~> 1.18",
      name: "Smith",
      description:
        "Composable, native Elixir CAD with sketches, assemblies, and verified printable exports",
      source_url: "https://github.com/ntodd/smith",
      homepage_url: "https://hexdocs.pm/smith",
      deps: deps(),
      aliases: [docs: ["run scripts/build-doc-previews.exs", "docs"]],
      package: [
        licenses: ["MIT", "OFL-1.1"],
        links: %{"GitHub" => "https://github.com/ntodd/smith"},
        files:
          ~w(lib priv guides examples skills llms.txt scripts/build-doc-previews.exs mix.exs .formatter.exs README.md CHANGELOG.md LICENSE)
      ],
      docs: [
        main: "readme",
        assets: %{
          "guides/images" => "guides/images",
          "guides/figures" => "figures",
          ".doc-preview-assets" => "preview/models",
          "priv/docs" => "preview",
          "priv/kino" => "preview/renderer"
        },
        before_closing_head_tag: %{
          html: ~s(<link rel="describedby" href="llms.txt" type="text/markdown">)
        },
        before_closing_body_tag: %{
          html: ~s(<script type="module" src="preview/docs.js"></script>)
        },
        source_ref: "v0.4.0",
        source_url_pattern: "https://github.com/ntodd/smith/blob/v0.4.0/%{path}#L%{line}",
        extras: [
          "README.md",
          "guides/getting-started.md",
          "guides/cad-basics.md",
          "guides/livebook.md",
          "guides/modeling.md",
          "guides/sketches.md",
          "guides/text.md",
          "guides/svg.md",
          "guides/mechanical-parts.md",
          "guides/extrusion.md",
          "guides/paths-and-shells.md",
          "guides/forming.md",
          "guides/projection.md",
          "guides/inspection.md",
          "guides/drawings.md",
          "guides/assemblies.md",
          "guides/joints.md",
          "guides/exporting.md",
          "guides/agent-modeling.md",
          "guides/errors-and-limits.md",
          {"examples/plate.livemd", [filename: "plate-notebook"]},
          {"examples/text.livemd", [filename: "text-notebook"]},
          {"examples/svg.livemd", [filename: "svg-notebook"]},
          {"examples/profiles.livemd", [filename: "profiles-notebook"]},
          {"examples/mechanical-parts.livemd", [filename: "mechanical-parts-notebook"]},
          {"examples/inspection.livemd", [filename: "inspection-notebook"]},
          {"examples/drawings.livemd", [filename: "drawings-notebook"]},
          {"examples/extrusion.livemd", [filename: "extrusion-notebook"]},
          {"examples/paths-and-shells.livemd", [filename: "paths-and-shells-notebook"]},
          {"examples/forming.livemd", [filename: "forming-notebook"]},
          {"examples/projection.livemd", [filename: "projection-notebook"]},
          {"examples/assembly.livemd", [filename: "assembly-notebook"]},
          {"examples/nested-assemblies.livemd", [filename: "nested-assemblies-notebook"]},
          {"examples/joints.livemd", [filename: "joints-notebook"]},
          {"examples/raspberry-pi-enclosure.livemd",
           [filename: "raspberry-pi-enclosure-notebook"]},
          {"examples/iphone-17-pro.livemd", [filename: "iphone-17-pro-notebook"]},
          {"skills/smith-cad/SKILL.md", [filename: "smith-cad-skill", title: "Smith CAD skill"]},
          "CHANGELOG.md",
          "LICENSE"
        ],
        groups_for_extras: [
          "Start here": ~r/(README|guides\/(getting-started|cad-basics|livebook))/,
          Modeling:
            ~r/guides\/(modeling|sketches|mechanical-parts|extrusion|paths-and-shells|forming|projection)\.md/,
          "Inspect and deliver": ~r/guides\/(inspection|drawings|exporting)\.md/,
          Assemblies: ~r/guides\/(assemblies|joints)\.md/,
          "Livebook lessons": ~r/examples\/(?!raspberry-pi|iphone)/,
          "Complete projects and studies": ~r/examples\/(raspberry-pi|iphone)/,
          Reference: ~r/(guides\/(agent-modeling|errors-and-limits)|skills\/|CHANGELOG|LICENSE)/
        ],
        groups_for_modules: [
          Modeling: [Smith, Smith.Model, Smith.Result, Smith.Error],
          Sketches: [
            Smith.Plane,
            Smith.Sketch,
            Smith.Path,
            Smith.Font,
            Smith.Text,
            Smith.SVG,
            Smith.SVG.Asset
          ],
          Selection: [Smith.Selector],
          Inspection: [Smith.Inspection, Smith.Measure, Smith.Render],
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
        nil -> {:ocex, "~> 0.4.0"}
        path -> {:ocex, path: path}
      end

    [ocex, {:kino, "~> 0.19.0", optional: true}, {:ex_doc, "~> 0.40", only: :dev, runtime: false}]
  end

  def application, do: [extra_applications: [:crypto], mod: {Smith.Application, []}]
end
