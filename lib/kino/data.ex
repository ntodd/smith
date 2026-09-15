defmodule Smith.Kino.Data do
  @moduledoc false
  alias Smith.{Geometry, Plane}

  def build(result, opts) do
    tolerance = Keyword.get(opts, :tolerance, 0.03)
    angular = Keyword.get(opts, :angular_tolerance, 0.5)

    with {:ok, mesh} <- OCEx.mesh(result.shape, tolerance, angular),
         {:ok, curves} <- OCEx.polylines(result.shape, tolerance, angular),
         {:ok, clip} <- clip(Keyword.get(opts, :clip)) do
      lines = Enum.map(curves, fn line -> Enum.map(line, &Tuple.to_list/1) end)

      {:ok,
       %{
         vertices: Enum.map(mesh.vertices, &Tuple.to_list/1),
         triangles: Enum.map(mesh.triangles, &Tuple.to_list/1),
         lines: if(mesh.triangles == [], do: lines, else: []),
         edge_lines: if(mesh.triangles == [], do: [], else: lines),
         revision: result.revision,
         label: Keyword.get(opts, :label, "Smith preview"),
         view: Keyword.get(opts, :view, :isometric),
         edges: Keyword.get(opts, :edges, false),
         clip: clip
       }}
    end
  end

  def build_layers(layers, opts) do
    with {:ok, items} <-
           Geometry.collect(layers, fn
             {source, {r, g, b} = color}
             when is_integer(r) and r in 0..255 and is_integer(g) and g in 0..255 and
                    is_integer(b) and b in 0..255 ->
               with {:ok, result} <- Geometry.result(source),
                    {:ok, data} <- build(result, opts),
                    do: {:ok, {data, Tuple.to_list(color)}}

             _ ->
               {:error, :invalid_options}
           end),
         true <- items != [] do
      [{first, _} | _] = items

      combined =
        Enum.reduce(
          items,
          %{first | vertices: [], triangles: [], lines: [], edge_lines: []}
          |> Map.put(:triangle_colors, []),
          fn {data, color}, acc ->
            offset = length(acc.vertices)

            %{
              acc
              | vertices: acc.vertices ++ data.vertices,
                triangles:
                  acc.triangles ++
                    Enum.map(data.triangles, fn t -> Enum.map(t, &(&1 + offset)) end),
                lines: acc.lines ++ data.lines,
                edge_lines: acc.edge_lines ++ data.edge_lines,
                triangle_colors:
                  acc.triangle_colors ++ List.duplicate(color, length(data.triangles))
            }
          end
        )

      revision =
        items
        |> Enum.map(fn {data, color} -> {data.revision, color} end)
        |> :erlang.term_to_binary()
        |> Geometry.hash()

      {:ok, %{combined | revision: revision}}
    else
      false -> {:error, :empty_shape}
      error -> error
    end
  end

  defp clip(nil), do: {:ok, nil}

  defp clip({%Plane{} = plane, keep}) when keep in [:positive, :negative] do
    with {:ok, frame} <- Plane.frame(plane),
         do:
           {:ok,
            %{origin: Tuple.to_list(frame.origin), normal: Tuple.to_list(frame.n), keep: keep}}
  end

  defp clip(_), do: {:error, :invalid_options}
end
