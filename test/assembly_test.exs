defmodule Smith.AssemblyTest do
  use ExUnit.Case, async: true
  alias Smith.Assembly

  test "named recipes branch immutably, rotate before translation, and retain inspectable parts" do
    bracket = Smith.box(2, 3, 4)
    base = Assembly.new(:fixture) |> Assembly.part(:left, bracket, position: {10, 0, 0})

    model =
      base |> Assembly.part(:right, bracket, position: {-10, 0, 0}, rotation: {{0, 0, 1}, 90})

    assert {:ok, original} = Smith.evaluate(base)
    assert {:error, :unknown_part} = Assembly.fetch(original, :right)
    assert {:ok, result} = Smith.evaluate(model)
    assert {:ok, left} = Assembly.fetch(result, "left")
    assert {:ok, right} = Assembly.fetch(result, :right)
    assert OCEx.bounds(left.shape) == {:ok, {{10.0, 0.0, 0.0}, {12.0, 3.0, 4.0}}}
    {:ok, {{lx, ly, _}, {hx, hy, _}}} = OCEx.bounds(right.shape)
    assert_in_delta lx, -13, 1.0e-8
    assert_in_delta hx, -10, 1.0e-8
    assert_in_delta ly, 0, 1.0e-8
    assert_in_delta hy, 2, 1.0e-8
    assert {:ok, solids} = OCEx.solids(result.shape)
    assert length(solids) == 2
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 48, 1.0e-8
  end

  test "shared recipe instances evaluate the base geometry once" do
    observer = self()

    recipe =
      Smith.box(2, 3, 4)
      |> Smith.fillet(
        edges: fn _ ->
          send(observer, :selected)
          true
        end,
        radius: 0.1
      )

    model =
      Assembly.new(:fixture)
      |> Assembly.part(:one, recipe)
      |> Assembly.part(:two, recipe, position: {10, 0, 0})

    assert {:ok, _} = Smith.evaluate(model)
    for _ <- 1..12, do: assert_receive(:selected)
    refute_receive :selected
  end

  test "references and printable extras stay outside installed geometry" do
    model =
      Assembly.new(:fixture)
      |> Assembly.part(:body, Smith.box(2, 3, 4))
      |> Assembly.part(:coupon, Smith.box(1, 1, 1), installed: false)
      |> Assembly.reference(:electronics, Smith.box(100, 100, 100))

    assert {:ok, result} = Smith.evaluate(model)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 24, 1.0e-8
    assert {:ok, _} = Assembly.fetch(result, :electronics)
    assert {:ok, _} = Assembly.fetch(result, :coupon)
  end

  test "references reject print and preview-only options" do
    for opts <- [
          [print: [on_bed: true]],
          [display_offset: {1, 0, 0}],
          [exploded_offset: {0, 0, 1}]
        ] do
      assert {:error, %{part: :ref, reason: :invalid_options}} =
               Assembly.new(:fixture)
               |> Assembly.part(:body, Smith.box(1, 1, 1))
               |> Assembly.reference(:ref, Smith.box(1, 1, 1), opts)
               |> Smith.evaluate()
    end
  end

  test "part failures retain the failing modeling operation and index" do
    model =
      Assembly.new(:fixture)
      |> Assembly.part(
        :shell,
        Smith.box(2, 3, 4) |> Smith.fillet(edges: :all, radius: -1)
      )

    assert {:error, %{__struct__: Smith.Error, part: :shell, step: 2, operation: :fillet}} =
             Smith.evaluate(model)
  end

  test "ambiguous names, bad placement, unsupported options, and invalid recipes fail explicitly" do
    box = Smith.box(1, 1, 1)
    assert {:error, _} = Assembly.new(:empty) |> Smith.evaluate()
    assert {:error, _} = Assembly.new("../bad") |> Assembly.part(:part, box) |> Smith.evaluate()

    for name <- [:part, "part"] do
      assert {:error, %{reason: :duplicate_part}} =
               Assembly.new(:fixture)
               |> Assembly.part(:part, box)
               |> Assembly.reference(name, box)
               |> Smith.evaluate()
    end

    assert {:error, %{reason: :duplicate_part}} =
             Assembly.new(:fixture)
             |> Assembly.part(:a_b, box)
             |> Assembly.part("a-b", box)
             |> Smith.evaluate()

    for opts <- [
          [typo: true],
          [position: {1, 2}],
          [rotation: {{0, 0, 0}, 90}],
          [installed: :yes],
          [print: [typo: true]],
          [print: [on_bed: true, offset: {0, 0, 0}]],
          [print: [on_bed: true, on_bed: false]],
          [exploded_offset: :bad]
        ] do
      assert {:error, %{part: :part, reason: :invalid_options}} =
               Assembly.new(:fixture) |> Assembly.part(:part, box, opts) |> Smith.evaluate()
    end

    assert {:error, %{reason: :invalid_options}} =
             Assembly.new(:fixture)
             |> Assembly.reference(:ref, box, print: [on_bed: true])
             |> Smith.evaluate()

    assert {:error, %{reason: :invalid_part_model}} =
             Assembly.new(:fixture) |> Assembly.part(:part, :bad) |> Smith.evaluate()
  end
end
