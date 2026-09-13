defmodule Smith.NestedAssemblyTest do
  use ExUnit.Case, async: true
  alias Smith.Assembly
  @moduletag :tmp_dir

  defp module_recipe do
    Assembly.new(:module)
    |> Assembly.part(:body, Smith.box(2, 3, 4), position: {5, 0, 0}, print: [on_bed: true])
    |> Assembly.part(:coupon, Smith.box(1, 1, 1), installed: false, print: [on_bed: true])
    |> Assembly.reference(:board, Smith.box(1, 2, 3), position: {0, 0, 10})
  end

  defp volume(shape, expected) do
    assert {:ok, measured} = OCEx.volume(shape)
    assert_in_delta measured, expected, 1.0e-7
  end

  test "subassemblies retain their tree and compose child placement before parent placement" do
    child = module_recipe()

    root =
      Assembly.new(:fixture)
      |> Assembly.subassembly(:left, child, rotation: {{0, 0, 1}, 90}, position: {10, 20, 30})
      |> Assembly.subassembly(:right, child, position: {-20, 0, 0})

    assert {:ok, result} = Smith.evaluate(root)
    assert {:ok, %Assembly.Result{} = left} = Assembly.fetch(result, :left)
    assert {:ok, part} = Assembly.fetch(result, [:left, :body])
    assert {:ok, ^part} = Assembly.fetch(result, "left/body")
    assert {:ok, bounds} = OCEx.bounds(part.shape)

    for {actual, expected} <- Enum.zip(Tuple.to_list(elem(bounds, 0)), [7, 25, 30]),
        do: assert_in_delta(actual, expected, 1.0e-7)

    for {actual, expected} <- Enum.zip(Tuple.to_list(elem(bounds, 1)), [10, 27, 34]),
        do: assert_in_delta(actual, expected, 1.0e-7)

    volume(result.shape, 48)
    volume(left.shape, 24)
    assert {:ok, _} = Assembly.fetch(left, :board)
    assert {:error, :unknown_part} = Assembly.fetch(result, [:left, :body, :missing])
    assert {:error, :unknown_part} = Assembly.fetch(result, [])
    assert {:error, :unknown_part} = Assembly.fetch(result, "left//body")
    assert {:ok, original} = Smith.evaluate(child)
    assert {:ok, body} = Assembly.fetch(original, :body)
    assert OCEx.bounds(body.shape) == {:ok, {{5.0, 0.0, 0.0}, {7.0, 3.0, 4.0}}}
  end

  test "leaf recipes are evaluated once across repeated and distinct branches" do
    observer = self()

    shared =
      Smith.box(2, 3, 4)
      |> Smith.fillet(
        edges: fn _ ->
          send(observer, :edge)
          true
        end,
        radius: 0.1
      )

    child = Assembly.new(:module) |> Assembly.part(:body, shared)
    different = Assembly.new(:different) |> Assembly.part(:other, shared)

    recipe =
      Assembly.new(:fixture)
      |> Assembly.subassembly(:one, child)
      |> Assembly.subassembly(:two, child, position: {10, 0, 0})
      |> Assembly.subassembly(:three, different, position: {20, 0, 0})

    assert {:ok, _} = Smith.evaluate(recipe)
    for _ <- 1..12, do: assert_receive(:edge)
    refute_receive :edge
  end

  test "an uninstalled branch excludes its solids without dropping references or print extras" do
    root =
      Assembly.new(:fixture)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.subassembly(:spare, module_recipe(), installed: false)

    assert {:ok, result} = Smith.evaluate(root)
    volume(result.shape, 1)
    assert {:ok, leaves} = Assembly.members(result)

    assert Enum.map(leaves, & &1.path) == [
             ["base"],
             ["spare", "body"],
             ["spare", "coupon"],
             ["spare", "board"]
           ]

    assert Enum.map(leaves, & &1.installed) == [true, false, false, false]
    assert Enum.map(leaves, & &1.kind) == [:part, :part, :part, :reference]
  end

  test "invalid nested members carry their full path and original modeling error" do
    bad =
      Assembly.new(:bad)
      |> Assembly.part(:broken, Smith.box(1, 1, 1) |> Smith.fillet(edges: :all, radius: -1))

    root = Assembly.new(:root) |> Assembly.subassembly(:left, bad)

    assert {:error, %Smith.Error{part: "left/broken", operation: :fillet, step: 2}} =
             Smith.evaluate(root)

    for opts <- [
          [print: [on_bed: true]],
          [position: {1, 2}],
          [installed: :yes],
          [rotation: {{0, 0, 0}, 90}]
        ] do
      assert {:error, %Smith.Error{part: :left, reason: :invalid_options}} =
               Assembly.new(:root)
               |> Assembly.subassembly(:left, module_recipe(), opts)
               |> Smith.evaluate()
    end

    assert {:error, %Smith.Error{reason: :duplicate_part}} =
             Assembly.new(:root)
             |> Assembly.subassembly(:a_b, module_recipe())
             |> Assembly.part("a-b", Smith.box(1, 1, 1))
             |> Smith.evaluate()

    assert {:error, %Smith.Error{reason: :invalid_subassembly}} =
             Assembly.new(:root)
             |> Assembly.subassembly(:bad, Smith.box(1, 1, 1))
             |> Smith.evaluate()
  end

  test "nested exports preserve leaf identity, print placement, tree and references", %{
    tmp_dir: root
  } do
    recipe =
      Assembly.new(:fixture)
      |> Assembly.subassembly(:left, module_recipe(),
        position: {20, 0, 0},
        exploded_offset: {0, 0, 10}
      )
      |> Assembly.subassembly(:right, module_recipe(), position: {-20, 0, 0})

    assert {:ok, result} = Smith.evaluate(recipe)

    assert {:ok, report} =
             Smith.export(result, root,
               name: "fixture",
               part_metadata: %{[:left, :body] => %{material: "PLA"}}
             )

    assert Enum.map(report.parts, & &1.part) == [
             "left/body",
             "left/coupon",
             "right/body",
             "right/coupon"
           ]

    assert Enum.map(report.parts, & &1.name) == [
             "fixture-left__body",
             "fixture-left__coupon",
             "fixture-right__body",
             "fixture-right__coupon"
           ]

    assert hd(report.parts).verification.material == "PLA"
    assert hd(report.parts).verification.exploded_offset == {0, 0, 10}
    assert Enum.map(report.tree, & &1.name) == ["left", "right"]
    assert Enum.map(hd(report.tree).children, & &1.name) == ["body", "coupon", "board"]
    assert {:ok, refs} = OCEx.read_step(report.references_step)
    volume(refs, 12)
    assert {:ok, combined} = OCEx.read_step(report.assembly_step)
    volume(combined, 48)
    assert {:ok, zip} = :zip.extract(File.read!(report.print_pack), [:memory])
    assert length(zip) == 8

    for part <- report.parts do
      assert part.verification.mesh.watertight
      mesh = part.stl |> File.read!() |> Smith.Mesh.from_stl()
      assert_in_delta Enum.min(Enum.map(mesh.vertices, &elem(&1, 2))), 0, 1.0e-6
    end
  end

  test "path encoding cannot collide with a single part name", %{tmp_dir: root} do
    child = Assembly.new(:child) |> Assembly.part(:b, Smith.box(1, 1, 1))

    recipe =
      Assembly.new(:root)
      |> Assembly.part("a__b", Smith.box(1, 1, 1))
      |> Assembly.subassembly(:a, child)

    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, report} = Smith.export(result, root, name: "fixture", formats: [:three_mf])
    assert Enum.map(report.parts, & &1.name) == ["fixture-a--b", "fixture-a__b"]

    assert {:error, :invalid_metadata} =
             Smith.export(result, root,
               name: "fixture",
               part_metadata: %{[:a, :b] => %{}, "a/b" => %{}}
             )
  end

  test "export rejects a tampered nested leaf before replacing the manifest", %{tmp_dir: root} do
    assert {:ok, result} =
             Assembly.new(:root)
             |> Assembly.subassembly(:branch, module_recipe())
             |> Smith.evaluate()

    assert {:ok, _} = Smith.export(result, root, name: "fixture", formats: [:three_mf])
    before = File.read!(Path.join(root, "current.json"))
    [branch] = result.entries
    [leaf | rest] = branch.result.entries
    {:ok, changed} = OCEx.translate(leaf.result.shape, {1, 0, 0})
    leaf = %{leaf | result: %{leaf.result | shape: changed}}
    branch = %{branch | result: %{branch.result | entries: [leaf | rest]}}

    assert {:error, :revision_mismatch} =
             Smith.export(%{result | entries: [branch]}, root, name: "fixture")

    assert File.read!(Path.join(root, "current.json")) == before
  end

  test "three levels compose noncommuting transforms and accumulate world display offsets" do
    leaf =
      Assembly.new(:leaf)
      |> Assembly.part(:body, Smith.box(2, 3, 4),
        position: {5, 0, 0},
        display_offset: {1, 0, 0},
        exploded_offset: {0, 0, 2}
      )

    middle =
      Assembly.new(:middle)
      |> Assembly.subassembly(:inner, leaf,
        rotation: {{0, 0, 1}, 90},
        position: {0, 10, 0},
        display_offset: {0, 2, 0},
        exploded_offset: {0, 0, 3}
      )

    root =
      Assembly.new(:root)
      |> Assembly.subassembly(:outer, middle,
        rotation: {{1, 0, 0}, 90},
        position: {30, 0, 0},
        display_offset: {0, 0, 4},
        exploded_offset: {0, 0, 5}
      )

    assert {:ok, result} = Smith.evaluate(root)
    assert {:ok, body} = Assembly.fetch(result, [:outer, :inner, :body])
    assert {:ok, {low, high}} = OCEx.bounds(body.shape)

    for {actual, expected} <- Enum.zip(Tuple.to_list(low), [27, -4, 15]),
        do: assert_in_delta(actual, expected, 1.0e-7)

    for {actual, expected} <- Enum.zip(Tuple.to_list(high), [30, 0, 17]),
        do: assert_in_delta(actual, expected, 1.0e-7)

    assert {:ok, [member]} = Assembly.members(result)
    assert member.options[:display_offset] == {1, 2, 4}
    assert member.options[:exploded_offset] == {0, 0, 10}
    assert :ok = Assembly.validate_result(result)
  end

  test "retiring an entire branch removes its current leaf exports", %{tmp_dir: root} do
    child = Assembly.new(:child) |> Assembly.part(:body, Smith.box(2, 3, 4))

    full =
      Assembly.new(:root)
      |> Assembly.subassembly(:left, child)
      |> Assembly.subassembly(:right, child)

    assert {:ok, original} = Smith.evaluate(full)
    assert {:ok, first} = Smith.export(original, root, name: "fixture", formats: [:three_mf])
    reduced = Assembly.new(:root) |> Assembly.subassembly(:left, child)
    assert {:ok, result} = Smith.evaluate(reduced)
    assert {:ok, _} = Smith.export(result, root, name: "fixture", formats: [:three_mf])
    manifest = root |> Path.join("current.json") |> File.read!() |> JSON.decode!()
    assert Enum.map(manifest["models"], & &1["name"]) == ["fixture-left__body"]
    assert [%{"name" => "left"}] = hd(manifest["assemblies"])["tree"]
    assert File.exists?(first.print_pack)
  end

  test "nested name errors use normalized paths, and empty branches fail at their instance" do
    duplicate =
      Assembly.new(:child)
      |> Assembly.part("a-b", Smith.box(1, 1, 1))
      |> Assembly.part(:a_b, Smith.box(1, 1, 1))

    inner = Assembly.new(:middle) |> Assembly.subassembly(:inner_group, duplicate)

    assert {:error, %Smith.Error{part: "outer-group/inner-group/a-b", reason: :duplicate_part}} =
             Assembly.new(:root) |> Assembly.subassembly(:outer_group, inner) |> Smith.evaluate()

    assert {:error, %Smith.Error{part: :empty, reason: :no_installed_parts}} =
             Assembly.new(:root)
             |> Assembly.subassembly(:empty, Assembly.new(:empty))
             |> Smith.evaluate()
  end
end
