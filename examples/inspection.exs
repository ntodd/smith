Mix.install([{:smith, "~> 0.4.0"}])

alias Smith.{Drawing, Inspection, Measure}

# A script can build, inspect, repair, draw, and export without Kino or vision.
defmodule InspectionExample do
  def plate(right_x) do
    Smith.box(40, 24, 6)
    |> Smith.cut([
      Smith.cylinder(2, 8, at: {10, 12, -1}),
      Smith.cylinder(2, 8, at: {right_x, 12, -1})
    ])
    |> Smith.evaluate()
  end

  def spacing(result) do
    left = fn edge ->
      edge.type == :circle and elem(edge.center, 0) < 20 and
        abs(elem(edge.center, 2) - 6) < 1.0e-6
    end

    right = fn edge ->
      edge.type == :circle and elem(edge.center, 0) > 20 and
        abs(elem(edge.center, 2) - 6) < 1.0e-6
    end

    Smith.Measure.distance(result, {:circle_center, left}, {:circle_center, right}, axis: :x)
  end
end

{:ok, first} = InspectionExample.plate(28)
{:ok, spacing} = InspectionExample.spacing(first)

{:ok, failed} =
  Inspection.run(%{plate: first},
    checks: [
      {:measurement, :plate, spacing, expected: 20, tolerance: 1.0e-6}
    ]
  )

:failed = failed.status
{:ok, json} = Inspection.json(failed)
IO.puts(json)

# The report measured 18 mm. Move the second hole by the missing 2 mm.
{:ok, corrected} = InspectionExample.plate(30)
{:ok, spacing} = InspectionExample.spacing(corrected)

{:ok, passed} =
  Inspection.run(%{plate: corrected},
    checks: [
      {:bounds, :plate, {{0, 0, 0}, {40, 24, 6}}, tolerance: 1.0e-6},
      {:measurement, :plate, spacing, expected: 20, tolerance: 1.0e-6}
    ]
  )

:passed = passed.status

output = Path.expand("output/inspection-example")

{:ok, artifacts} =
  Inspection.write(passed, output,
    views: [:isometric, :top, :front],
    sections: [Smith.Plane.xz(y: 12)]
  )

{:ok, width} = Measure.extent(corrected, :x)
{:ok, drawing} = Drawing.new(corrected, on: :xy)
{:ok, drawing} = Drawing.dimension(drawing, width, orientation: :horizontal, offset: -6)
{:ok, drawing} = Drawing.dimension(drawing, spacing, orientation: :horizontal, offset: 18)
{:ok, _} = Drawing.write(drawing, Path.join(artifacts.directory, "dimensions.svg"), hidden: false)
{:ok, files} = Smith.export(corrected, output, name: "measured-plate", on_bed: true)
IO.puts("Inspection report: #{artifacts.report}")
IO.puts("Printable 3MF: #{files.three_mf}")
