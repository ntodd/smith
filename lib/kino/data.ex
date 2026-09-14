defmodule Smith.Kino.Data do
  @moduledoc false

  # Shared browser payload for Livebook and documentation snapshots.
  def build(result, opts) do
    tolerance = Keyword.get(opts, :tolerance, 0.03)
    angular = Keyword.get(opts, :angular_tolerance, 0.5)

    with {:ok, mesh} <- OCEx.mesh(result.shape, tolerance, angular),
         {:ok, lines} <- lines(result.shape, mesh.triangles, tolerance, angular) do
      {:ok,
       %{
         vertices: Enum.map(mesh.vertices, &Tuple.to_list/1),
         triangles: Enum.map(mesh.triangles, &Tuple.to_list/1),
         lines: Enum.map(lines, fn line -> Enum.map(line, &Tuple.to_list/1) end),
         revision: result.revision,
         label: Keyword.get(opts, :label, "Smith preview")
       }}
    end
  end

  defp lines(shape, [], tolerance, angular), do: OCEx.polylines(shape, tolerance, angular)
  defp lines(_shape, _triangles, _tolerance, _angular), do: {:ok, []}
end
