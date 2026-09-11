defmodule Smith.AssemblyExportTest do
  use ExUnit.Case, async: true
  alias Smith.Assembly
  @moduletag :tmp_dir

  defp fixture do
    Assembly.new(:fixture)
    |> Assembly.part(:body, Smith.box(2, 3, 4),
      position: {10, 0, 20},
      print: [rotation: {{1, 0, 0}, 180}, on_bed: true],
      exploded_offset: {0, 0, 30}
    )
    |> Assembly.part(:coupon, Smith.box(1, 1, 1),
      installed: false,
      display_offset: {30, 0, 0},
      print: [on_bed: true]
    )
    |> Assembly.reference(:electronics, Smith.box(20, 20, 20))
  end

  test "complete assembly publication separates installed, printable, and reference geometry", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.evaluate(fixture())

    assert {:ok, report} =
             Smith.export(result, root,
               name: "fixture",
               formats: [:step, :stl, :three_mf],
               metadata: %{design_revision: "test"}
             )

    assert report.revision == result.revision
    assert report.metadata.design_revision == "test"
    assert {:ok, installed} = OCEx.read_step(report.assembly_step)
    assert {:ok, volume} = OCEx.volume(installed)
    assert_in_delta volume, 24, 1.0e-8
    assert {:ok, reference} = OCEx.read_step(report.references_step)
    assert {:ok, volume} = OCEx.volume(reference)
    assert_in_delta volume, 8000, 1.0e-8
    assert length(report.parts) == 2
    [body, coupon] = report.parts
    assert body.part == "body"
    assert body.installed
    refute coupon.installed
    printed = body.stl |> File.read!() |> Smith.Mesh.from_stl()
    assert_in_delta Enum.min(Enum.map(printed.vertices, &elem(&1, 2))), 0, 1.0e-6
    manifest = root |> Path.join("current.json") |> File.read!() |> JSON.decode!()
    assert [%{"name" => "fixture", "export_id" => id}] = manifest["assemblies"]
    assert id == report.export_id
    assert Enum.map(manifest["models"], & &1["name"]) == ["fixture-body", "fixture-coupon"]
    assert hd(manifest["models"])["verification"]["exploded_offset"] == [0, 0, 30]
    assert Enum.min(Enum.map(hd(manifest["models"])["mesh"]["vertices"], &Enum.at(&1, 2))) == 20.0
    assert {:ok, files} = :zip.extract(File.read!(report.print_pack), [:memory])
    assert length(files) == 4

    for part <- report.parts, {extension, path} <- [{"stl", part.stl}, {"3mf", part.three_mf}] do
      assert {String.to_charlist(part.name <> "." <> extension), File.read!(path)} in files
    end
  end

  test "replacement removes retired parts, preserves unrelated models and assembly records", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.evaluate(fixture())
    {:ok, first} = Smith.export(result, root, name: "fixture")
    {:ok, box} = Smith.box(1, 1, 1) |> Smith.evaluate()
    assert {:ok, _} = Smith.export(box, root, name: "standalone")

    {:ok, other} =
      Assembly.new(:other) |> Assembly.part(:base, Smith.box(1, 1, 1)) |> Smith.evaluate()

    assert {:ok, _} = Smith.export(other, root, name: "other")

    {:ok, reduced} =
      Assembly.new(:fixture) |> Assembly.part(:body, Smith.box(2, 3, 4)) |> Smith.evaluate()

    assert {:ok, second} = Smith.export(reduced, root, name: "fixture")
    manifest = root |> Path.join("current.json") |> File.read!() |> JSON.decode!()

    assert Enum.sort(Enum.map(manifest["models"], & &1["name"])) == [
             "fixture-body",
             "other-base",
             "standalone"
           ]

    assert Enum.map(manifest["assemblies"], & &1["name"]) == ["fixture", "other"]
    assert File.exists?(first.print_pack)
    refute first.print_pack == second.print_pack
  end

  test "failure after staging printable parts leaves the entire current assembly untouched", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.evaluate(fixture())
    {:ok, previous} = Smith.export(result, root, name: "fixture")
    manifest = File.read!(Path.join(root, "current.json"))
    archive = File.read!(previous.print_pack)
    # Part staging uses fixture-body/..., then assembly output hits a real filesystem failure.
    blocked_root = Path.join(root, "blocked")
    File.mkdir_p!(blocked_root)
    File.write!(Path.join(blocked_root, "current.json"), manifest)
    File.write!(Path.join(blocked_root, "fixture"), "not a directory")
    assert {:error, _} = Smith.export(result, blocked_root, name: "fixture")
    assert Path.wildcard(Path.join(blocked_root, "fixture-body/*/*/model.stl")) != []
    assert File.read!(Path.join(blocked_root, "current.json")) == manifest
    assert File.read!(previous.print_pack) == archive
  end

  test "format selection controls files and archive entries", %{tmp_dir: root} do
    {:ok, result} = Smith.evaluate(fixture())
    assert {:ok, report} = Smith.export(result, root, name: "fixture", formats: [:three_mf])
    assert report.assembly_step == nil
    assert report.references_step == nil
    assert {:ok, entries} = :zip.extract(File.read!(report.print_pack), [:memory])
    assert length(entries) == 2

    for part <- report.parts do
      assert part.step == nil and part.stl == nil
      assert File.exists?(part.three_mf)
      refute File.exists?(Path.join(Path.dirname(part.three_mf), "model.stl"))
    end

    assert {:ok, step_only} = Smith.export(result, root, name: "fixture", formats: [:step])
    assert File.exists?(step_only.assembly_step)
    assert step_only.print_pack == nil
  end

  test "invalid exports and mutated evaluated geometry never change the manifest", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.evaluate(fixture())
    {:ok, _} = Smith.export(result, root, name: "fixture")
    before = File.read!(Path.join(root, "current.json"))

    for opts <- [
          [name: "../bad"],
          [name: "fixture", typo: true],
          [name: "fixture", formats: []],
          [name: "fixture", formats: [:obj]],
          [name: "fixture", formats: [:step, :step]],
          [name: "fixture", metadata: %{pid: self()}],
          [name: "fixture", part_metadata: %{missing: %{}}]
        ] do
      assert {:error, _} = Smith.export(result, root, opts)
    end

    assert {:error, :revision_mismatch} =
             Smith.export(%{result | revision: "stale"}, root, name: "fixture")

    [entry | rest] = result.entries
    {:ok, moved} = OCEx.translate(entry.result.shape, {1, 0, 0})
    changed = %{entry | result: %{entry.result | shape: moved}}

    assert {:error, :revision_mismatch} =
             Smith.export(%{result | entries: [changed | rest]}, root, name: "fixture")

    assert File.read!(Path.join(root, "current.json")) == before
  end

  test "standalone and other assembly exports cannot replace owned parts", %{tmp_dir: root} do
    {:ok, first} =
      Assembly.new(:a) |> Assembly.part("b-c", Smith.box(1, 1, 1)) |> Smith.evaluate()

    {:ok, _} = Smith.export(first, root, name: "a")
    before = File.read!(Path.join(root, "current.json"))
    {:ok, box} = Smith.box(2, 2, 2) |> Smith.evaluate()
    assert {:error, :assembly_part_conflict} = Smith.export(box, root, name: "a-b-c")

    {:ok, second} =
      Assembly.new(:other) |> Assembly.part(:c, Smith.box(2, 2, 2)) |> Smith.evaluate()

    assert {:error, :assembly_part_conflict} = Smith.export(second, root, name: "a-b")
    assert File.read!(Path.join(root, "current.json")) == before
  end

  test "malformed current manifests remain untouched", %{tmp_dir: root} do
    {:ok, result} = Smith.evaluate(fixture())

    for content <- ["not json", JSON.encode!(%{models: [], assemblies: :bad})] do
      File.write!(Path.join(root, "current.json"), content)
      assert {:error, :invalid_manifest} = Smith.export(result, root, name: "fixture")
      assert File.read!(Path.join(root, "current.json")) == content
    end
  end
end
