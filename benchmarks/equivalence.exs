source =
  File.read!(List.first(System.argv()) || raise("pass the baseline mesh.ex path"))
  |> String.replace("defmodule Smith.Mesh do", "defmodule Smith.ReferenceMesh do")

Code.compile_string(source)
:rand.seed(:exsss, {71, 82, 93})

for _ <- 1..1000 do
  vertices =
    for _ <- 1..30, do: {:rand.uniform() * 10, :rand.uniform() * 10, :rand.uniform() * 10}

  triangles =
    for _ <- 1..:rand.uniform(100),
        do: {:rand.uniform(30) - 1, :rand.uniform(30) - 1, :rand.uniform(30) - 1}

  mesh = %{vertices: vertices, triangles: triangles}
  true = Smith.Mesh.inspect(mesh) == Smith.ReferenceMesh.inspect(mesh)
  true = Smith.Mesh.to_stl(mesh) == Smith.ReferenceMesh.to_stl(mesh)
end

IO.puts("1000 seeded arbitrary meshes: identical inspection reports and STL bytes")
