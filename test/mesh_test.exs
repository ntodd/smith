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

  test "STL stores unit facet normals, coordinates, and zero attributes" do
    mesh = %{
      vertices: [{0, 0, 0}, {2, 0, 0}, {0, 3, 0}],
      triangles: [{0, 1, 2}, {0, 2, 1}, {0, 0, 1}]
    }

    stl = Smith.Mesh.to_stl(mesh)
    assert <<0::640, 3::little-32, records::binary-size(150)>> = stl

    facets =
      for <<nx::little-float-32, ny::little-float-32, nz::little-float-32, ax::little-float-32,
            ay::little-float-32, az::little-float-32, bx::little-float-32, by::little-float-32,
            bz::little-float-32, cx::little-float-32, cy::little-float-32, cz::little-float-32,
            0::little-16 <- records>>,
          do: {{nx, ny, nz}, {ax, ay, az}, {bx, by, bz}, {cx, cy, cz}}

    assert facets == [
             {{0.0, 0.0, 1.0}, {0.0, 0.0, 0.0}, {2.0, 0.0, 0.0}, {0.0, 3.0, 0.0}},
             {{0.0, 0.0, -1.0}, {0.0, 0.0, 0.0}, {0.0, 3.0, 0.0}, {2.0, 0.0, 0.0}},
             {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, {2.0, 0.0, 0.0}}
           ]
  end

  test "connectivity uses shared edges, including nonmanifold edges" do
    vertices = [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {0, -1, 0}]

    for triangles <- [
          [{0, 1, 2}, {1, 0, 3}, {0, 1, 4}],
          [{0, 1, 4}, {1, 0, 3}, {0, 1, 2}]
        ] do
      report = Smith.Mesh.inspect(%{vertices: vertices, triangles: triangles})
      assert report.components == 1
      refute report.watertight
      refute report.winding_consistent
    end

    report = Smith.Mesh.inspect(%{vertices: vertices, triangles: [{0, 1, 2}, {0, 3, 4}]})
    assert report.components == 2
  end

  test "empty meshes and isolated triangles retain component semantics" do
    assert Smith.Mesh.inspect(%{vertices: [], triangles: []}) == %{
             watertight: false,
             winding_consistent: true,
             components: 0,
             volume: 0.0,
             vertices: 0,
             triangles: 0
           }

    vertices = for i <- 0..299, do: {i, rem(i, 2), 0}
    triangles = for i <- 0..99, do: {3 * i, 3 * i + 1, 3 * i + 2}
    assert Smith.Mesh.inspect(%{vertices: vertices, triangles: triangles}).components == 100
  end

  test "disconnected closed shells sum signed volume and preserve winding checks" do
    {:ok, shape} = OCEx.box(2, 3, 4)
    {:ok, raw} = OCEx.mesh(shape)
    mesh = Smith.Mesh.weld(raw)
    n = length(mesh.vertices)
    shifted = Enum.map(mesh.vertices, fn {x, y, z} -> {x + 10, y, z} end)
    triangles = Enum.map(mesh.triangles, fn {a, b, c} -> {a + n, b + n, c + n} end)

    report =
      Smith.Mesh.inspect(%{
        vertices: mesh.vertices ++ shifted,
        triangles: mesh.triangles ++ triangles
      })

    assert report.components == 2
    assert report.watertight
    assert report.winding_consistent
    assert_in_delta report.volume, 48, 1.0e-8
  end
end
