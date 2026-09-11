defmodule Models.DeckClipChecks do
  import Models.Verification

  def verify(body, p \\ %Models.DeckClip{}) do
    g = Models.DeckClip.Profile.geometry(p)

    cylinders =
      OCEx.faces(body)
      |> ok()
      |> Enum.map(&ok(OCEx.face_info(&1)))
      |> Enum.filter(&(&1.type == :cylinder))

    for radius <- [p.main_diameter / 2, p.recess_diameter / 2, p.flange_diameter / 2] do
      check(
        Enum.count(cylinders, &near(&1.radius, radius, 1.0e-5)) == 2,
        "Incorrect cylindrical hole count at R#{radius}"
      )
    end

    for {radius, spacing, axis} <- [
          {p.main_diameter / 2, p.main_spacing, :plate},
          {p.recess_diameter / 2, p.main_spacing, :plate},
          {p.flange_diameter / 2, p.flange_spacing, :flange}
        ] do
      [a, b] =
        Enum.filter(cylinders, &near(&1.radius, radius)) |> Enum.sort_by(&elem(&1.axis_origin, 0))

      check(
        near(elem(b.axis_origin, 0) - elem(a.axis_origin, 0), spacing),
        "Incorrect hole spacing"
      )

      for hole <- [a, b] do
        if axis == :plate do
          check(
            near(elem(hole.axis_origin, 1), p.flange_thickness + p.hole_row_from_flange) and
              abs(elem(hole.axis_direction, 2)) > 0.999999,
            "Incorrect plate hole placement"
          )
        else
          check(
            near(elem(hole.axis_origin, 2), p.flange_hole_elevation) and
              abs(elem(hole.axis_direction, 1)) > 0.999999,
            "Incorrect flange hole placement"
          )
        end
      end
    end

    inner_radius = p.widening_radius + p.hook_thickness
    {{tip_y, tip_z}, _, _} = Models.DeckClip.Profile.taper_sample(p, g, g.flare_path_length)

    stations =
      [{(g.root_center_y + g.flare_center_y) / 2, 2 * g.root_outer_radius - p.hook_thickness}] ++
        Enum.map([0, 0.25, 0.5, 0.75, 1], fn q ->
          {g.flare_center_y - inner_radius * :math.sin(g.flare_angle * q),
           g.flare_center_z - inner_radius * :math.cos(g.flare_angle * q)}
        end) ++
        [{tip_y + 0.01, tip_z - 0.01 * :math.tan(g.flare_angle)}]

    clearances =
      Enum.map(stations, fn {y, z} ->
        gap = z - p.plate_thickness

        probe =
          Smith.box(1, 0.001, gap - 0.02)
          |> Smith.translate({-0.5, y - 0.0005, p.plate_thickness + 0.01})
          |> shape()

        check(volume(ok(OCEx.common(body, probe))) < 1.0e-7, "Insertion corridor blocked")
        gap
      end)

    check(near(hd(clearances), p.hook_gap), "Incorrect throat gap")
    check(near(tip_y, p.hook_tip_from_flange), "Incorrect reach")

    check(
      Enum.all?(Enum.chunk_every(clearances, 2, 1, :discard), fn [a, b] -> b >= a - 1.0e-5 end),
      "Entrance narrows"
    )

    check(List.last(clearances) > p.hook_gap + 1, "Entrance does not flare")

    thicknesses =
      Enum.map([0, 0.25, 0.5, 0.75, 0.9], fn q ->
        {{y, z}, {ny, nz}, expected} =
          Models.DeckClip.Profile.taper_sample(p, g, g.flare_path_length * q)

        ray = OCEx.edge({0, y - ny * 0.1, z - nz * 0.1}, {0, y + ny * 6, z + nz * 6}) |> ok()
        measured = OCEx.common(body, ray) |> ok() |> OCEx.length() |> ok()

        check(
          near(measured, expected, 0.01),
          "Hook thickness #{measured} differs from #{expected}"
        )

        measured
      end)

    check(
      Enum.all?(Enum.chunk_every(thicknesses, 2, 1, :discard), fn [a, b] -> b < a end),
      "Hook thickness does not taper"
    )

    %{
      hole_positions: :passed,
      insertion_clearances_mm: clearances,
      flare_thicknesses_mm: thicknesses
    }
  end
end
