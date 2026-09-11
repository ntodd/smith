defmodule SmithTest do
  use ExUnit.Case, async: true

  defp plate do
    Smith.box(60, 40, 5)
    |> Smith.fillet(edges: {:parallel, :z}, radius: 2)
    |> Smith.hole(on: :top, diameter: 8, through: :all)
  end

  test "construction is deferred and models branch without changing the original" do
    base = Smith.box(60, 40, 5)
    a = Smith.hole(base, on: :top, diameter: 8, through: :all)
    b = Smith.hole(base, on: :top, diameter: 10, through: :all)
    assert base.operations == [{:box, [60, 40, 5]}]
    assert length(a.operations) == 2
    assert length(b.operations) == 2
    refute a == b
    assert {:ok, ra} = Smith.evaluate(a)
    assert {:ok, rb} = Smith.evaluate(b)
    assert {:ok, va} = OCEx.volume(ra.shape)
    assert {:ok, vb} = OCEx.volume(rb.shape)
    assert va > vb
  end

  test "the requested pipeline evaluates to the independently calculated solid" do
    assert {:ok, result} = Smith.evaluate(plate())
    assert OCEx.valid?(result.shape) == {:ok, true}
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, (2400 - (4 - :math.pi()) * 4 - :math.pi() * 16) * 5, 1.0e-5
    assert byte_size(result.revision) == 64
  end

  test "all axis selectors resolve against the body at that step" do
    for axis <- [:x, :y, :z] do
      model = Smith.box(20, 20, 20) |> Smith.fillet(edges: {:parallel, axis}, radius: 2)
      assert {:ok, result} = Smith.evaluate(model)
      assert OCEx.valid?(result.shape) == {:ok, true}
      assert {:ok, volume} = OCEx.volume(result.shape)
      assert_in_delta volume, (400 - (4 - :math.pi()) * 4) * 20, 1.0e-5
    end
  end

  test "hole offsets are relative to the selected top face centroid" do
    model = Smith.box(60, 40, 5) |> Smith.hole(on: :top, at: {10, 0}, diameter: 8, through: :all)
    assert {:ok, result} = Smith.evaluate(model)
    assert {:ok, {x, y, z}} = OCEx.center_of_mass(result.shape)
    removed = :math.pi() * 16 * 5
    assert_in_delta x, (12_000 * 30 - removed * 40) / (12_000 - removed), 1.0e-6
    assert_in_delta y, 20, 1.0e-6
    assert_in_delta z, 2.5, 1.0e-6
  end

  test "invalid dimensions identify the failed step" do
    assert {:error, %Smith.Error{step: 1, operation: :box, reason: :invalid_argument}} =
             Smith.evaluate(Smith.box(0, 40, 5))
  end

  test "failed native operation identifies its recipe step" do
    model = Smith.box(10, 10, 10) |> Smith.fillet(edges: {:parallel, :z}, radius: 1000)
    assert {:error, %Smith.Error{step: 2, operation: :fillet}} = Smith.evaluate(model)
  end

  for opts <- [
        [edges: :unknown, radius: 1],
        [edges: {:parallel, :w}, radius: 1],
        [edges: {:parallel, :z}],
        [edges: {:parallel, :z}, radius: 1, typo: true]
      ] do
    test "rejects unsupported fillet options #{inspect(opts)}" do
      model = Smith.box(10, 10, 10) |> Smith.fillet(unquote(Macro.escape(opts)))
      assert {:error, %Smith.Error{reason: :invalid_options}} = Smith.evaluate(model)
    end
  end

  for opts <- [
        [on: :bottom, diameter: 8, through: :all],
        [on: :top, diameter: 8],
        [on: :top, diameter: 8, through: :all, at: {1}],
        [on: :top, diameter: -8, through: :all],
        [on: :top, diameter: 8, through: :all, typo: true]
      ] do
    test "rejects unsupported hole options #{inspect(opts)}" do
      model = Smith.box(60, 40, 5) |> Smith.hole(unquote(Macro.escape(opts)))
      assert {:error, %Smith.Error{}} = Smith.evaluate(model)
    end
  end

  test "a hole missing the body reports an error" do
    model = Smith.box(60, 40, 5) |> Smith.hole(on: :top, diameter: 8, through: :all, at: {100, 0})
    assert {:error, %Smith.Error{reason: :hole_misses_body}} = Smith.evaluate(model)
  end

  test "geometry revision is reproducible and changes with the model" do
    assert {:ok, a} = Smith.evaluate(Smith.box(60, 40, 5))
    assert {:ok, b} = Smith.evaluate(Smith.box(60, 40, 5))
    assert {:ok, c} = Smith.evaluate(Smith.box(60, 40, 6))
    assert a.revision == b.revision
    refute a.revision == c.revision
  end

  @tag :tmp_dir
  test "exports can be reopened and measured", %{tmp_dir: dir} do
    assert {:ok, result} = Smith.evaluate(plate())
    path = Path.join(dir, "plate.step")
    assert {:ok, :ok} = Smith.export(result, path)
    assert {:ok, reopened} = OCEx.read_step(path)
    assert {:ok, expected} = OCEx.volume(result.shape)
    assert {:ok, actual} = OCEx.volume(reopened)
    assert_in_delta actual, expected, 1.0e-5
    assert {:error, :unsupported_format} = Smith.export(result, Path.join(dir, "plate.obj"))
  end
end
