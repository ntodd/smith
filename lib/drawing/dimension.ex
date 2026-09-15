defmodule Smith.Drawing.Dimension do
  @moduledoc false
  alias Smith.{Geometry, Measure, Plane}

  def build(drawing, %Measure{} = m, opts) do
    with true <- Geometry.options(opts, [:orientation, :offset, :precision]),
         orientation = Keyword.get(opts, :orientation, :aligned),
         offset = Keyword.get(opts, :offset, 5),
         precision = Keyword.get(opts, :precision, 2),
         true <-
           orientation in [:aligned, :horizontal, :vertical] and is_number(offset) and
             is_integer(precision) and precision in 0..6,
         true <- m.source_revision == drawing.source_revision,
         {:ok, frame} <- Plane.frame(drawing.plane),
         points =
           Enum.map(m.points, fn p ->
             delta = Geometry.vector(p, frame.origin)
             {Geometry.dot(delta, frame.u), Geometry.dot(delta, frame.v)}
           end),
         :ok <- in_plane(m, points, frame, orientation),
         {:ok, geometry} <- geometry(m, points, orientation, offset) do
      prefix =
        case m.kind do
          :diameter -> "⌀"
          :radius -> "R"
          _ -> ""
        end

      unit = if m.unit == :degrees, do: "°", else: " mm"
      label = prefix <> :erlang.float_to_binary(m.value * 1.0, decimals: precision) <> unit
      {:ok, Map.merge(geometry, %{measurement: m, label: label})}
    else
      false ->
        if(match?(%Measure{}, m) and m.source_revision != drawing.source_revision,
          do: {:error, :revision_mismatch},
          else: {:error, :invalid_options}
        )

      error ->
        error
    end
  end

  def build(_, _, _), do: {:error, :invalid_argument}

  defp in_plane(%{kind: :angle, value: value}, [o, a, b], _, _) do
    u = sub(a, o)
    v = sub(b, o)

    if norm(u) > 1.0e-9 and norm(v) > 1.0e-9 and
         abs(angle(u, v) * 180 / :math.pi() - value) < 1.0e-6,
       do: :ok,
       else: {:error, :dimension_out_of_plane}
  end

  defp in_plane(m, [a, b], frame, orientation) do
    {dx, dy} = sub(b, a)

    projected =
      case orientation do
        :horizontal -> abs(dx)
        :vertical -> abs(dy)
        :aligned -> norm({dx, dy})
      end

    circle_ok = m.normal == nil or abs(Geometry.dot(m.normal, frame.n)) > 1 - 1.0e-7

    if circle_ok and abs(projected - m.value) < 1.0e-6 and projected > 1.0e-9,
      do: :ok,
      else: {:error, :dimension_out_of_plane}
  end

  defp geometry(%{kind: :angle}, [o, a, b], _, offset) when abs(offset) > 1.0e-7 do
    {ux, uy} = sub(a, o)
    {vx, vy} = sub(b, o)
    start = :math.atan2(uy, ux)
    sweep = :math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    r = abs(offset)

    if abs(sweep) > 1.0e-7 and abs(sweep) < :math.pi() - 1.0e-7 do
      arc =
        for i <- 0..32,
            do:
              add(
                o,
                {r * :math.cos(start + sweep * i / 32), r * :math.sin(start + sweep * i / 32)}
              )

      first = hd(arc)
      last = List.last(arc)

      {:ok,
       %{
         lines: [[o, add(o, mul(sub(first, o), 1.15))], [o, add(o, mul(sub(last, o), 1.15))], arc],
         arrows: arrow(first, Enum.at(arc, 1)) ++ arrow(last, Enum.at(arc, -2)),
         center: [],
         text_at:
           add(
             o,
             {(r + 2) * :math.cos(start + sweep / 2), (r + 2) * :math.sin(start + sweep / 2)}
           )
       }}
    else
      {:error, :degenerate_dimension}
    end
  end

  defp geometry(%{kind: :angle}, _, _, _), do: {:error, :invalid_options}

  defp geometry(m, [a, b], orientation, offset) do
    {ax, ay} = a
    {bx, by} = b

    {p, q} =
      case orientation do
        :horizontal ->
          y = if(offset >= 0, do: max(ay, by), else: min(ay, by)) + offset
          {{ax, y}, {bx, y}}

        :vertical ->
          x = if(offset >= 0, do: max(ax, bx), else: min(ax, bx)) + offset
          {{x, ay}, {x, by}}

        :aligned ->
          {dx, dy} = sub(b, a)
          n = norm({dx, dy})
          shift = {-dy / n * offset, dx / n * offset}
          {add(a, shift), add(b, shift)}
      end

    midpoint = mul(add(p, q), 0.5)

    center =
      if m.kind in [:radius, :diameter] do
        o = if m.kind == :radius, do: a, else: mul(add(a, b), 0.5)
        r = if m.kind == :radius, do: m.value, else: m.value / 2
        [[add(o, {-r - 1, 0}), add(o, {r + 1, 0})], [add(o, {0, -r - 1}), add(o, {0, r + 1})]]
      else
        []
      end

    {:ok,
     %{
       lines: [[a, extend(a, p)], [b, extend(b, q)], [p, q]],
       arrows: arrow(p, q) ++ arrow(q, p),
       center: center,
       text_at: add(midpoint, {0, 2})
     }}
  end

  defp extend(a, b) do
    d = sub(b, a)
    n = norm(d)
    if n < 1.0e-9, do: b, else: add(b, mul(d, 1 / n))
  end

  defp arrow(a, b) do
    {dx, dy} = sub(b, a)
    n = norm({dx, dy})
    {ux, uy} = {dx / n, dy / n}

    [
      [
        add(a, {ux * 1.6 - uy * 0.55, uy * 1.6 + ux * 0.55}),
        a,
        add(a, {ux * 1.6 + uy * 0.55, uy * 1.6 - ux * 0.55})
      ]
    ]
  end

  defp angle({ax, ay} = a, {bx, by} = b),
    do: :math.acos(max(-1.0, min(1.0, (ax * bx + ay * by) / (norm(a) * norm(b)))))

  defp sub({a, b}, {c, d}), do: {a - c, b - d}
  defp add({a, b}, {c, d}), do: {a + c, b + d}
  defp mul({a, b}, n), do: {a * n, b * n}
  defp norm({a, b}), do: :math.sqrt(a * a + b * b)

  def extent(dimensions) do
    Enum.flat_map(dimensions, fn d ->
      {x, y} = d.text_at
      half = String.length(d.label) * 0.95
      List.flatten(d.lines ++ d.arrows ++ d.center) ++ [{x - half, y - 1.5}, {x + half, y + 3.5}]
    end)
  end

  def svg(dimensions) do
    Enum.map(dimensions, fn d ->
      {x, y} = d.text_at

      [
        ~s|<g class="dimension" fill="none" stroke="#26374a" stroke-width="0.2">|,
        paths(d.lines ++ d.arrows),
        ~s|<g class="center-mark" stroke-dasharray="3 0.8 0.4 0.8">|,
        paths(d.center),
        "</g></g>",
        ~s|<text class="dimension-label" transform="translate(#{x},#{y}) scale(1,-1)" text-anchor="middle" font-family="sans-serif" font-size="3" fill="#172b40" stroke="none">#{d.label}</text>|
      ]
    end)
  end

  defp paths(lines),
    do:
      Enum.map(lines, fn line ->
        ~s|<polyline points="#{Enum.map_join(line, " ", fn {x, y} -> "#{x},#{y}" end)}"/>|
      end)
end
