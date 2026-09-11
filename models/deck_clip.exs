# OCEX_PATH is an optional development override; normal runs resolve OCEx from Hex.
ocex =
  case System.get_env("OCEX_PATH") do
    nil -> []
    directory -> [{:ocex, path: Path.expand(directory), override: true}]
  end

Mix.install([{:smith, path: Path.expand("..", __DIR__)}] ++ ocex)

defmodule Models.DeckClip do
  @moduledoc "Deck clip v04, with the original tapered spline and R0.8 edge rounds. Units: mm."
  alias __MODULE__.Profile

  defstruct width: 70.4,
            depth: 47.5,
            height: 26.0,
            plate_thickness: 5.0,
            hook_width: 40.4,
            hook_thickness: 5.0,
            hook_gap: 11.2,
            hook_tip_from_flange: 18.0,
            main_spacing: 50.6,
            main_diameter: 5.0,
            recess_diameter: 9.6,
            hole_row_from_flange: 6.5,
            flange_height: 18.5,
            flange_spacing: 50.75,
            flange_diameter: 4.6,
            flange_hole_elevation: 9.5,
            flange_thickness: 3.4,
            recess_depth: 2.1,
            widening_radius: 14.2,
            terminal_flare_length: 2.0,
            shoulder_start: 17.0,
            shoulder_end: 28.0,
            corner_chamfer: 2.5,
            tip_side_inset: 3.0,
            tip_taper_start_y: 30.0,
            edge_radius: 0.8,
            flare_tip_thickness: 3.5

  @doc "Compose the clip's features into a deferred recipe. Rounding precedes drilling."
  def build(dimensions \\ %__MODULE__{}) do
    dimensions
    |> hook()
    |> Smith.fuse(mounting_plate(dimensions))
    |> Smith.fuse(mounting_flange(dimensions))
    |> Smith.cut(tip_trimmers(dimensions))
    |> Smith.clean()
    |> Smith.fillet(edges: :all, radius: dimensions.edge_radius)
    |> Smith.cut(plate_holes(dimensions))
    |> Smith.cut(flange_holes(dimensions))
  end

  @doc "Extruded hook with the tight root and tapered, flared return arm."
  def hook(dimensions) do
    dimensions
    |> Profile.build()
    |> Smith.extrude({dimensions.hook_width, 0, 0})
  end

  @doc "Mounting plate, including its shoulders and clipped front corners."
  def mounting_plate(dimensions) do
    half_width = dimensions.width / 2
    half_hook = dimensions.hook_width / 2
    chamfer = dimensions.corner_chamfer
    root_y = Profile.geometry(dimensions).root_center_y

    [
      {-half_width + chamfer, 0},
      {half_width - chamfer, 0},
      {half_width, chamfer},
      {half_width, dimensions.shoulder_start},
      {half_hook, dimensions.shoulder_end},
      {half_hook, root_y},
      {-half_hook, root_y},
      {-half_hook, dimensions.shoulder_end},
      {-half_width, dimensions.shoulder_start},
      {-half_width, chamfer}
    ]
    |> Enum.map(fn {x, y} -> {x, y, 0} end)
    |> Smith.polygon()
    |> Smith.extrude({0, 0, dimensions.plate_thickness})
  end

  @doc "Perpendicular flange with clipped upper corners, before drilling."
  def mounting_flange(dimensions) do
    half_width = dimensions.width / 2
    chamfer = dimensions.corner_chamfer

    [
      {-half_width, 0},
      {half_width, 0},
      {half_width, dimensions.flange_height - chamfer},
      {half_width - chamfer, dimensions.flange_height},
      {-half_width + chamfer, dimensions.flange_height},
      {-half_width, dimensions.flange_height - chamfer}
    ]
    |> Enum.map(fn {x, z} -> {x, 0, z} end)
    |> Smith.polygon()
    |> Smith.extrude({0, dimensions.flange_thickness, 0})
  end

  @doc "Paired cutting tools that taper the sides of the raised return arm."
  def tip_trimmers(dimensions), do: Enum.map([-1, 1], &tip_trimmer(dimensions, &1))

  @doc "Through-hole and counterbore tools for each plate screw, in machining order."
  def plate_holes(dimensions) do
    Enum.flat_map([-dimensions.main_spacing / 2, dimensions.main_spacing / 2], fn x ->
      [plate_hole(dimensions, x), counterbore(dimensions, x)]
    end)
  end

  @doc "Two horizontal screw-hole tools for the mounting flange."
  def flange_holes(dimensions) do
    for x <- [-dimensions.flange_spacing / 2, dimensions.flange_spacing / 2] do
      Smith.cylinder(dimensions.flange_diameter / 2, dimensions.flange_thickness + 2)
      |> Smith.rotate({1, 0, 0}, 90)
      |> Smith.translate({x, dimensions.flange_thickness + 1, dimensions.flange_hole_elevation})
    end
  end

  defp plate_hole(dimensions, x) do
    Smith.cylinder(dimensions.main_diameter / 2, dimensions.plate_thickness + 2)
    |> Smith.translate({x, dimensions.flange_thickness + dimensions.hole_row_from_flange, -1})
  end

  defp counterbore(dimensions, x) do
    Smith.cylinder(dimensions.recess_diameter / 2, dimensions.recess_depth)
    |> Smith.translate(
      {x, dimensions.flange_thickness + dimensions.hole_row_from_flange,
       dimensions.plate_thickness - dimensions.recess_depth}
    )
  end

  defp tip_trimmer(dimensions, side) do
    half_hook = dimensions.hook_width / 2
    half_tip = half_hook - dimensions.tip_side_inset
    bottom = 2 * Profile.geometry(dimensions).root_outer_radius - dimensions.hook_thickness - 0.1

    [
      {side * half_hook, dimensions.tip_taper_start_y},
      {side * half_tip, dimensions.hook_tip_from_flange},
      {side * half_tip, dimensions.hook_tip_from_flange - 2},
      {side * (dimensions.width + 10), dimensions.hook_tip_from_flange - 2},
      {side * (dimensions.width + 10), dimensions.tip_taper_start_y}
    ]
    |> Enum.map(fn {x, y} -> {x, y, bottom} end)
    |> Smith.polygon()
    |> Smith.extrude({0, 0, dimensions.height})
  end
