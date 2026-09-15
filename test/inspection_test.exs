defmodule Smith.InspectionTest do
  use ExUnit.Case, async: true
  alias Smith.{Inspection, Measure}
  @moduletag :tmp_dir

  test "reports catch exposed material and displacement without images" do
    body = Smith.box(20, 20, 5)
    lip = Smith.box(4, 10, 1, at: {18, 5, 4})
    {:ok, result} = Smith.evaluate(body)
    {:ok, width} = Measure.extent(result, :x)

    assert {:ok, report} =
             Inspection.run(%{body: result, lip: lip},
               checks: [
                 {:contained, :lip, :body, [tolerance: 1.0e-7]},
                 {:bounds, :body, {{0, 0, 0}, {19, 20, 5}}, [tolerance: 1.0e-7]},
                 {:measurement, :body, width, [expected: 20, tolerance: 1.0e-7]}
               ]
             )

    assert report.status == :failed
    [outside, bounds, measurement] = report.checks
    assert_in_delta outside.measured, 20, 1.0e-7
    assert outside.unit == :mm3
    assert outside.status == :failed
    assert outside.bounds != nil
    assert bounds.status == :failed
    assert measurement.status == :passed
    assert {:ok, json} = Inspection.json(report)
    decoded = JSON.decode!(json)
    assert decoded["models"]["body"]["revision"] == result.revision
    refute json =~ "#Reference"
  end

  test "clearance distinguishes contact, containment, and penetration" do
    assert {:ok, report} =
             Inspection.run(
               %{
                 a: Smith.box(10, 10, 10),
                 b: Smith.box(2, 2, 2, at: {2, 2, 2}),
                 c: Smith.box(2, 2, 2, at: {13, 0, 0})
               },
               checks: [
                 {:clearance, :a, :b, [minimum: 0, tolerance: 1.0e-7]},
                 {:clearance, :a, :c, [minimum: 2.9, tolerance: 1.0e-7]}
               ]
             )

    [overlap, clear] = report.checks
    assert overlap.status == :failed
    assert_in_delta overlap.interference_mm3, 8, 1.0e-7
    assert clear.status == :passed
    assert_in_delta clear.measured, 3, 1.0e-7
    assert clear.point_a != clear.point_b
  end

  test "stage differences measure additions and removals separately" do
    a = Smith.box(10, 10, 10)
    b = a |> Smith.cut(Smith.box(2, 2, 10)) |> Smith.fuse(Smith.box(2, 2, 10, at: {10, 0, 0}))
    assert {:ok, diff} = Inspection.compare(a, b)
    assert_in_delta diff.added_mm3, 40, 1.0e-7
    assert_in_delta diff.removed_mm3, 40, 1.0e-7
    assert diff.before_revision != diff.after_revision
  end

  test "topology queries are bounded and ambiguous model names fail" do
    assert {:ok, page} = Inspection.topology(Smith.box(10, 20, 30), :faces, limit: 2, offset: 2)
    assert page.total == 6 and length(page.items) == 2 and page.next_offset == 4
    assert Enum.all?(page.items, &(&1.type == :plane))

    assert {:error, :duplicate_name} =
             Inspection.run(%{:part => Smith.box(1, 1, 1), "part" => Smith.box(2, 2, 2)})

    assert {:error, :invalid_options} = Inspection.topology(Smith.box(1, 1, 1), :faces, limit: -1)
  end

  test "errors are recorded and never reported as passing checks" do
    assert {:ok, report} =
             Inspection.run(%{body: Smith.box(2, 2, 2)},
               checks: [{:contained, :missing, :body, [tolerance: 0.01]}]
             )

    assert report.status == :error
    assert hd(report.checks).reason == :unknown_model
    {:ok, r} = Smith.evaluate(Smith.box(1, 1, 1))
    {:ok, m} = Measure.extent(r, :x)

    {:ok, report} =
      Inspection.run(%{body: Smith.box(2, 2, 2)},
        checks: [{:measurement, :body, m, [expected: 1, tolerance: 0.01]}]
      )

    assert hd(report.checks).reason == :revision_mismatch
  end

  test "topology requirements catch disconnected material without vision" do
    source = Smith.compound([Smith.box(2, 2, 2), Smith.box(2, 2, 2, at: {4, 0, 0})])

    assert {:ok, report} =
             Inspection.run(%{part: source}, checks: [{:topology, :part, :solids, [expected: 1]}])

    assert report.status == :failed
    assert [%{measured: 2, expected: 1, unit: :count}] = report.checks
  end

  test "invalid names and measurement targets return specific errors" do
    body = Smith.box(2, 2, 2)
    assert {:error, :invalid_name} = Inspection.run(%{{:part, 1} => body})
    {:ok, width} = Measure.extent(body, :x)

    assert {:ok, report} =
             Inspection.run(%{body: body},
               checks: [
                 {:measurement, :body, width, expected: "2", tolerance: 0.01}
               ]
             )

    assert report.status == :error
    assert [%{reason: :invalid_options}] = report.checks
  end
end
