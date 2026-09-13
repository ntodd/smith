defmodule Smith.Sketch do
  @moduledoc """
  Deferred planar outlines with optional cutouts and corner rounding.

  Build an outline with `rectangle/3`, `circle/2`, `polygon/2`, or
  `profile/2`. Coordinates are local to a `Smith.Plane`; standalone
  sketches default to XY at Z=0. Distances are millimeters.

      iex> outline =
      ...>   Smith.Sketch.rectangle(40, 20) |> Smith.Sketch.cut(Smith.Sketch.circle(3))
      iex> {:ok, face} = Smith.evaluate(outline)
      iex> OCEx.shape_type(face.shape)
      {:ok, :face}

  Use `Smith.extrude/2`, `Smith.revolve/4`, `Smith.loft/2`, or
  `Smith.sweep/3` to build solid model recipes. A bare sketch evaluates to one face and cannot be
  exported as a printable bundle.

  Sketches have no constraint solver. Their local coordinates, dimensions,
  and cuts come from ordinary Elixir calculations. Validation runs when
  evaluated, and cuts must retain one connected face. Rounding belongs to
  the original outline and is always applied before its cuts.

  See [sketches and planes](sketches.html) for coordinate conventions and
  examples of side planes, holes, and solid generation.
  """
  alias Smith.Plane
  defstruct [:kind, :data, rounding: :none, plane: :default, options: [], cuts: []]

  @type t :: %__MODULE__{
          kind: atom(),
          data: term(),
          plane: Plane.t() | :default,
          rounding: keyword() | :none,
          options: keyword(),
          cuts: [term()]
        }
  @doc """
  Describes a rectangle with a width and height in local millimeters.

  Both dimensions must be positive; native size tolerances apply at
  evaluation. The default bounds are centered on local `{0, 0}`.

  ## Options

    * `:on` — a `Smith.Plane`. A standalone sketch defaults to XY at Z=0.
    * `:at` — local anchor `{u, v}`, default `{0, 0}`.
    * `:align` — `{x_alignment, y_alignment}`, each `:min`, `:center`,
      or `:max`. Defaults to `{:center, :center}`. The chosen point of
      the local bounds lands at `:at`.

  `align: :none` uses the unaligned rectangle `{0, 0}..{width, height}`,
  then adds `:at`. Unknown/duplicate options return
  `:invalid_sketch_options` at evaluation; unsupported alignments return
  `:invalid_alignment`.

      iex> sketch = Smith.Sketch.rectangle(4, 6, align: {:min, :max}, at: {10, 20})
      iex> {:ok, face} = Smith.evaluate(sketch)
      iex> OCEx.bounds(face.shape)
      {:ok, {{10.0, 14.0, 0.0}, {14.0, 20.0, 0.0}}}
  """
  @spec rectangle(number(), number(), keyword()) :: t()
  def rectangle(width, height, opts \\ []),
    do: %__MODULE__{kind: :rectangle, data: {width, height}, options: opts}

  @doc """
  Describes a rectangle with four circular corner rounds of `radius` mm.

  Supports the placement options of `rectangle/3`. Equivalent to a rectangle
  followed by `fillet/2`; rounding precedes subsequent cutouts. Radius must
  be positive and smaller than half either dimension, allowing for native
  tolerance. Use `slot/3` for semicircular ends meeting at the full width.
  """
  @spec rounded_rectangle(number(), number(), number(), keyword()) :: t()
  def rounded_rectangle(width, height, radius, opts \\ []),
    do: rectangle(width, height, opts) |> fillet(radius: radius)

  @doc """
  Describes a straight slot along local X with semicircular ends.

  `length` is the overall end-to-end dimension; `width` is the diameter
  of each end, both in mm. Length must be at least width, and width must
  exceed 1.0e-7 mm. A nonzero straight span (length minus width) must also
  exceed the native edge tolerance of 1.0e-7 mm. Equal dimensions produce
  a circle. Smaller length or
  invalid dimensions fail with `:invalid_sketch` at evaluation.

  Supports `:on`, `:at`, and `:align` as in `rectangle/3`, defaulting
  to centered alignment. `align: :none` also retains a centered outline.
  Use `cut/2` to subtract this sketch from another outline.
  """
  @spec slot(number(), number(), keyword()) :: t()
  def slot(length, width, opts \\ []),
    do: %__MODULE__{kind: :slot, data: {length, width}, options: opts}

  @doc """
  Describes a circle by radius in local millimeters.

  Radius must exceed the native tolerance of 1.0e-7 mm at evaluation.
  Supports the options of `rectangle/3`, defaulting to centered alignment.
  `:at` therefore places the circle center unless another alignment is
  chosen. `align: :none` retains a center at local zero before adding `:at`.

  The sketch evaluates to a disk face. Use `cut/2` to make a ring, or
  `Smith.extrude/2` to make a cylinder.
  """
  @spec circle(number(), keyword()) :: t()
  def circle(radius, opts \\ []), do: %__MODULE__{kind: :circle, data: radius, options: opts}

  @doc """
  Describes a closed polygon from at least three local `{u, v}` points.

  Closure is implicit; do not repeat the first point. The outline must
  enclose nonzero area and form a valid face. Concave polygons are allowed
  without `fillet/2`.

  Supports `:on`, `:at`, and `:align` as in `rectangle/3`. Alignment
  defaults to `:none`: supplied coordinates are retained, then shifted by
  `:at`. Explicit alignment uses the bounds of those coordinates.
  """
  @spec polygon([{number(), number()}], keyword()) :: t()
  def polygon(points, opts \\ []), do: %__MODULE__{kind: :polygon, data: points, options: opts}

  @doc """
  Describes a closed outline made from local lines, circular arcs, and interpolated splines.

  Supply a nonempty list of `line/2`, `arc/4`, and `spline/2` descriptions in connected
  boundary order. Options are `:on` and `:at` as in `rectangle/3`.
  Coordinates are retained and shifted by `:at`; `:align` is not accepted.
  Open, disconnected, and invalid boundaries fail during evaluation.

      iex> sketch =
      ...>   Smith.Sketch.profile([
      ...>     Smith.Sketch.arc({0, 0}, 2, 0, 180),
      ...>     Smith.Sketch.line({-2, 0}, {2, 0})
      ...>   ])
      iex> {:ok, face} = Smith.evaluate(sketch)
      iex> {:ok, area} = OCEx.area(face.shape)
      iex> abs(area - 2 * :math.pi()) < 1.0e-6
      true
  """
  @spec profile([tuple()], keyword()) :: t()
  def profile(edges, opts \\ []), do: %__MODULE__{kind: :profile, data: edges, options: opts}

  @doc """
  Returns a directed line description for `profile/2`.

  `from` and `to` are local `{u, v}` points. Their separation must
  exceed 1.0e-7 mm when evaluated. This returns `{:line, from, to}`, not
  a sketch or a native edge.
  """
  @spec line({number(), number()}, {number(), number()}) :: tuple()
  def line(from, to), do: {:line, from, to}

  @doc """
  Returns a directed circular-arc description for `profile/2`.

  `center` is a local `{u, v}` point and radius is in millimeters.
  `start` is measured from local +X in degrees. Positive `sweep` turns
  counterclockwise from local +X toward +Y; negative sweep reverses the turn.

  At evaluation, radius must exceed 1.0e-7 mm, and the absolute sweep must
  be greater than 1.0e-9 and at most 360 degrees. This returns an arc
  description tuple, not a sketch or native edge.
  """
  @spec arc({number(), number()}, number(), number(), number()) :: tuple()
  def arc(center, radius, start, sweep), do: {:arc, center, radius, start, sweep}

  @doc """
  Returns a nonperiodic interpolated B-spline description for `profile/2`.

  Supply at least two distinct local `{u, v}` points in traversal order.
  The curve passes through these points, not through a control polygon.
  Optional `tangents` is a pair of nonzero local direction vectors at the
  first and last point. Directions are mapped through the sketch plane
  without translation; OCCT chooses their derivative magnitudes.

  The curve need not remain inside the points' bounds. Invalid points,
  tangents, and degenerate interpolation fail during sketch evaluation.
  Close the outline with other edges before extruding or sweeping it.
  """
  @spec spline([{number(), number()}], {{number(), number()}, {number(), number()}} | nil) ::
          tuple()
  def spline(points, tangents \\ nil), do: {:spline, points, tangents}

  @doc """
  Places a sketch on a new plane, preserving its local coordinates.

  Overrides both its original `:on` option and any earlier call to
  `on/2`. The original sketch is unchanged. Cutters without an explicit
  plane inherit this new frame. Explicitly placed cutters retain their
  world placement and must still be coplanar.

      iex> outline = Smith.Sketch.rectangle(4, 6)
      iex> model =
      ...>   outline |> Smith.Sketch.on(Smith.Plane.yz(x: 10)) |> Smith.extrude(2)
      iex> {:ok, part} = Smith.evaluate(model)
      iex> {:ok, {x, y, z}} = OCEx.center_of_mass(part.shape)
      iex> abs(x - 11) < 1.0e-6 and abs(y) < 1.0e-6 and abs(z) < 1.0e-6
      true
  """
  @spec on(t(), Plane.t()) :: t()
  def on(%__MODULE__{} = sketch, plane), do: %{sketch | plane: plane}

  @doc """
  Sets a common corner radius on the original rectangle or convex polygon.

  Accepts only `radius:`, a positive distance in millimeters. Each corner
  is replaced by a tangent circular arc; adjacent arcs must leave a positive
  straight segment. Concave, collinear, degenerate, or overlarge fillets
  fail with `:invalid_fillet`. Circles and authored arc profiles return
  `:unsupported_sketch_fillet`.

  Calling this again replaces the earlier radius. Rounding is applied
  **before all sketch cuts**, regardless of pipeline order; it does not
  round corners introduced by a cutter. For edges on an evaluated solid
  recipe use `Smith.fillet/2`.
  """
  @spec fillet(t(), keyword()) :: t()
  def fillet(%__MODULE__{} = sketch, opts), do: %{sketch | rounding: opts}

  @doc """
  Subtracts a sketch or ordered list of sketches from this region.

  A cutter without an explicit plane inherits the parent's frame, including
  in nested cuts. Its `:at` is relative to that frame's origin, not the
  parent's anchor or center. Explicit cutter planes must be coplanar; there
  is no projection from another plane.

  Cuts may overlap, contain holes, reach the outside edge, or miss the
  parent. Repeated subtraction does not remove material twice. An empty
  list returns the original sketch. After every cut the result must be one
  face: removing it entirely fails with `:empty_sketch`, splitting it
  fails with `:disconnected_sketch`, and mismatched planes fail with
  `:non_coplanar_sketches`.

      iex> ring = Smith.Sketch.circle(5) |> Smith.Sketch.cut(Smith.Sketch.circle(3))
      iex> {:ok, part} = ring |> Smith.extrude(2) |> Smith.evaluate()
      iex> {:ok, volume} = OCEx.volume(part.shape)
      iex> abs(volume - 32 * :math.pi()) < 1.0e-6
      true
  """
  @spec cut(t(), t() | [t()]) :: t()
  def cut(%__MODULE__{} = sketch, tools) when is_list(tools),
    do: %{sketch | cuts: sketch.cuts ++ tools}

  def cut(%__MODULE__{} = sketch, tool), do: cut(sketch, [tool])

  @doc false
  def evaluate(sketch), do: evaluate_in(sketch, nil)

  defp evaluate_in(sketch, inherited) do
    with {:ok, base, frame} <- prepare(sketch, inherited),
         :ok <- coplanar(frame, inherited),
         {:ok, shape} <- face(base, frame, sketch.rounding) do
      Enum.reduce_while(sketch.cuts, {:ok, shape}, fn tool, {:ok, body} ->
        with {:ok, cutter} <- evaluate_in(tool, frame),
             {:ok, cut} <- OCEx.cut(body, cutter),
             {:ok, clean} <- OCEx.clean(cut),
             {:ok, face} <- single_face(clean) do
          {:cont, {:ok, face}}
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  defp single_face(shape) do
    with {:ok, faces} <- OCEx.faces(shape) do
      case faces do
        [face] -> {:ok, face}
        [] -> {:error, :empty_sketch}
        _ -> {:error, :disconnected_sketch}
      end
    end
  end

  defp coplanar(_, nil), do: :ok

  defp coplanar(a, b) do
    # Compare vectors directly: dot products lose tiny but meaningful tilts near 1.
    direction = if Plane.dot(a.n, b.n) < 0, do: Plane.scale(b.n, -1), else: b.n
    difference = Plane.sub(a.n, direction)

    if Plane.dot(difference, difference) < 1.0e-24 and
         abs(Plane.dot(Plane.sub(a.origin, b.origin), b.n)) < 1.0e-7,
       do: :ok,
       else: {:error, :non_coplanar_sketches}
  end

  @doc false
  def extrude(%__MODULE__{cuts: [_ | _]} = sketch, height)
      when is_number(height) and height != 0 do
    with {:ok, _, frame} <- prepare(sketch),
         {:ok, face} <- evaluate(sketch),
         do: OCEx.extrude(face, Plane.scale(frame.n, height))
  end

  def extrude(sketch, height) when is_number(height) and height != 0 do
    with {:ok, base, frame} <- prepare(sketch) do
      # Exact primitive lowering preserves analytic surfaces and existing exports.
      case {base, sketch.rounding} do
        {%{kind: :rectangle, width: w, height: h, points: [low | _]}, :none} ->
          with {:ok, shape} <- OCEx.box(w, h, abs(height)),
               do:
                 Plane.place(shape, %{
                   frame
                   | origin:
                       Plane.add(Plane.point(frame, low), Plane.scale(frame.n, min(0, height)))
                 })

        {%{kind: :circle, radius: radius, center: center}, :none} ->
          with {:ok, shape} <- OCEx.cylinder(radius, abs(height)),
               do:
                 Plane.place(shape, %{
                   frame
                   | origin:
                       Plane.add(Plane.point(frame, center), Plane.scale(frame.n, min(0, height)))
                 })

        _ ->
          with {:ok, face} <- face(base, frame, sketch.rounding),
               do: OCEx.extrude(face, Plane.scale(frame.n, height))
      end
    end
  end

  def extrude(_, _), do: {:error, :invalid_extrusion}

  @doc false
  def extrude(sketch, height, opts) when is_number(height) and height != 0 do
    if Plane.keywords?(opts, [:both, :taper]) and
         is_boolean(Keyword.get(opts, :both, false)) and
         is_number(Keyword.get(opts, :taper, 0)) do
      if not Keyword.get(opts, :both, false) and Keyword.get(opts, :taper, 0) == 0 do
        extrude(sketch, height)
      else
        with {:ok, _, frame} <- prepare(sketch),
             {:ok, face} <- evaluate(sketch),
             do: OCEx.extrude(face, Plane.scale(frame.n, height), opts)
      end
    else
      {:error, :invalid_options}
    end
  end

  def extrude(_, _, _), do: {:error, :invalid_extrusion}

  @doc false
  def extrude_until(sketch, target, opts) do
    with {:ok, _, frame} <- prepare(sketch),
         {:ok, face} <- evaluate(sketch),
         do:
           OCEx.extrude_until(
             face,
             Keyword.get(opts, :direction, frame.n),
             target.origin,
             target.n
           )
  end

  defp prepare(sketch, inherited \\ nil)

  defp prepare(%__MODULE__{} = sketch, inherited) do
    opts = sketch.options
    allowed = if sketch.kind == :profile, do: [:on, :at], else: [:on, :at, :align]

    with true <- Plane.keywords?(opts, allowed),
         true <- point?(Keyword.get(opts, :at, {0, 0})),
         {:ok, frame} <- sketch_frame(sketch, inherited),
         {:ok, base} <- base(sketch.kind, sketch.data, opts),
         :ok <- rounding(base, sketch.rounding) do
      {:ok, base, frame}
    else
      false -> {:error, :invalid_sketch_options}
      error -> error
    end
  end

  defp prepare(_, _), do: {:error, :invalid_sketch}

  defp sketch_frame(sketch, inherited) do
    cond do
      sketch.plane != :default -> Plane.frame(sketch.plane)
      Keyword.has_key?(sketch.options, :on) -> Plane.frame(sketch.options[:on])
      inherited != nil -> {:ok, inherited}
      true -> Plane.frame(Plane.xy())
    end
  end

  defp base(:rectangle, {w, h}, opts) when is_number(w) and w > 0 and is_number(h) and h > 0 do
    with {:ok, points} <- align([{0, 0}, {w, 0}, {w, h}, {0, h}], opts, {:center, :center}),
         do: {:ok, %{kind: :rectangle, width: w, height: h, points: points}}
  end

  defp base(:circle, radius, opts) when is_number(radius) and radius > 0 do
    with {:ok, [{lx, ly}, _]} <-
           align([{-radius, -radius}, {radius, radius}], opts, {:center, :center}),
         do: {:ok, %{kind: :circle, radius: radius, center: {lx + radius, ly + radius}}}
  end

  defp base(:slot, {length, width}, opts)
       when is_number(length) and is_number(width) and length >= width and width > 1.0e-7 do
    if length == width do
      base(:circle, width / 2, opts)
    else
      with {:ok, [{x, y}, _]} <-
             align([{-length / 2, -width / 2}, {length / 2, width / 2}], opts, {:center, :center}) do
        r = width / 2
        left = {x + r, y + r}
        right = {x + length - r, y + r}

        {:ok,
         %{
           kind: :profile,
           offset: {0, 0},
           edges: [
             line({x + r, y}, {x + length - r, y}),
             arc(right, r, -90, 180),
             line({x + length - r, y + width}, {x + r, y + width}),
             arc(left, r, 90, 180)
           ]
         }}
      end
    end
  end

  defp base(:polygon, points, opts) when is_list(points) and length(points) >= 3 do
    if Enum.all?(points, &point?/1) and abs(area(points)) > 1.0e-9 do
      with {:ok, points} <- align(points, opts, :none),
           do: {:ok, %{kind: :polygon, points: points}}
    else
      {:error, :invalid_polygon}
    end
  end

  defp base(:profile, edges, opts) when is_list(edges) and edges != [],
    do: {:ok, %{kind: :profile, edges: edges, offset: Keyword.get(opts, :at, {0, 0})}}

  defp base(_, _, _), do: {:error, :invalid_sketch}

  defp align(points, opts, default) do
    at = Keyword.get(opts, :at, {0, 0})
    alignment = Keyword.get(opts, :align, default)

    case alignment do
      :none ->
        {:ok, Enum.map(points, &add(&1, at))}

      {x, y} when x in [:min, :center, :max] and y in [:min, :center, :max] ->
        xs = Enum.map(points, &elem(&1, 0))
        ys = Enum.map(points, &elem(&1, 1))
        offset = sub(at, {anchor(xs, x), anchor(ys, y)})
        {:ok, Enum.map(points, &add(&1, offset))}

      _ ->
        {:error, :invalid_alignment}
    end
  end

  defp anchor(values, :min), do: Enum.min(values)
  defp anchor(values, :max), do: Enum.max(values)
  defp anchor(values, :center), do: (Enum.min(values) + Enum.max(values)) / 2

  defp rounding(_, :none), do: :ok

  defp rounding(%{kind: kind}, opts) when kind in [:rectangle, :polygon] do
    if Plane.keywords?(opts, [:radius]) and is_number(opts[:radius]) and opts[:radius] > 0,
      do: :ok,
      else: {:error, :invalid_fillet}
  end

  defp rounding(_, _), do: {:error, :unsupported_sketch_fillet}

  defp face(%{kind: :circle, radius: radius, center: center}, frame, :none) do
    with {:ok, edge} <- OCEx.circle(radius),
         {:ok, edge} <- Plane.place(edge, %{frame | origin: Plane.point(frame, center)}),
         {:ok, wire} <- OCEx.wire([edge]),
         do: OCEx.face(wire)
  end

  defp face(%{kind: :profile, edges: edges, offset: offset}, frame, :none),
    do: edges_face(edges, %{frame | origin: Plane.point(frame, offset)})

  defp face(%{points: points}, frame, :none), do: edges_face(lines(points), frame)

  defp face(%{points: points}, frame, opts) do
    with {:ok, edges} <- rounded(points, opts[:radius]), do: edges_face(edges, frame)
  end

  defp edges_face(edges, frame) do
    Enum.reduce_while(edges, {:ok, []}, fn description, {:ok, shapes} ->
      case edge(description, frame) do
        {:ok, shape} -> {:cont, {:ok, shapes ++ [shape]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, edges} ->
        with {:ok, wire} <- OCEx.wire(edges), do: OCEx.face(wire)

      error ->
        error
    end
  end

  defp edge({:line, from, to}, frame) do
    if point?(from) and point?(to),
      do: OCEx.edge(Plane.point(frame, from), Plane.point(frame, to)),
      else: {:error, :invalid_profile}
  end

  defp edge({:arc, center, radius, start, sweep}, frame) do
    if point?(center),
      do: OCEx.arc(Plane.point(frame, center), frame.n, frame.u, radius, start, sweep),
      else: {:error, :invalid_profile}
  end

  defp edge({:spline, points, tangents}, frame) do
    with true <- is_list(points) and Enum.all?(points, &point?/1),
         {:ok, tangents} <- spline_tangents(tangents, frame) do
      OCEx.spline(Enum.map(points, &Plane.point(frame, &1)), tangents)
    else
      false -> {:error, :invalid_profile}
      error -> error
    end
  end

  defp edge(_, _), do: {:error, :invalid_profile}

  defp spline_tangents(nil, _), do: {:ok, nil}

  defp spline_tangents({a, b}, frame) do
    if point?(a) and point?(b) do
      local = fn {u, v} -> Plane.add(Plane.scale(frame.u, u), Plane.scale(frame.v, v)) end
      {:ok, {local.(a), local.(b)}}
    else
      {:error, :invalid_profile}
    end
  end

  defp spline_tangents(_, _), do: {:error, :invalid_profile}

  defp rounded(points, radius) do
    points = if area(points) < 0, do: Enum.reverse(points), else: points

    corners =
      Enum.with_index(points)
      |> Enum.map(fn {p, i} ->
        incoming = sub(p, Enum.at(points, i - 1))
        outgoing = sub(Enum.at(points, rem(i + 1, length(points))), p)
        turn = :math.atan2(cross(incoming, outgoing), dot(incoming, outgoing))

        if norm(incoming) > 1.0e-9 and norm(outgoing) > 1.0e-9 and turn > 1.0e-9 and
             turn < :math.pi() - 1.0e-9 do
          u = scale(incoming, 1 / norm(incoming))
          v = scale(outgoing, 1 / norm(outgoing))
          distance = radius * :math.tan(turn / 2)
          start = sub(p, scale(u, distance))
          finish = add(p, scale(v, distance))
          center = add(start, scale({-elem(u, 1), elem(u, 0)}, radius))

          %{
            start: start,
            finish: finish,
            center: center,
            distance: distance,
            length: norm(outgoing),
            turn: turn
          }
        else
          nil
        end
      end)

    if Enum.all?(corners, &is_map/1) and
         Enum.with_index(corners)
         |> Enum.all?(fn {c, i} ->
           next = Enum.at(corners, rem(i + 1, length(corners)))
           c.distance + next.distance < c.length - 1.0e-9
         end) do
      {:ok,
       Enum.with_index(corners)
       |> Enum.flat_map(fn {c, i} ->
         next = Enum.at(corners, rem(i + 1, length(corners)))
         {x, y} = sub(c.start, c.center)

         [
           arc(c.center, radius, :math.atan2(y, x) * 180 / :math.pi(), c.turn * 180 / :math.pi()),
           line(c.finish, next.start)
         ]
       end)}
    else
      {:error, :invalid_fillet}
    end
  end

  defp lines(points),
    do:
      (points ++ [hd(points)])
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> line(a, b) end)

  defp area(points),
    do: Enum.reduce(lines(points), 0, fn {:line, a, b}, sum -> sum + cross(a, b) end) / 2

  defp point?({x, y}), do: is_number(x) and is_number(y)
  defp point?(_), do: false
  defp add({a, b}, {x, y}), do: {a + x, b + y}
  defp sub({a, b}, {x, y}), do: {a - x, b - y}
  defp scale({x, y}, n), do: {x * n, y * n}
  defp dot({a, b}, {x, y}), do: a * x + b * y
  defp cross({a, b}, {x, y}), do: a * y - b * x
  defp norm(v), do: :math.sqrt(dot(v, v))
end
