defmodule Smith.ExportTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "exports installed and print orientations, verifies files, and publishes a revision", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.box(2, 3, 4) |> Smith.evaluate()

    assert {:ok, record} =
             Smith.Export.write(result, root,
               name: "bracket",
               print_rotation: {{1, 0, 0}, 180},
               print_offset: {0, 0, 4},
               display_offset: {20, 0, 0},
               metadata: %{purpose: "test"},
               step_tolerance: 1.0e-5
             )

    assert record.revision == result.revision
    {:ok, restored} = OCEx.read_step(record.step)
    assert OCEx.bounds(restored) == {:ok, {{0.0, 0.0, 0.0}, {2.0, 3.0, 4.0}}}
    mesh = record.stl |> File.read!() |> Smith.Mesh.from_stl()
    ys = Enum.map(mesh.vertices, &elem(&1, 1))
    assert_in_delta Enum.min(ys), -3, 1.0e-6
    assert_in_delta Enum.max(ys), 0, 1.0e-6
    assert record.verification.mesh.watertight
    assert record.verification.purpose == "test"
    assert record.verification.step_volume_tolerance == 1.0e-5
    assert Enum.min(Enum.map(record.mesh.vertices, &elem(&1, 0))) >= 20
    assert {:ok, _} = :zip.extract(File.read!(record.three_mf), [:memory])
    manifest = root |> Path.join("current.json") |> File.read!() |> JSON.decode!()
    assert [%{"name" => "bracket", "revision" => revision}] = manifest["models"]
    assert revision == result.revision
  end

  @tag :tmp_dir
  test "publishing one model preserves the other current records", %{tmp_dir: root} do
    first = %{name: "clip", revision: "one"}
    other = %{name: "stand", revision: "two"}
    assert {:ok, :ok} = Smith.Export.publish(first, root)
    assert {:ok, :ok} = Smith.Export.publish(other, root)
    assert {:ok, :ok} = Smith.Export.publish(%{first | revision: "three"}, root)
    manifest = root |> Path.join("current.json") |> File.read!() |> JSON.decode!()

    assert manifest["models"] == [
             %{"name" => "clip", "revision" => "three"},
             %{"name" => "stand", "revision" => "two"}
           ]

    refute File.exists?(Path.join(root, "current.json.tmp"))
  end

  @tag :tmp_dir
  test "invalid exports never replace a current manifest", %{tmp_dir: root} do
    {:ok, result} = Smith.box(2, 3, 4) |> Smith.evaluate()
    assert {:ok, _} = Smith.Export.write(result, root, name: "good")
    path = Path.join(root, "current.json")
    before = File.read!(path)

    assert {:error, :revision_mismatch} =
             Smith.Export.write(%{result | revision: "stale"}, root, name: "bad")

    assert {:error, :invalid_options} = Smith.Export.write(result, root, name: "../bad")
    assert {:error, :invalid_options} = Smith.Export.write(result, root, name: "bad", typo: true)
    assert {:error, _} = Smith.Export.write(result, root, name: "bad", tolerance: -1)
    assert {:error, _} = Smith.Export.write(result, path, name: "bad")

    assert {:error, :invalid_options} =
             Smith.Export.write(result, root, name: "bad", step_tolerance: 0)

    assert File.read!(path) == before
  end

  @tag :tmp_dir
  test "bundle meshing honors and records angular tolerance", %{tmp_dir: root} do
    {:ok, result} = Smith.cylinder(10, 5) |> Smith.evaluate()

    {:ok, coarse} =
      Smith.Export.write(result, root, name: "coarse", tolerance: 0.5, angular_tolerance: 0.2)

    {:ok, fine} =
      Smith.Export.write(result, root, name: "fine", tolerance: 0.5, angular_tolerance: 0.05)

    coarse_mesh = coarse.stl |> File.read!() |> Smith.Mesh.from_stl()
    fine_mesh = fine.stl |> File.read!() |> Smith.Mesh.from_stl()
    assert length(fine_mesh.triangles) > 2 * length(coarse_mesh.triangles)
    assert fine.verification.mesh.angular_deflection == 0.05
    assert fine.verification.mesh.linear_deflection == 0.5
    assert fine.verification.mesh.watertight
    assert {:ok, files} = :zip.extract(File.read!(fine.three_mf), [:memory])

    {_name, xml} =
      Enum.find(files, fn {name, _} -> List.to_string(name) |> String.ends_with?(".model") end)

    assert length(Regex.scan(~r/<triangle /, xml)) == length(fine_mesh.triangles)
    manifest = File.read!(Path.join(root, "current.json"))

    for angle <- [0, -0.1, :bad] do
      assert {:error, _} = Smith.Export.write(result, root, name: "bad", angular_tolerance: angle)
    end

    assert File.read!(Path.join(root, "current.json")) == manifest
  end

  @tag :tmp_dir
  test "installed display orientation is independent of print placement", %{tmp_dir: root} do
    {:ok, result} = Smith.box(2, 3, 4) |> Smith.translate({0, 0, 10}) |> Smith.evaluate()

    assert {:ok, record} =
             Smith.Export.write(result, root,
               name: "part",
               print_offset: {0, 0, -10},
               display_orientation: :installed
             )

    assert Enum.min(Enum.map(record.mesh.vertices, &elem(&1, 2))) == 10.0
    print = record.stl |> File.read!() |> Smith.Mesh.from_stl()
    assert Enum.min(Enum.map(print.vertices, &elem(&1, 2))) == 0.0

    assert {:error, :invalid_options} =
             Smith.Export.write(result, root, name: "bad", display_orientation: :unknown)
  end

  test "mesh export supports disconnected solids and rejects profiles" do
    {:ok, result} =
      Smith.box(1, 1, 1)
      |> Smith.fuse(Smith.box(1, 1, 1) |> Smith.translate({3, 0, 0}))
      |> Smith.evaluate()

    assert {:ok, %{checks: %{components: 2, watertight: true}}} = Smith.Export.mesh(result.shape)
    {:ok, edge} = OCEx.edge({0, 0, 0}, {1, 0, 0})
    assert {:error, :no_solids} = Smith.Export.mesh(edge)
  end

  @tag :tmp_dir
  test "bundle facade places rotated parts on the bed without moving installed geometry", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.box(2, 3, 4) |> Smith.translate({10, 20, 30}) |> Smith.evaluate()

    assert {:ok, record} =
             Smith.export(result, root,
               name: "part",
               on_bed: true,
               print_rotation: {{1, 0, 0}, 90},
               display_orientation: :installed
             )

    mesh = record.stl |> File.read!() |> Smith.Mesh.from_stl()

    for axis <- [0, 1] do
      coordinates = Enum.map(mesh.vertices, &elem(&1, axis))
      assert_in_delta Enum.min(coordinates) + Enum.max(coordinates), 0, 1.0e-6
    end

    assert_in_delta Enum.min(Enum.map(mesh.vertices, &elem(&1, 2))), 0, 1.0e-6
    assert record.verification.print_placement.on_bed
    assert {:ok, restored} = OCEx.read_step(record.step)
    assert OCEx.bounds(restored) == OCEx.bounds(result.shape)
    assert Enum.min(Enum.map(record.mesh.vertices, &elem(&1, 2))) == 30.0
    assert {:error, :invalid_options} = Smith.export(result, root, name: "bad", on_bed: :yes)

    assert {:error, :invalid_options} =
             Smith.export(result, root, name: "bad", on_bed: true, print_offset: {0, 0, 1})
  end

  @tag :tmp_dir
  test "re-exporting geometry keeps previous printable files intact", %{tmp_dir: root} do
    {:ok, result} = Smith.cylinder(10, 5) |> Smith.evaluate()
    assert {:ok, first} = Smith.Export.write(result, root, name: "part", angular_tolerance: 0.2)
    original = File.read!(first.stl)
    assert {:ok, second} = Smith.Export.write(result, root, name: "part", angular_tolerance: 0.05)
    assert first.revision == second.revision
    refute first.stl == second.stl
    refute first.export_id == second.export_id
    assert File.read!(first.stl) == original
    refute File.read!(second.stl) == original
  end

  @tag :tmp_dir
  test "batch exports replace all requested parts together and retain other models", %{
    tmp_dir: root
  } do
    {:ok, result} = Smith.box(2, 3, 4) |> Smith.evaluate()
    assert {:ok, old} = Smith.Export.write(result, root, name: "existing")
    entries = [{result, [name: "left", on_bed: true]}, {result, [name: "right"]}]
    assert {:ok, [left, right]} = Smith.Export.write_many(entries, root)
    manifest = root |> Path.join("current.json") |> File.read!() |> JSON.decode!()
    assert Enum.map(manifest["models"], & &1["name"]) == ["existing", "left", "right"]
    assert Enum.map(manifest["models"], & &1["stl"]) == [old.stl, left.stl, right.stl]
  end

  @tag :tmp_dir
  test "failed batch leaves prior manifest and files untouched", %{tmp_dir: root} do
    {:ok, result} = Smith.box(2, 3, 4) |> Smith.evaluate()
    {:ok, old} = Smith.Export.write(result, root, name: "left")
    manifest = File.read!(Path.join(root, "current.json"))
    original = File.read!(old.stl)
    entries = [{result, [name: "left"]}, {%{result | revision: "stale"}, [name: "right"]}]

    assert {:error, {:export_failed, "right", :revision_mismatch}} =
             Smith.Export.write_many(entries, root)

    assert File.read!(Path.join(root, "current.json")) == manifest
    assert File.read!(old.stl) == original

    for invalid <- [
          [],
          [:bad],
          [{result, :bad}],
          [{result, [name: "same"]}, {result, [name: "same"]}]
        ] do
      assert {:error, :invalid_options} = Smith.Export.write_many(invalid, root)
    end

    assert File.read!(Path.join(root, "current.json")) == manifest
  end

  @tag :tmp_dir
  test "invalid publication returns errors without changing the manifest", %{tmp_dir: root} do
    valid = %{name: "part", revision: "one"}
    assert {:ok, :ok} = Smith.Export.publish(valid, root)
    before = File.read!(Path.join(root, "current.json"))

    assert {:error, :invalid_argument} =
             Smith.Export.publish(Map.put(valid, :value, self()), root)

    assert {:error, :invalid_argument} = Smith.Export.publish([valid, valid], root)
    assert {:error, :invalid_argument} = Smith.Export.publish([], root)
    assert File.read!(Path.join(root, "current.json")) == before
  end
end
