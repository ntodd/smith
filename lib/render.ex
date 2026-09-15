defmodule Smith.Render do
  @moduledoc """
  Headless orthographic PNG observations of evaluated geometry.

  Uses OCEx tessellation and an Elixir software depth buffer. It requires no
  browser, GPU, display server, Python, or Kino. Images are mesh observations,
  not metrology: use `Smith.Measure` and `Smith.Inspection` for BREP checks.
  Independent opaque layers support colored stage differences.
  """
  alias Smith.{Geometry, Plane, Measure}
  @type view :: :isometric | :top | :bottom | :front | :back | :left | :right | Plane.t()
  @type color :: {0..255, 0..255, 0..255}
  @type source :: Measure.source() | [{Measure.source(), color()}]

  @doc """
  Renders a source, or a list of `{source, rgb}` layers, to a PNG binary.

  Options:

    * `view: :isometric` — named view or explicit `Smith.Plane`. Top looks
      from +Z, front from −Y, right from +X. Opposite views reverse those axes.
      Plane-local X is screen-right and local Y screen-up.
    * `width: 640`, `height: 480` — integer pixel dimensions, 32–2048 each,
      with at most 2,097,152 pixels. The model fits with a 6% margin.
    * `color: {62, 153, 183}` — default surface RGB; explicit layers override it.
    * `tolerance: 0.03`, `angular_tolerance: 0.3` — OCEx mesh deflections.
    * `edges: false` — draw sampled native edges with depth testing.
    * `clip: {plane, :positive | :negative}` — discard material on the other
      side for observation. Clipping does not cap the mesh or alter geometry;
      use `Smith.section/2` for a measured section face.

  Shading is flat, surfaces are opaque, and a depth buffer resolves visibility.
  PNG metadata records source revisions and view. Empty geometry returns
  `:empty_shape`. Invalid options return `:invalid_options`; geometry failures
  propagate. Rendering runs synchronously in the calling process.
  """
  @spec png(source(), keyword()) :: {:ok, binary()} | {:error, term()}
  def png(source, opts \\ []) do
    with {:ok, config} <- config(opts),
         {:ok, frame} <- Plane.frame(view_plane(config.view)),
         {:ok, clip} <- clip_frame(config.clip),
         {:ok, layers} <- layers(source, config),
         points =
           Enum.flat_map(layers, fn layer -> layer.mesh.vertices ++ List.flatten(layer.lines) end),
         true <- points != [] do
      projected = Enum.map(points, &project(&1, frame))
      low = for i <- 0..2, do: projected |> Enum.map(&elem(&1, i)) |> Enum.min()
      high = for i <- 0..2, do: projected |> Enum.map(&elem(&1, i)) |> Enum.max()
      [xmin, ymin, zmin] = low
      [xmax, ymax, zmax] = high

      scale =
        min(
          config.width * 0.88 / max(xmax - xmin, 1.0e-9),
          config.height * 0.88 / max(ymax - ymin, 1.0e-9)
        )

      screen = fn point ->
        {x, y, z} = project(point, frame)

        {config.width / 2 + (x - (xmin + xmax) / 2) * scale,
         config.height / 2 - (y - (ymin + ymax) / 2) * scale,
         (z - zmin) / max(zmax - zmin, 1.0e-9)}
      end

      buffer = :atomics.new(config.width * config.height, signed: false)

      for layer <- layers do
        vertices = List.to_tuple(layer.mesh.vertices)

        for {i, j, k} <- layer.mesh.triangles do
          world = Enum.map([i, j, k], &elem(vertices, &1))
          [a, b, c] = Enum.map(world, screen)
          rgb = shade(world, layer.color, frame)
          distances = Enum.map(world, &clip_distance(&1, clip))
          triangle(buffer, [a, b, c], distances, rgb, config)
        end
      end

      for layer <- layers,
          line <- layer.lines,
          [a, b] <- Enum.chunk_every(line, 2, 1, :discard) do
        edge(
          buffer,
          screen.(a),
          screen.(b),
          clip_distance(a, clip),
          clip_distance(b, clip),
          config
        )
      end

      rows =
        for y <- 0..(config.height - 1) do
          pixels =
            for x <- 0..(config.width - 1), into: <<>> do
              pixel = :atomics.get(buffer, y * config.width + x + 1)
              rgb = if pixel == 0, do: 0xF0F5FA, else: Bitwise.band(pixel, 0xFFFFFF)
              <<rgb::24>>
            end

          <<0, pixels::binary>>
        end

      metadata =
        JSON.encode!(%{
          revisions: Enum.map(layers, & &1.revision),
          view: Geometry.json(config.view),
          units: "mm",
          tolerance: config.tolerance,
          clip: Geometry.json(config.clip)
        })

      png =
        <<137, 80, 78, 71, 13, 10, 26, 10>> <>
          chunk("IHDR", <<config.width::32, config.height::32, 8, 2, 0, 0, 0>>) <>
          chunk("tEXt", "Smith" <> <<0>> <> metadata) <>
          chunk("IDAT", :zlib.compress(IO.iodata_to_binary(rows))) <> chunk("IEND", <<>>)

      {:ok, png}
    else
      false -> {:error, :empty_shape}
      error -> error
    end
  end

  @doc "Writes a PNG after successful rendering. The parent directory must exist; returns `{:ok, path}` or a tagged error."
  @spec write(source(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def write(source, path, opts \\ []) do
    with {:ok, png} <- png(source, opts), :ok <- File.write(path, png), do: {:ok, path}
  end

  @doc false
  def view_plane(:top), do: Plane.xy()
  def view_plane(:bottom), do: Plane.new(normal: {0, 0, -1})
  def view_plane(:front), do: Plane.xz()
  def view_plane(:back), do: Plane.new(normal: {0, 1, 0}, x_direction: {-1, 0, 0})
  def view_plane(:right), do: Plane.yz()
  def view_plane(:left), do: Plane.new(normal: {-1, 0, 0}, x_direction: {0, -1, 0})
  def view_plane(:isometric), do: Plane.new(normal: {1, -1, 1}, x_direction: {1, 1, 0})
  def view_plane(%Plane{} = plane), do: plane
  def view_plane(_), do: nil

  defp config(opts) do
    defaults = %{
      view: :isometric,
      width: 640,
      height: 480,
      color: {62, 153, 183},
      tolerance: 0.03,
      angular_tolerance: 0.3,
      edges: false,
      clip: nil
    }

    if Geometry.options(opts, Map.keys(defaults)) do
      c = Map.merge(defaults, Map.new(opts))

      if is_integer(c.width) and c.width in 32..2048 and is_integer(c.height) and
           c.height in 32..2048 and c.width * c.height <= 2_097_152 and
           color?(c.color) and view_plane(c.view) != nil and is_boolean(c.edges) and
           is_number(c.tolerance) and c.tolerance > 1.0e-7 and
           is_number(c.angular_tolerance) and c.angular_tolerance > 1.0e-7,
         do: {:ok, c},
         else: {:error, :invalid_options}
    else
      {:error, :invalid_options}
    end
  end

  defp color?({r, g, b}), do: Enum.all?([r, g, b], &(is_integer(&1) and &1 in 0..255))
  defp color?(_), do: false

  defp layers(source, config) do
    sources = if is_list(source), do: source, else: [{source, config.color}]

    Geometry.collect(sources, fn
      {source, color} ->
        with true <- color?(color),
             {:ok, result} <- Geometry.result(source),
             {:ok, mesh} <- OCEx.mesh(result.shape, config.tolerance, config.angular_tolerance),
             {:ok, lines} <-
               if(config.edges or mesh.triangles == [],
                 do: OCEx.polylines(result.shape, config.tolerance, config.angular_tolerance),
                 else: {:ok, []}
               ) do
          {:ok, %{mesh: mesh, lines: lines, color: color, revision: result.revision}}
        else
          false -> {:error, :invalid_options}
          error -> error
        end

      _ ->
        {:error, :invalid_options}
    end)
  end

  defp project(point, frame) do
    p = Geometry.vector(point, frame.origin)
    {Geometry.dot(p, frame.u), Geometry.dot(p, frame.v), Geometry.dot(p, frame.n)}
  end

  defp clip_frame(nil), do: {:ok, nil}

  defp clip_frame({%Plane{} = plane, keep}) when keep in [:positive, :negative] do
    with {:ok, frame} <- Plane.frame(plane),
         do: {:ok, {frame, if(keep == :positive, do: 1, else: -1)}}
  end

  defp clip_frame(_), do: {:error, :invalid_options}
  defp clip_distance(_, nil), do: 1.0

  defp clip_distance(point, {frame, sign}),
    do: Geometry.dot(Geometry.vector(point, frame.origin), frame.n) * sign

  defp shade([a, b, c], color, frame) do
    {ux, uy, uz} = Geometry.vector(b, a)
    {vx, vy, vz} = Geometry.vector(c, a)
    n = {uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx}
    n = Geometry.scale(n, 1 / max(Geometry.norm(n), 1.0e-12))
    n = if Geometry.dot(n, frame.n) < 0, do: Geometry.scale(n, -1), else: n

    light =
      Geometry.add(
        frame.n,
        Geometry.add(Geometry.scale(frame.u, -0.4), Geometry.scale(frame.v, 0.7))
      )

    brightness = 0.32 + 0.68 * max(0, Geometry.dot(n, light) / Geometry.norm(light))
    [r, g, b] = color |> Tuple.to_list() |> Enum.map(&round(&1 * brightness))
    r * 65536 + g * 256 + b
  end

  defp triangle(buffer, [{ax, ay, az}, {bx, by, bz}, {cx, cy, cz}], [ad, bd, cd], color, c) do
    denominator = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    xmin = max(0, floor(min(ax, min(bx, cx))))
    xmax = min(c.width - 1, ceil(max(ax, max(bx, cx))))
    ymin = max(0, floor(min(ay, min(by, cy))))
    ymax = min(c.height - 1, ceil(max(ay, max(by, cy))))

    if abs(denominator) > 1.0e-12 and xmin <= xmax and ymin <= ymax do
      for y <- ymin..ymax, x <- xmin..xmax do
        a = ((by - cy) * (x + 0.5 - cx) + (cx - bx) * (y + 0.5 - cy)) / denominator
        b = ((cy - ay) * (x + 0.5 - cx) + (ax - cx) * (y + 0.5 - cy)) / denominator
        d = 1 - a - b

        if a >= -1.0e-9 and b >= -1.0e-9 and d >= -1.0e-9 and a * ad + b * bd + d * cd >= 0,
          do: pixel(buffer, x, y, a * az + b * bz + d * cz, color, c.width)
      end
    end
  end

  defp edge(buffer, {ax, ay, az}, {bx, by, bz}, ad, bd, c) do
    count = max(1, ceil(max(abs(bx - ax), abs(by - ay))))

    for i <- 0..count do
      t = i / count
      x = round(ax + (bx - ax) * t)
      y = round(ay + (by - ay) * t)

      if x >= 0 and x < c.width and y >= 0 and y < c.height and ad + (bd - ad) * t >= 0,
        do: pixel(buffer, x, y, az + (bz - az) * t + 1.0e-5, 0x243440, c.width)
    end
  end

  defp pixel(buffer, x, y, z, color, width) do
    depth = round(max(0, min(1.01, z)) * 1_000_000_000) + 1
    value = depth * 16_777_216 + color
    index = y * width + x + 1
    if value > :atomics.get(buffer, index), do: :atomics.put(buffer, index, value)
  end

  defp chunk(kind, data),
    do: <<byte_size(data)::32, kind::binary, data::binary, :erlang.crc32(kind <> data)::32>>
end
