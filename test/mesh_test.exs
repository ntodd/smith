defmodule Smith.MeshTest do
  use ExUnit.Case, async: true

  test "welded native meshes preserve closed, oriented topology and volume" do
    {:ok, shape} = OCEx.box(2, 3, 4)
    {:ok, raw} = OCEx.mesh(shape)
    mesh = Smith.Mesh.weld(raw)
    assert length(mesh.vertices) == 8

    assert %{watertight: true, winding_consistent: true, components: 1, volume: volume} =
             Smith.Mesh.inspect(mesh)

    assert_in_delta volume, 24, 1.0e-8

    assert Smith.Mesh.from_stl(Smith.Mesh.to_stl(mesh)) |> Smith.Mesh.inspect() ==
             Smith.Mesh.inspect(mesh)

    broken = %{mesh | triangles: tl(mesh.triangles)}
    refute Smith.Mesh.inspect(broken).watertight
    [triangle | rest] = mesh.triangles
    {a, b, c} = triangle
    refute Smith.Mesh.inspect(%{mesh | triangles: [{a, c, b} | rest]}).winding_consistent
  end

  test "welding discards collapsed triangles and duplicates" do
    mesh = %{
      vertices: [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 0}],
      triangles: [{0, 1, 2}, {3, 1, 2}, {0, 0, 1}]
    }

    assert length(Smith.Mesh.weld(mesh).triangles) == 1
  end

  test "3MF includes the mesh and package relationships" do
    {:ok, shape} = OCEx.box(2, 3, 4)
    {:ok, raw} = OCEx.mesh(shape)
    binary = raw |> Smith.Mesh.weld() |> Smith.Mesh.to_3mf()
    {:ok, entries} = :zip.extract(binary, [:memory])
    assert {~c"3D/3dmodel.model", xml} = List.keyfind(entries, ~c"3D/3dmodel.model", 0)
    assert xml =~ "unit=\"millimeter\""
    assert xml =~ "<triangle "
    assert List.keymember?(entries, ~c"_rels/.rels", 0)
  end
end
