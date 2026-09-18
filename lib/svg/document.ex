defmodule Smith.SVG.Document do
  @moduledoc false
  alias Smith.SVG.PathData, as: P
  @identity {1, 0, 0, 1, 0, 0}
  @defaults %{
    "fill" => "black",
    "stroke" => "none",
    "fill-rule" => "nonzero",
    "stroke-width" => "1",
    "stroke-linecap" => "butt",
    "stroke-linejoin" => "miter",
    "stroke-miterlimit" => "4",
    "visibility" => "visible",
    "color" => "black"
  }
  @styles ~w(fill stroke fill-rule stroke-width stroke-linecap stroke-linejoin stroke-miterlimit stroke-dasharray stroke-dashoffset opacity fill-opacity stroke-opacity display visibility color clip-path mask filter vector-effect marker marker-start marker-mid marker-end)
  def parse(root) do
    try do
      ids = index(root, %{})
      {matrix, viewport} = viewport(root.attrs)

      context = %{
        matrix: matrix,
        style: @defaults,
        groups: [],
        viewport: viewport,
        stack: [],
        ids: ids,
        budget: :counters.new(1, [])
      }

      elements =
        walk(root, context, true)
        |> Enum.with_index()
        |> Enum.map(fn {e, i} -> Map.put(e, :index, i) end)

      if length(elements) > 4096, do: fail(nil, :svg_complexity_limit)
      {:ok, %{elements: elements, viewport: viewport}}
    rescue
      ArithmeticError -> {:error, %{element: "svg", reason: :invalid_numeric_range}}
    catch
      {:svg, reason} -> {:error, reason}
    end
  end

  defp fail(node, reason),
    do:
      throw(
        {:svg,
         %{element: if(node, do: node.attrs["id"] || node.name, else: "svg"), reason: reason}}
      )

  defp index(node, acc) do
    if node.name == "style", do: fail(node, {:unsupported_element, "style"})

    acc =
      case node.attrs["id"] do
        nil ->
          acc

        id ->
          if Map.has_key?(acc, id), do: fail(node, :duplicate_id), else: Map.put(acc, id, node)
      end

    Enum.reduce(node.children, acc, &index/2)
  end

  def multiply({a, b, c, d, e, f}, {g, h, i, j, k, l}),
    do:
      {a * g + c * h, b * g + d * h, a * i + c * j, b * i + d * j, a * k + c * l + e,
       b * k + d * l + f}

  def point({a, b, c, d, e, f}, {x, y}), do: {a * x + c * y + e, b * x + d * y + f}
  def stretch({a, b, c, d, _, _}), do: :math.sqrt(a * a + b * b + c * c + d * d)
  def transform(nil), do: @identity

  def transform(text) do
    matches = Regex.scan(~r/([A-Za-z]+)\s*\(([^)]*)\)/, text)

    residue =
      Regex.replace(~r/[A-Za-z]+\s*\([^)]*\)/, text, "")
      |> String.replace(",", "")
      |> String.trim()

    if residue != "", do: throw({:svg, :invalid_transform})

    Enum.reduce(matches, @identity, fn [_, kind, args], matrix ->
      values = P.numbers(args)

      next =
        case {kind, values} do
          {"matrix", [a, b, c, d, e, f]} ->
            {a, b, c, d, e, f}

          {"translate", [x]} ->
            {1, 0, 0, 1, x, 0}

          {"translate", [x, y]} ->
            {1, 0, 0, 1, x, y}

          {"scale", [s]} ->
            {s, 0, 0, s, 0, 0}

          {"scale", [x, y]} ->
            {x, 0, 0, y, 0, 0}

          {"rotate", [angle]} ->
            rotation(angle)

          {"rotate", [angle, x, y]} ->
            multiply(multiply({1, 0, 0, 1, x, y}, rotation(angle)), {1, 0, 0, 1, -x, -y})

          {"skewX", [angle]} ->
            {1, 0, :math.tan(angle * :math.pi() / 180), 1, 0, 0}

          {"skewY", [angle]} ->
            {1, :math.tan(angle * :math.pi() / 180), 0, 1, 0, 0}

          _ ->
            throw({:svg, :invalid_transform})
        end

      multiply(matrix, next)
    end)
  end

  defp rotation(angle) do
    c = :math.cos(angle * :math.pi() / 180)
    s = :math.sin(angle * :math.pi() / 180)
    {c, s, -s, c, 0, 0}
  end

  def length_value(value, reference \\ nil) do
    case Regex.run(
           ~r/\A\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(px|mm|cm|in|pt|pc|%)?\s*\z/,
           value
         ) do
      [_, n] ->
        P.number(n)

      [_, n, unit] ->
        factor =
          case unit do
            "px" ->
              1

            "mm" ->
              96 / 25.4

            "cm" ->
              960 / 25.4

            "in" ->
              96

            "pt" ->
              96 / 72

            "pc" ->
              16

            "%" ->
              if is_number(reference),
                do: reference / 100,
                else: throw({:svg, :unresolved_percentage})
          end

        P.number(n) * factor

      _ ->
        throw({:svg, :invalid_length})
    end
  end

  defp viewport(attrs) do
    view =
      case attrs["viewBox"] do
        nil ->
          nil

        text ->
          case P.numbers(text) do
            [x, y, w, h] when w > 0 and h > 0 -> {x, y, w, h}
            _ -> throw({:svg, :invalid_viewbox})
          end
      end

    {_, _, vw, vh} = view || {0, 0, 300, 150}
    w = length_value(attrs["width"] || to_string(vw))
    h = length_value(attrs["height"] || to_string(vh))
    if w <= 0 or h <= 0, do: throw({:svg, :invalid_viewport})
    base = {25.4 / 96, 0, 0, 25.4 / 96, 0, 0}

    inner =
      case view do
        nil ->
          @identity

        {x, y, vw, vh} ->
          ratio = String.split(attrs["preserveAspectRatio"] || "xMidYMid meet")

          case ratio do
            ["none"] ->
              {w / vw, 0, 0, h / vh, -x * w / vw, -y * h / vh}

            [align | rest] when rest in [[], ["meet"], ["slice"]] ->
              unless align in ~w(xMinYMin xMidYMin xMaxYMin xMinYMid xMidYMid xMaxYMid xMinYMax xMidYMax xMaxYMax),
                do: throw({:svg, :invalid_aspect_ratio})

              if rest == ["slice"], do: throw({:svg, :unsupported_viewport_clipping})
              s = min(w / vw, h / vh)

              factor = fn
                "Min" -> 0
                "Mid" -> 0.5
                "Max" -> 1
              end

              dx = (w - vw * s) * factor.(String.slice(align, 1, 3))
              dy = (h - vh * s) * factor.(String.slice(align, 5, 3))
              {s, 0, 0, s, dx - x * s, dy - y * s}

            _ ->
              throw({:svg, :invalid_aspect_ratio})
          end
      end

    {multiply(base, inner),
     %{width: w * 25.4 / 96, height: h * 25.4 / 96, user_width: vw, user_height: vh}}
  end

  defp walk(node, ctx, root \\ false) do
    try do
      :counters.add(ctx.budget, 1, 1)
      if :counters.get(ctx.budget, 1) > 10_000, do: fail(node, :svg_complexity_limit)

      if node.name in ["defs", "title", "desc", "metadata", "sodipodi:namedview"],
        do: throw(:skip)

      style = style(node, ctx.style)
      if style["display"] == "none" or style["opacity"] == "0", do: throw(:skip)
      matrix = multiply(ctx.matrix, transform(node.attrs["transform"]))
      {a, b, c, d, _, _} = matrix
      if abs(a * d - b * c) < 1.0e-15, do: throw(:skip)
      group = List.wrap(node.attrs["id"]) ++ List.wrap(node.attrs["inkscape:label"])
      ctx = %{ctx | matrix: matrix, style: style}

      case node.name do
        "svg" when root ->
          Enum.flat_map(node.children, &walk(&1, ctx))

        "g" ->
          Enum.flat_map(node.children, &walk(&1, %{ctx | groups: ctx.groups ++ group}))

        "use" ->
          href = node.attrs["href"] || node.attrs["xlink:href"] || ""
          unless String.starts_with?(href, "#"), do: fail(node, :external_reference)
          id = String.trim_leading(href, "#")
          if id in ctx.stack or length(ctx.stack) >= 32, do: fail(node, :cyclic_reference)
          target = ctx.ids[id] || fail(node, :missing_reference)
          dx = length_value(node.attrs["x"] || "0")
          dy = length_value(node.attrs["y"] || "0")

          walk(target, %{
            ctx
            | matrix: multiply(matrix, {1, 0, 0, 1, dx, dy}),
              groups: ctx.groups ++ group,
              stack: [id | ctx.stack]
          })

        kind when kind in ~w(path rect circle ellipse line polyline polygon) ->
          if style["visibility"] in ["hidden", "collapse"], do: throw(:skip)

          diagonal =
            :math.sqrt((ctx.viewport.user_width ** 2 + ctx.viewport.user_height ** 2) / 2)

          style = Map.update!(style, "stroke-width", &to_string(length_value(&1, diagonal)))

          style =
            Enum.reduce(~w(fill stroke), style, fn key, acc ->
              paint = if acc[key] == "currentColor", do: acc["color"], else: acc[key]
              Map.put(acc, key, if(paint == "transparent", do: "none", else: paint))
            end)

          validate_style(node, style)
          paths = paths(node, ctx.viewport)

          [
            %{
              id: node.attrs["id"],
              label: node.attrs["inkscape:label"],
              groups: ctx.groups,
              kind: kind,
              paths: paths,
              matrix: matrix,
              style: style
            }
          ]

        _ ->
          fail(node, {:unsupported_element, node.name})
      end
    catch
      :skip -> []
      {:svg, %{} = reason} -> throw({:svg, reason})
      {:svg, reason} -> fail(node, reason)
    end
  end

  defp style(node, parent) do
    # Opacity and display are group effects, not inherited properties. A partial
    # opacity is rejected instead of pretending it changes material thickness.
    base = Map.drop(parent, ["display", "opacity"])
    attrs = Map.take(node.attrs, @styles)

    inline =
      String.split(node.attrs["style"] || "", ";", trim: true)
      |> Enum.reduce(%{}, fn entry, acc ->
        case String.split(entry, ":", parts: 2) do
          [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
          _ -> fail(node, :invalid_style)
        end
      end)

    unknown = Map.keys(inline) -- (@styles ++ ["font-family", "font-size"])
    if unknown != [], do: fail(node, {:unsupported_style, hd(unknown)})

    result =
      Map.merge(attrs, inline)
      |> Enum.reduce(base, fn {k, v}, acc ->
        if v == "inherit", do: acc, else: Map.put(acc, k, v)
      end)

    result =
      Enum.reduce(~w(opacity fill-opacity stroke-opacity), result, fn key, acc ->
        case acc[key] do
          nil ->
            acc

          value ->
            n = P.number(value)

            cond do
              n <= 0 -> Map.put(acc, key, "0")
              n >= 1 -> Map.put(acc, key, "1")
              true -> fail(node, :unsupported_opacity)
            end
        end
      end)

    if result["display"] == "none" or result["opacity"] == "0", do: throw(:skip)

    if result["opacity"] not in [nil, "0", "1", "1.0"], do: fail(node, :unsupported_opacity)

    for key <- ~w(clip-path mask filter marker marker-start marker-mid marker-end vector-effect) do
      if result[key] not in [nil, "none"], do: fail(node, {:unsupported_style, key})
    end

    result
  end

  defp validate_style(node, style) do
    for key <- ~w(fill stroke) do
      if String.contains?(style[key], ["url(", "var(", "rgba(", "hsla(", "/"]),
        do: fail(node, {:unsupported_paint, key})

      if Regex.match?(~r/\A#(?:[0-9a-fA-F]{4}|[0-9a-fA-F]{8})\z/, style[key]),
        do: fail(node, {:unsupported_paint, key})
    end

    if style["stroke-dasharray"] not in [nil, "none"], do: fail(node, :unsupported_dashes)
    unless style["fill-rule"] in ["nonzero", "evenodd"], do: fail(node, :invalid_fill_rule)

    unless style["stroke-linecap"] in ["butt", "round", "square"],
      do: fail(node, :invalid_linecap)

    unless style["stroke-linejoin"] in ["miter", "round", "bevel"],
      do: fail(node, :invalid_linejoin)

    for key <- ~w(fill-opacity stroke-opacity) do
      if style[key] not in [nil, "0", "1", "1.0"], do: fail(node, :unsupported_opacity)
    end
  end

  defp paths(%{name: "path", attrs: a}, _), do: P.parse(a["d"] || "")

  defp paths(%{name: name, attrs: a}, viewport) do
    get = fn key, default ->
      length_value(
        a[key] || to_string(default),
        cond do
          key == "r" -> :math.sqrt((viewport.user_width ** 2 + viewport.user_height ** 2) / 2)
          key in ~w(y y1 y2 cy ry height) -> viewport.user_height
          true -> viewport.user_width
        end
      )
    end

    data =
      case name do
        "line" ->
          "M #{get.("x1", 0)} #{get.("y1", 0)} L #{get.("x2", 0)} #{get.("y2", 0)}"

        kind when kind in ["polyline", "polygon"] ->
          "M " <> (a["points"] || "") <> if(kind == "polygon", do: " Z", else: "")

        kind when kind in ["circle", "ellipse"] ->
          x = get.("cx", 0)
          y = get.("cy", 0)
          rx = if kind == "circle", do: get.("r", 0), else: get.("rx", 0)
          ry = if kind == "circle", do: rx, else: get.("ry", 0)
          if rx < 0 or ry < 0, do: throw({:svg, :invalid_radius})

          if rx == 0 or ry == 0,
            do: "",
            else:
              "M #{x + rx} #{y} A #{rx} #{ry} 0 1 1 #{x - rx} #{y} A #{rx} #{ry} 0 1 1 #{x + rx} #{y} Z"

        "rect" ->
          x = get.("x", 0)
          y = get.("y", 0)
          w = get.("width", 0)
          h = get.("height", 0)
          rx = if a["rx"], do: get.("rx", 0), else: get.("ry", 0)
          ry = if a["ry"], do: get.("ry", 0), else: rx
          if min(min(w, h), min(rx, ry)) < 0, do: throw({:svg, :invalid_rectangle})
          rx = min(rx, w / 2)
          ry = min(ry, h / 2)

          cond do
            w == 0 or h == 0 ->
              ""

            rx == 0 or ry == 0 ->
              "M #{x} #{y} H #{x + w} V #{y + h} H #{x} Z"

            true ->
              "M #{x + rx} #{y} H #{x + w - rx} A #{rx} #{ry} 0 0 1 #{x + w} #{y + ry} V #{y + h - ry} A #{rx} #{ry} 0 0 1 #{x + w - rx} #{y + h} H #{x + rx} A #{rx} #{ry} 0 0 1 #{x} #{y + h - ry} V #{y + ry} A #{rx} #{ry} 0 0 1 #{x + rx} #{y} Z"
          end
      end

    if data == "", do: [], else: P.parse(data)
  end
end
