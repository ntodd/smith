defmodule Smith.SVG.Geometry do
  @moduledoc false
  alias Smith.SVG.{Document, PathData}
  def unwrap({:ok, value}), do: value
  def unwrap({:error, reason}), do: throw({:svg, reason})

  def build(elements, opts, scale) do
    shapes =
      Enum.flat_map(elements, fn element ->
        try do
          convert(element, opts, scale)
        catch
          {:svg, reason} -> throw({:svg, %{element: element.id || element.index, reason: reason}})
        end
      end)

    union(shapes)
  end

  def union([]), do: OCEx.compound([]) |> unwrap()

  def union([first | rest]),
    do:
      Enum.reduce(rest, first, fn shape, acc -> OCEx.fuse(acc, shape) |> unwrap() end)
      |> OCEx.clean()
      |> unwrap()

  def matrix(element, scale), do: Document.multiply({scale, 0, 0, -scale, 0, 0}, element.matrix)

  def wire(path, close \\ false) do
    {edges, last} =
      Enum.reduce(path.segments, {[], path.start}, fn segment, {edges, last} ->
        {edge, point} =
          case segment do
            {:line, p} ->
              {if(distance(last, p) > 1.0e-7,
                 do: OCEx.edge(p3(last), p3(p)) |> unwrap(),
                 else: nil
               ), p}

            {:bezier, points} ->
              curve =
                if Enum.any?(points, &(distance(hd(points), &1) > 1.0e-7)),
                  do: OCEx.bezier(Enum.map(points, &p3/1)) |> unwrap(),
                  else: nil

              {curve, List.last(points)}

            {:arc, {cx, cy}, rx, ry, angle, start, sweep, p} ->
              curve = OCEx.arc({0, 0, 0}, {0, 0, 1}, {1, 0, 0}, 1, start, sweep) |> unwrap()
              phi = angle * :math.pi() / 180
              c = :math.cos(phi)
              s = :math.sin(phi)

              {OCEx.affine_transform(curve, {rx * c, rx * s, -ry * s, ry * c, cx, cy})
               |> unwrap(), p}
          end

        {if(edge, do: edges ++ [edge], else: edges), point}
      end)

    edges =
      if (close or path.closed) and distance(last, path.start) > 1.0e-7,
        do: edges ++ [OCEx.edge(p3(last), p3(path.start)) |> unwrap()],
        else: edges

    if edges == [], do: nil, else: OCEx.wire(edges) |> unwrap()
  end

  defp convert(element, opts, scale) do
    mode = Keyword.get(opts, :mode, :painted)
    style = element.style
    tolerance = Keyword.get(opts, :tolerance, 0.01)
    matrix = matrix(element, scale)

    fills =
      if mode in [:fill, :painted] and style["fill"] != "none" and style["fill-opacity"] != "0" do
        wires =
          element.paths
          |> Enum.map(&wire(&1, true))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&(OCEx.affine_transform(&1, matrix) |> unwrap()))

        if wires == [],
          do: [],
          else: [
            OCEx.planar_fill(
              wires,
              if(style["fill-rule"] == "evenodd", do: :evenodd, else: :nonzero)
            )
            |> unwrap()
          ]
      else
        []
      end

    strokes =
      if mode in [:strokes, :painted] and style["stroke"] != "none" and
           style["stroke-opacity"] != "0" do
        source_width = Document.length_value(style["stroke-width"])
        if source_width < 0, do: throw({:svg, :invalid_stroke_width})
        override = opts[:stroke_width]

        if source_width == 0 and override == nil do
          []
        else
          element.paths
          |> Enum.flat_map(fn path ->
            case wire(path) do
              nil ->
                if path.closed or style["stroke-linecap"] == "butt" do
                  []
                else
                  center = if override, do: Document.point(matrix, path.start), else: path.start
                  shape = point_stroke(center, override || source_width, style["stroke-linecap"])

                  [
                    if(override,
                      do: shape,
                      else: OCEx.affine_transform(shape, matrix) |> unwrap()
                    )
                  ]
                end

              wire ->
                args = [
                  cap: enum(style["stroke-linecap"]),
                  join: enum(style["stroke-linejoin"]),
                  miter_limit: PathData.number(style["stroke-miterlimit"])
                ]

                shape =
                  if override do
                    transformed = OCEx.affine_transform(wire, matrix) |> unwrap()

                    OCEx.stroke(transformed, override, args ++ [tolerance: tolerance / 2])
                    |> unwrap()
                  else
                    local_tolerance = tolerance / (2 * max(Document.stretch(matrix), 1.0e-12))

                    OCEx.stroke(wire, source_width, args ++ [tolerance: local_tolerance])
                    |> unwrap()
                    |> OCEx.affine_transform(matrix)
                    |> unwrap()
                  end

                [shape]
            end
          end)
        end
      else
        []
      end

    fills ++ strokes
  end

  defp point_stroke({x, y}, width, "round") do
    edge = OCEx.circle(width / 2) |> unwrap()
    wire = OCEx.wire([edge]) |> unwrap()
    OCEx.face(wire) |> unwrap() |> OCEx.translate({x, y, 0}) |> unwrap()
  end

  defp point_stroke({x, y}, width, "square") do
    r = width / 2

    wire(%{
      start: {x - r, y - r},
      segments: [{:line, {x + r, y - r}}, {:line, {x + r, y + r}}, {:line, {x - r, y + r}}],
      closed: true
    })
    |> OCEx.face()
    |> unwrap()
  end

  defp enum("butt"), do: :butt
  defp enum("square"), do: :square
  defp enum("round"), do: :round
  defp enum("bevel"), do: :bevel
  defp enum("miter"), do: :miter
  def p3({x, y}), do: {x, y, 0}
  def distance({x, y}, {a, b}), do: :math.sqrt((x - a) * (x - a) + (y - b) * (y - b))
end
