defmodule Smith.SVG.PathData do
  @moduledoc false
  @number ~r/\A[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/
  @commands ~w(M L H V C S Q T A Z m l h v c s q t a z)
  def number(text) do
    # SVG permits .5, -.5 and 1.e2; Float.parse/1 requires digits on
    # both sides of a decimal point. Normalize only those grammar forms.
    text = Regex.replace(~r/\A([+-]?)\./, text, "\\g{1}0.")
    text = Regex.replace(~r/\.(?=[eE]|$)/, text, ".0")

    case Float.parse(text) do
      {n, ""} when abs(n) <= 1.0e12 -> n
      _ -> throw({:svg, :invalid_number})
    end
  end

  def numbers(text),
    do:
      tokenize(text, [])
      |> Enum.map(fn
        {:number, raw} -> number(raw)
        _ -> throw({:svg, :invalid_number})
      end)

  def parse(data) do
    tokens = tokenize(data, [])
    if length(tokens) > 100_000, do: throw({:svg, :svg_complexity_limit})
    state = %{point: {0.0, 0.0}, start: nil, segments: [], paths: [], last: nil, control: nil}
    run(tokens, nil, state) |> finish() |> Map.fetch!(:paths) |> Enum.reverse()
  end

  defp tokenize("", acc), do: Enum.reverse(acc)
  defp tokenize(<<c, rest::binary>>, acc) when c in [32, 9, 10, 13, 44], do: tokenize(rest, acc)

  defp tokenize(<<c, rest::binary>> = text, acc) do
    if <<c>> in @commands do
      tokenize(rest, [<<c>> | acc])
    else
      case Regex.run(@number, text) do
        [n] ->
          tokenize(binary_part(text, byte_size(n), byte_size(text) - byte_size(n)), [
            {:number, n} | acc
          ])

        _ ->
          throw({:svg, :invalid_path_data})
      end
    end
  end

  defp finish(%{start: nil} = s), do: s

  defp finish(s),
    do: %{
      s
      | paths: [%{start: s.start, segments: Enum.reverse(s.segments), closed: false} | s.paths],
        start: nil,
        segments: []
    }

  defp run([], _, s), do: s

  defp run([c | tail], _, s) when is_binary(c) do
    if String.upcase(c) == "Z" do
      if s.start == nil, do: throw({:svg, :invalid_path_data})
      path = %{start: s.start, segments: Enum.reverse(s.segments), closed: true}

      run(tail, nil, %{
        s
        | point: s.start,
          start: nil,
          segments: [],
          paths: [path | s.paths],
          last: "Z",
          control: nil
      })
    else
      run_command(tail, c, s)
    end
  end

  defp run(tokens, c, s) when is_binary(c), do: run_command(tokens, c, s)
  defp run(_, _, _), do: throw({:svg, :invalid_path_data})

  defp run_command(tokens, c, s) do
    upper = String.upcase(c)

    count =
      %{"M" => 2, "L" => 2, "H" => 1, "V" => 1, "C" => 6, "S" => 4, "Q" => 4, "T" => 2, "A" => 7}[
        upper
      ]

    {args, tail} = arguments(tokens, upper, count, 0, [])

    relative = c != upper
    point = fn x, y -> if relative, do: add(s.point, {x, y}), else: {x, y} end
    s = if s.start == nil and s.last == "Z" and upper != "M", do: %{s | start: s.point}, else: s
    if upper != "M" and s.start == nil, do: throw({:svg, :invalid_path_data})

    {s, next} =
      case {upper, args} do
        {"M", [x, y]} ->
          p = point.(x, y)
          s = finish(s)
          {%{s | point: p, start: p, last: "M", control: nil}, if(relative, do: "l", else: "L")}

        {"L", [x, y]} ->
          {segment(s, {:line, point.(x, y)}, point.(x, y), upper), c}

        {"H", [x]} ->
          {px, py} = s.point
          p = {if(relative, do: px + x, else: x), py}
          {segment(s, {:line, p}, p, upper), c}

        {"V", [y]} ->
          {px, py} = s.point
          p = {px, if(relative, do: py + y, else: y)}
          {segment(s, {:line, p}, p, upper), c}

        {"C", [x1, y1, x2, y2, x, y]} ->
          b = point.(x2, y2)
          p = point.(x, y)
          {segment(s, {:bezier, [s.point, point.(x1, y1), b, p]}, p, upper, b), c}

        {"S", [x2, y2, x, y]} ->
          a = reflect(s, ["C", "S"])
          b = point.(x2, y2)
          p = point.(x, y)
          {segment(s, {:bezier, [s.point, a, b, p]}, p, upper, b), c}

        {"Q", [x1, y1, x, y]} ->
          a = point.(x1, y1)
          p = point.(x, y)
          {segment(s, {:bezier, [s.point, a, p]}, p, upper, a), c}

        {"T", [x, y]} ->
          a = reflect(s, ["Q", "T"])
          p = point.(x, y)
          {segment(s, {:bezier, [s.point, a, p]}, p, upper, a), c}

        {"A", [rx, ry, angle, large, sweep, x, y]} ->
          unless large in [0.0, 1.0] and sweep in [0.0, 1.0], do: throw({:svg, :invalid_arc_flag})
          p = point.(x, y)
          {segment(s, arc(s.point, p, abs(rx), abs(ry), angle, large, sweep), p, upper), c}
      end

    run(tail, next, s)
  end

  defp arguments(tokens, _, count, count, acc), do: {Enum.reverse(acc), tokens}

  defp arguments([{:number, <<flag, rest::binary>>} | tail], "A", count, i, acc)
       when i in [3, 4] and flag in [?0, ?1] do
    tail = if rest == "", do: tail, else: [{:number, rest} | tail]
    arguments(tail, "A", count, i + 1, [(flag - ?0) * 1.0 | acc])
  end

  defp arguments([{:number, raw} | tail], command, count, i, acc)
       when command != "A" or i not in [3, 4],
       do: arguments(tail, command, count, i + 1, [number(raw) | acc])

  defp arguments(_, _, _, _, _), do: throw({:svg, :invalid_path_data})

  defp segment(s, segment, p, last, control \\ nil),
    do: %{s | segments: [segment | s.segments], point: p, last: last, control: control}

  defp reflect(s, kinds),
    do: if(s.last in kinds, do: subtract(scale(s.point, 2), s.control), else: s.point)

  def add({a, b}, {x, y}), do: {a + x, b + y}
  def subtract({a, b}, {x, y}), do: {a - x, b - y}
  def scale({x, y}, k), do: {x * k, y * k}
  defp arc(from, to, rx, ry, _, _, _) when rx == 0 or ry == 0 or from == to, do: {:line, to}
  # SVG endpoint-to-center conversion, retaining the ellipse rather than a polyline.
  defp arc({x1, y1}, {x2, y2}, rx, ry, angle, large, sweep) do
    phi = angle * :math.pi() / 180
    c = :math.cos(phi)
    s = :math.sin(phi)
    x = c * (x1 - x2) / 2 + s * (y1 - y2) / 2
    y = -s * (x1 - x2) / 2 + c * (y1 - y2) / 2
    correction = max(1.0, :math.sqrt(x * x / (rx * rx) + y * y / (ry * ry)))
    rx = rx * correction
    ry = ry * correction
    sign = if large == sweep, do: -1, else: 1

    factor =
      sign *
        :math.sqrt(
          max(
            0.0,
            (rx * rx * ry * ry - rx * rx * y * y - ry * ry * x * x) /
              (rx * rx * y * y + ry * ry * x * x)
          )
        )

    cx = factor * rx * y / ry
    cy = -factor * ry * x / rx
    center = {c * cx - s * cy + (x1 + x2) / 2, s * cx + c * cy + (y1 + y2) / 2}
    start = :math.atan2((y - cy) / ry, (x - cx) / rx)
    ending = :math.atan2((-y - cy) / ry, (-x - cx) / rx)
    delta = ending - start

    delta =
      cond do
        sweep == 1 and delta < 0 -> delta + 2 * :math.pi()
        sweep == 0 and delta > 0 -> delta - 2 * :math.pi()
        true -> delta
      end

    {:arc, center, rx, ry, angle, start * 180 / :math.pi(), delta * 180 / :math.pi(), {x2, y2}}
  end
end