end

defmodule Models.DeckClip.Profile do
  @moduledoc "The hook's closed section and pure calculations for its curved, tapered wall."

  def build(dimensions) do
    geometry = geometry(dimensions)
    outer = outer_profile(dimensions, geometry)
    arc_end = inner_arc_end(dimensions, geometry)
    tip = inner_tip(dimensions, geometry)

    Smith.profile([
      hook_line(dimensions, {0, 0}, {geometry.root_center_y, 0}),
      hook_arc(
        dimensions,
        {geometry.root_center_y, geometry.root_center_z},
        geometry.root_outer_radius,
        -90,
        180
      ),
      hook_line(
        dimensions,
        {geometry.root_center_y, 2 * geometry.root_outer_radius},
        {geometry.flare_center_y, 2 * geometry.root_outer_radius}
      ),
      Smith.spline(
        Enum.map(outer, &on_hook_plane(&1, dimensions)),
        {{0, -1, 0}, {0, -:math.cos(geometry.flare_angle), :math.sin(geometry.flare_angle)}}
      ),
      hook_line(dimensions, List.last(outer), tip),
      hook_line(dimensions, tip, arc_end),
      hook_arc(
        dimensions,
        {geometry.flare_center_y, geometry.flare_center_z},
        dimensions.widening_radius + dimensions.hook_thickness,
        -90 - geometry.flare_angle_degrees,
        geometry.flare_angle_degrees
      ),
      hook_line(
        dimensions,
        {geometry.flare_center_y, 2 * geometry.root_outer_radius - dimensions.hook_thickness},
        {geometry.root_center_y, 2 * geometry.root_outer_radius - dimensions.hook_thickness}
      ),
      hook_arc(
        dimensions,
        {geometry.root_center_y, geometry.root_center_z},
        geometry.root_inner_radius,
        90,
        -180
      ),
      hook_line(
        dimensions,
        {geometry.root_center_y, dimensions.hook_thickness},
        {0, dimensions.plate_thickness}
      ),
      hook_line(dimensions, {0, dimensions.plate_thickness}, {0, 0})
    ])
  end

  defp hook_line(dimensions, from, to),
    do: Smith.line(on_hook_plane(from, dimensions), on_hook_plane(to, dimensions))

  defp hook_arc(dimensions, center, radius, start, sweep),
    do: Smith.arc(on_hook_plane(center, dimensions), {1, 0, 0}, {0, 1, 0}, radius, start, sweep)

  defp on_hook_plane({y, z}, dimensions), do: {-dimensions.hook_width / 2, y, z}

  defp outer_profile(dimensions, geometry) do
    dimensions
    |> sample_distances(geometry)
    |> Enum.map(fn distance ->
      {{y, z}, {ny, nz}, thickness} = taper_sample(dimensions, geometry, distance)
      {y + thickness * ny, z + thickness * nz}
    end)
  end

  defp sample_distances(dimensions, geometry) do
    arc_length = (dimensions.widening_radius + dimensions.hook_thickness) * geometry.flare_angle

    Enum.map(0..24, &(arc_length * &1 / 24)) ++
      Enum.map(1..6, &(arc_length + dimensions.terminal_flare_length * &1 / 6))
  end

  defp inner_arc_end(dimensions, geometry) do
    radius = dimensions.widening_radius + dimensions.hook_thickness

    {geometry.flare_center_y - radius * :math.sin(geometry.flare_angle),
     geometry.flare_center_z - radius * :math.cos(geometry.flare_angle)}
  end

  defp inner_tip(dimensions, geometry) do
    {y, z} = inner_arc_end(dimensions, geometry)

    {y - dimensions.terminal_flare_length * :math.cos(geometry.flare_angle),
     z + dimensions.terminal_flare_length * :math.sin(geometry.flare_angle)}
  end

  @doc "Derived dimensions of the root bend and flared entrance; no geometry is evaluated."
  def geometry(dimensions) do
    root_radius = (dimensions.hook_gap + 2 * dimensions.hook_thickness) / 2
    angle = flare_angle(dimensions, root_radius)
    inner_flare_radius = dimensions.widening_radius + dimensions.hook_thickness

    %{
      root_outer_radius: root_radius,
      root_inner_radius: root_radius - dimensions.hook_thickness,
      root_center_y: dimensions.depth - root_radius,
      root_center_z: root_radius,
      flare_center_y:
        dimensions.hook_tip_from_flange + inner_flare_radius * :math.sin(angle) +
          dimensions.terminal_flare_length * :math.cos(angle),
      flare_center_z: 2 * root_radius + dimensions.widening_radius,
      flare_angle: angle,
      flare_angle_degrees: angle * 180 / :math.pi(),
      flare_path_length: inner_flare_radius * angle + dimensions.terminal_flare_length
    }
  end

  @doc "Inner guide point, outward unit normal, and wall thickness at a path distance."
  def taper_sample(dimensions, geometry, distance) do
    fraction = distance / geometry.flare_path_length

    thickness =
      dimensions.hook_thickness -
        (dimensions.hook_thickness - dimensions.flare_tip_thickness) * smoothstep(fraction)

    inner_radius = dimensions.widening_radius + dimensions.hook_thickness
    arc_angle = min(distance / inner_radius, geometry.flare_angle)
    lead_in = max(0.0, distance - inner_radius * geometry.flare_angle)

    y =
      geometry.flare_center_y - inner_radius * :math.sin(arc_angle) -
        lead_in * :math.cos(geometry.flare_angle)

    z =
      geometry.flare_center_z - inner_radius * :math.cos(arc_angle) +
        lead_in * :math.sin(geometry.flare_angle)

    {{y, z}, {:math.sin(arc_angle), :math.cos(arc_angle)}, thickness}
  end

  defp smoothstep(fraction), do: 3 * fraction * fraction - 2 * fraction * fraction * fraction

  defp flare_angle(dimensions, root_radius) do
    rise = dimensions.height - 2 * root_radius

    {lower, upper} =
      Enum.reduce(1..70, {0.0, :math.pi() / 2}, fn _, {lower, upper} ->
        angle = (lower + upper) / 2

        height =
          dimensions.widening_radius * (1 - :math.cos(angle)) +
            dimensions.terminal_flare_length * :math.sin(angle)

        if height < rise, do: {angle, upper}, else: {lower, angle}
      end)

    (lower + upper) / 2
  end
end

unless "--no-export" in System.argv() do
  dimensions = struct(Models.DeckClip)
  {:ok, result} = dimensions |> Models.DeckClip.build() |> Smith.evaluate()

  checks =
    if "--verify" in System.argv() do
      Code.require_file("support/verification.exs", __DIR__)
      Code.require_file("test/deck_clip_checks.exs", __DIR__)

      %{
        comparison: Models.Verification.reference(result.shape, "deck-clip"),
        functional: Models.DeckClipChecks.verify(result.shape, dimensions)
      }
    else
      %{}
    end

  {:ok, export} =
    Smith.export(result, Path.expand("../output/models", __DIR__),
      name: "deck-clip",
      tolerance: 0.005,
      angular_tolerance: 0.05,
      display_offset: {185, -25, 0},
      metadata: checks
    )

  IO.inspect(export.verification, label: "Verified deck-clip", limit: :infinity)
end
