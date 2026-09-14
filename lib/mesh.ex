defmodule Smith.Mesh do
  @moduledoc """
  Low-level indexed triangle utilities used by the exporter.

  A mesh has `:vertices` (world `{x, y, z}` tuples) and `:triangles`
  (zero-based `{a, b, c}` indices into that vertex list). Native meshes
  from `OCEx.mesh/3` need welding to share indices across face boundaries.

  These functions return maps or binaries directly, not tagged results.
  They assume trusted, well-formed mesh data and may raise on malformed
  input. For normal print output, use `Smith.export/3`, which handles
  meshing, checks, serialization, and files together.
  """

  @doc """
  Merges vertices assigned to the same grid cell and remaps triangles.

  `tolerance` is the grid spacing in model units, default 1.0e-6. Each
  coordinate is divided by that spacing and rounded to form a key. The
  first vertex in each cell is retained at its original coordinates;
  vertices are not snapped to the grid or averaged.

  Triangles with repeated indices after welding are removed. Duplicate
  triangles are removed regardless of winding. Collinear triangles with
  three distinct indices are not removed. Only `:vertices` and
  `:triangles` are retained in the returned map.

  This function assumes valid indices and a positive tolerance. It returns
  a mesh directly and may raise on malformed data.
  """
  @spec weld(map(), number()) :: map()
  def weld(%{vertices: vertices, triangles: triangles}, tolerance \\ 1.0e-6) do
    {_, points, indices} =
      Enum.reduce(vertices, {%{}, [], []}, fn {x, y, z} = point, {lookup, points, indices} ->
        key = {round(x / tolerance), round(y / tolerance), round(z / tolerance)}

        case Map.fetch(lookup, key) do
          {:ok, index} ->
            {lookup, points, [index | indices]}

          :error ->
            index = map_size(lookup)
            {Map.put(lookup, key, index), [point | points], [index | indices]}
        end
      end)

    indices = indices |> Enum.reverse() |> List.to_tuple()

    triangles =
      triangles
      |> Enum.map(fn {a, b, c} -> {elem(indices, a), elem(indices, b), elem(indices, c)} end)
      |> Enum.reject(fn {a, b, c} -> a == b or a == c or b == c end)
      |> Enum.uniq_by(fn {a, b, c} -> Enum.sort([a, b, c]) end)

    %{vertices: Enum.reverse(points), triangles: triangles}
  end

  @doc """
  Reports edge connectivity, winding, counts, and signed mesh volume.

  Returns a map directly:

    * `:watertight` — at least one edge exists and every edge belongs to
      exactly two triangles.
    * `:winding_consistent` — each shared edge is traversed in opposite
      directions by its two triangles. For an empty mesh this is `true`.
    * `:components` — number of triangle groups connected by shared edges.
    * `:volume` — signed volume in cubic model units.
    * `:vertices`, `:triangles` — input list lengths.

  It does not weld vertices first. Call `weld/2` on native face meshes
  before inspecting connectivity. Consistent winding does not necessarily
  mean outward winding; an entirely reversed shell has negative volume.
  The checks do not detect arbitrary triangle self-intersections or prove
  manifold vertex neighborhoods.

      iex> {:ok, box} = OCEx.box(2, 3, 4)
      iex> {:ok, raw} = OCEx.mesh(box)
      iex> report = raw |> Smith.Mesh.weld() |> Smith.Mesh.inspect()
      iex> {report.watertight, report.winding_consistent, report.components,
      ...>  report.volume}
      {true, true, 1, 24.0}

  <div class="smith-doc-preview" data-preview="api-mesh-0" data-model="raw" data-label="Inspected mesh">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @spec inspect(map()) :: map()
  def inspect(%{vertices: vertices, triangles: triangles}) do
    points = List.to_tuple(vertices)

    edges =
      triangles
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {{a, b, c}, i}, acc ->
        Enum.reduce([{a, b}, {b, c}, {c, a}], acc, fn {u, v}, acc ->
          key = {min(u, v), max(u, v)}
          Map.update(acc, key, [{i, u < v}], &[{i, u < v} | &1])
        end)
      end)

    watertight = map_size(edges) > 0 and Enum.all?(edges, fn {_, uses} -> length(uses) == 2 end)

    winding =
      Enum.all?(edges, fn {_, uses} ->
        case uses do
          [{_, a}, {_, b}] -> a != b
          _ -> false
        end
      end)

    adjacency =
      Enum.reduce(edges, %{}, fn {_, uses}, acc ->
        ids = Enum.map(uses, &elem(&1, 0))
        Enum.reduce(ids, acc, fn id, acc -> Map.update(acc, id, ids, &(ids ++ &1)) end)
      end)

    remaining = triangles |> Enum.with_index() |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    volume =
      Enum.reduce(triangles, 0.0, fn {a, b, c}, total ->
        total + dot(elem(points, a), cross(elem(points, b), elem(points, c))) / 6
      end)

    %{
      watertight: watertight,
      winding_consistent: winding,
      components: components(remaining, adjacency, 0),
      volume: volume,
      vertices: length(vertices),
      triangles: length(triangles)
    }
  end

  defp components(remaining, adjacency, count) do
    if MapSet.size(remaining) == 0 do
      count
    else
      first = Enum.at(remaining, 0)
      components(visit([first], remaining, adjacency), adjacency, count + 1)
    end
  end

  defp visit([], remaining, _), do: remaining

  defp visit([id | queue], remaining, adjacency) do
    if MapSet.member?(remaining, id),
      do: visit(Map.get(adjacency, id, []) ++ queue, MapSet.delete(remaining, id), adjacency),
      else: visit(queue, remaining, adjacency)
  end

  @doc """
  Serializes a mesh as binary STL, returning bytes without writing a file.

  Writes 32-bit float coordinates and calculated facet normals. STL does
  not store units. Vertex precision can change during serialization, so
  `Smith.Export.mesh/3` checks the parsed STL rather than just this input.
  No topology or volume validation is performed here.
  """
  @spec to_stl(map()) :: binary()
  def to_stl(%{vertices: vertices, triangles: triangles}) do
    points = List.to_tuple(vertices)

    records =
      Enum.map(triangles, fn {a, b, c} ->
        a = elem(points, a)
        b = elem(points, b)
        c = elem(points, c)
        n = cross(subtract(b, a), subtract(c, a))
        length = :math.sqrt(dot(n, n))
        normal = if length > 0, do: scale(n, 1 / length), else: {0, 0, 0}
        [float3(normal), float3(a), float3(b), float3(c), <<0::little-16>>]
      end)

    IO.iodata_to_binary([:binary.copy(<<0>>, 80), <<length(triangles)::little-32>>, records])
  end

  @doc """
  Parses a binary STL and welds the resulting vertices.

  Requires an 80-byte header, a 32-bit little-endian triangle count, and
  exactly 50 bytes per triangle. Facet normals and attribute words are
  ignored. Vertices are welded with the default tolerance of `weld/2`;
  the result is a mesh map, not a tagged result.

  This utility is for trusted binary data. ASCII STL, truncated records,
  trailing bytes, and unsupported float encodings are not handled as
  tagged errors and may raise Elixir exceptions.

      iex> {:ok, box} = OCEx.box(2, 3, 4)
      iex> {:ok, raw} = OCEx.mesh(box)
      iex> mesh = raw |> Smith.Mesh.to_stl() |> Smith.Mesh.from_stl()
      iex> {length(mesh.vertices), length(mesh.triangles)}
      {8, 12}

  <div class="smith-doc-preview" data-preview="api-mesh-1" data-model="mesh" data-label="STL round trip">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @spec from_stl(binary()) :: map()
  def from_stl(<<_header::binary-size(80), count::little-32, records::binary>>)
      when byte_size(records) == count * 50 do
    vertices =
      for <<_normal::binary-size(12), a::binary-size(12), b::binary-size(12), c::binary-size(12),
            _::little-16 <- records>>,
          point <- [a, b, c],
          do: read3(point)

    triangles =
      if count == 0, do: [], else: for(i <- 0..(count - 1), do: {3 * i, 3 * i + 1, 3 * i + 2})

    weld(%{vertices: vertices, triangles: triangles})
  end

  @doc """
  Serializes a mesh as a geometry-only 3MF ZIP archive.

  Returns archive bytes without writing a file. The archive contains one
  mesh object and one build item, with millimeter units. Disconnected
  components remain within that one object. There are no materials,
  printer profiles, support settings, or slicer configuration.

  This function does not validate the mesh. Use `Smith.export/3` to run
  print mesh checks before producing files.
  """
  @spec to_3mf(map()) :: binary()
  def to_3mf(%{vertices: vertices, triangles: triangles}) do
    points = Enum.map(vertices, fn {x, y, z} -> ~s(<vertex x="#{x}" y="#{y}" z="#{z}"/>) end)

    facets =
      Enum.map(triangles, fn {a, b, c} -> ~s(<triangle v1="#{a}" v2="#{b}" v3="#{c}"/>) end)

    model =
      IO.iodata_to_binary([
        ~s(<?xml version="1.0" encoding="UTF-8"?><model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><resources><object id="1" type="model"><mesh><vertices>),
        points,
        "</vertices><triangles>",
        facets,
        "</triangles></mesh></object></resources><build><item objectid=\"1\"/></build></model>"
      ])

    types =
      ~s(<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>)

    rels =
      ~s(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>)

    {:ok, {_, binary}} =
      :zip.create(
        ~c"model.3mf",
        [
          {~c"[Content_Types].xml", types},
          {~c"_rels/.rels", rels},
          {~c"3D/3dmodel.model", model}
        ],
        [:memory]
      )

    binary
  end

  defp float3({x, y, z}), do: <<x::little-float-32, y::little-float-32, z::little-float-32>>
  defp read3(<<x::little-float-32, y::little-float-32, z::little-float-32>>), do: {x, y, z}
  defp subtract({a, b, c}, {x, y, z}), do: {a - x, b - y, c - z}
  defp cross({a, b, c}, {x, y, z}), do: {b * z - c * y, c * x - a * z, a * y - b * x}
  defp dot({a, b, c}, {x, y, z}), do: a * x + b * y + c * z
  defp scale({x, y, z}, k), do: {x * k, y * k, z * k}
end
