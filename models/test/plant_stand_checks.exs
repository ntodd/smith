defmodule Models.PlantStandChecks do
  import Models.Verification

  def verify(body, p \\ %Models.PlantStand{}) do
    for r <- Models.PlantStand.slot_radii(p) do
      a = :math.pi() / p.spokes

      probe =
        Smith.cylinder(1, p.height + 2)
        |> Smith.translate(
          {(r + p.slot_width / 2) * :math.cos(a), (r + p.slot_width / 2) * :math.sin(a), -1}
        )
        |> shape()

      check(volume(ok(OCEx.common(body, probe))) < 1.0e-7, "Drain slot blocked at #{r}")
    end

    slice =
      Smith.box(p.diameter + 2, p.diameter + 2, 0.5)
      |> Smith.translate({-p.diameter / 2 - 1, -p.diameter / 2 - 1, 0})
      |> shape()

    feet = OCEx.common(body, slice) |> ok() |> OCEx.solids() |> ok() |> length()
    check(feet == p.spokes + p.intermediate_foot_count + 1, "Incorrect feet count: #{feet}")

    for i <- 0..(p.intermediate_foot_count - 1) do
      a = i * 2 * :math.pi() / p.intermediate_foot_count

      probe =
        Smith.cylinder(1, p.height - p.deck)
        |> Smith.translate(
          {p.intermediate_foot_radius * :math.cos(a), p.intermediate_foot_radius * :math.sin(a),
           0}
        )
        |> shape()

      check(
        near(volume(ok(OCEx.common(body, probe))), volume(probe)),
        "Interrupted intermediate support"
      )
    end

    %{
      drain_bands: length(Models.PlantStand.slot_radii(p)),
      feet: feet,
      continuous_intermediate_supports: p.intermediate_foot_count
    }
  end
end
