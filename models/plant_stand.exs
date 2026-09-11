# OCEX_PATH is an optional development override; normal runs resolve OCEx from Hex.
ocex =
  case System.get_env("OCEX_PATH") do
    nil -> []
    directory -> [{:ocex, path: Path.expand(directory), override: true}]
  end

Mix.install([{:smith, path: Path.expand("..", __DIR__)}] ++ ocex)

defmodule Models.PlantStand do
  @moduledoc "Plant tray insert v04, reconstructed as an Elixir recipe. Units: mm."
  defstruct diameter: 247.65,
            height: 19.05,
            deck: 5.0,
            slot_width: 8.0,
            ring_width: 8.0,
            hub_radius: 14.0,
            spokes: 8,
            spoke_width: 8.0,
            rib_depth: 5.0,
            foot_radius_position: 108.0,
            foot_length: 16.0,
            center_foot_diameter: 16.0,
            intermediate_foot_radius: 54.0,
            intermediate_foot_length: 16.0,
            intermediate_foot_count: 4,
            foot_root_radius: 2.0,
            rim_chamfer: 0.5

  @doc "Compose the drained deck, radial supports, feet, and rounded support roots."
  def build(dimensions \\ %__MODULE__{}) do
    dimensions
    |> deck()
    |> Smith.fuse(radial_supports(dimensions))
    |> Smith.fuse(intermediate_feet(dimensions))
    |> Smith.fuse(center_foot(dimensions))
    |> Smith.clean()
    |> round_roots(dimensions)
    |> Smith.clean()
  end

  @doc "Finished circular deck with connected drainage rings and rounded slot corners."
  def deck(p) do
    p
    |> deck_blank()
    |> Smith.cut(drain_slots(p))
    |> Smith.fuse(spokes(p))
    |> Smith.fillet(
      edges: &slot_corner?(&1, p),
      radius: 2.0,
      count: length(slot_radii(p)) * p.spokes * 4
    )
    |> Smith.chamfer(edges: &rim_edge?(&1, p), distance: p.rim_chamfer, count: 2)
  end

  @doc "Annular cutters spaced from the hub toward the rim."
  def drain_slots(p) do
    for radius <- slot_radii(p) do
      Smith.cylinder(radius + p.slot_width, p.deck + 2)
      |> Smith.cut(Smith.cylinder(radius, p.deck + 4) |> Smith.translate({0, 0, -1}))
      |> Smith.translate({0, 0, deck_bottom(p) - 1})
    end
  end

  @doc "Radial deck spokes, clipped to the circular envelope."
  def spokes(p) do
    for angle <- angles(p.spokes) do
      Smith.box(p.diameter / 2, p.spoke_width, p.deck)
      |> Smith.translate({0, -p.spoke_width / 2, deck_bottom(p)})
      |> Smith.rotate({0, 0, 1}, angle)
      |> Smith.common(deck_blank(p))
    end
  end

  @doc "A rib and outer foot at each spoke angle, preserving feature order."
  def radial_supports(p) do
    for angle <- angles(p.spokes), support <- [rib(p), outer_foot(p)] do
      Smith.rotate(support, {0, 0, 1}, angle)
    end
  end

  @doc "Intermediate feet distributed evenly around the center."
  def intermediate_feet(p) do
    for angle <- angles(p.intermediate_foot_count) do
      foot(p, p.intermediate_foot_radius, p.intermediate_foot_length)
      |> Smith.rotate({0, 0, 1}, angle)
    end
  end

  @doc "Center support extending all the way to the deck underside."
  def center_foot(p), do: Smith.cylinder(p.center_foot_diameter / 2, deck_bottom(p))

  def slot_radii(p) do
    Stream.iterate(p.hub_radius, &(&1 + p.slot_width + p.ring_width))
    |> Enum.take_while(&(&1 + p.slot_width <= p.diameter / 2 - p.ring_width / 2))
  end

  defp deck_blank(p) do
    Smith.cylinder(p.diameter / 2, p.deck)
    |> Smith.translate({0, 0, deck_bottom(p)})
  end

  defp rib(p) do
    length = p.foot_radius_position + p.foot_length / 2

    Smith.box(length, p.spoke_width, p.rib_depth)
    |> Smith.translate({0, -p.spoke_width / 2, rib_bottom(p)})
  end

  defp outer_foot(p), do: foot(p, p.foot_radius_position, p.foot_length)

  defp foot(p, radius, length) do
    Smith.box(length, p.spoke_width, rib_bottom(p))
    |> Smith.translate({radius - length / 2, -p.spoke_width / 2, 0})
  end

  defp round_roots(model, p) do
    Smith.fillet(model,
      edges: &root_edge?(&1, p),
      radius: p.foot_root_radius,
      count: p.spokes + 2 * p.intermediate_foot_count + 1
    )
  end

  defp slot_corner?(%{type: :line, direction: {_, _, z}, midpoint: midpoint}, p),
    do: abs(z) > 1 - 1.0e-9 and radial(midpoint) < p.diameter / 2 - 1

  defp slot_corner?(_, _), do: false

  defp rim_edge?(%{type: :circle, radius: radius}, p), do: near(radius, p.diameter / 2)
  defp rim_edge?(_, _), do: false

  defp root_edge?(%{bounds: {{_, _, low}, {_, _, high}}} = edge, p),
    do: near(low, rib_bottom(p)) and near(high, rib_bottom(p)) and root_shoulder?(edge, p)

  defp root_shoulder?(%{type: :circle, radius: radius}, p),
    do: near(radius, p.center_foot_diameter / 2)

  defp root_shoulder?(%{type: :line, length: length, midpoint: midpoint}, p) do
    radii = [
      p.foot_radius_position - p.foot_length / 2,
      p.intermediate_foot_radius - p.intermediate_foot_length / 2,
      p.intermediate_foot_radius + p.intermediate_foot_length / 2
    ]

    near(length, p.spoke_width) and Enum.any?(radii, &near(radial(midpoint), &1))
  end

  defp root_shoulder?(_, _), do: false

  defp deck_bottom(p), do: p.height - p.deck
  defp rib_bottom(p), do: deck_bottom(p) - p.rib_depth
  defp angles(count), do: Enum.map(0..(count - 1), &(&1 * 360 / count))
  defp radial({x, y, _}), do: :math.sqrt(x * x + y * y)
  defp near(a, b), do: abs(a - b) < 1.0e-6
end

unless "--no-export" in System.argv() do
  dimensions = struct(Models.PlantStand)
  {:ok, result} = dimensions |> Models.PlantStand.build() |> Smith.evaluate()

  checks =
    if "--verify" in System.argv() do
      Code.require_file("support/verification.exs", __DIR__)
      Code.require_file("test/plant_stand_checks.exs", __DIR__)

      %{
        comparison: Models.Verification.reference(result.shape, "plant-stand"),
        functional: Models.PlantStandChecks.verify(result.shape, dimensions)
      }
    else
      %{}
    end

  {:ok, export} =
    Smith.export(result, Path.expand("../output/models", __DIR__),
      name: "plant-stand",
      tolerance: 0.02,
      angular_tolerance: 0.08,
      print_rotation: {{1, 0, 0}, 180},
      print_offset: {0, 0, dimensions.height},
      display_offset: {0, 0, 0},
      metadata: checks
    )

  IO.inspect(export.verification, label: "Verified plant-stand", limit: :infinity)
end
