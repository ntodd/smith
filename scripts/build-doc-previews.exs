# Build browser snapshots from the examples immediately preceding each marker.
defmodule Smith.DocPreviews do
  def sources(root) do
    guides =
      for path <- [
            Path.join(root, "README.md")
            | Path.wildcard(Path.join(root, "{guides,examples}/*.{md,livemd}"))
          ],
          do: {path, File.read!(path)}

    api =
      for module <- Application.spec(:smith, :modules),
          {:docs_v1, _, _, _, module_doc, _, docs} = Code.fetch_docs(module),
          {name, %{"en" => text}} <- [
            {"module", module_doc}
            | Enum.map(docs, fn {id, _, _, doc, _} -> {inspect(id), doc} end)
          ] do
        # Keep only IEx input; ExUnit checks the expected outputs separately.
        text =
          Regex.replace(~r/(?:^    .*(?:\n|$))+/m, text, fn block ->
            if String.contains?(block, "iex>") do
              code =
                Regex.scan(~r/^    (?:iex>|\.\.\.>) (.*)$/m, block)
                |> Enum.map_join("\n", fn [_, line] -> line end)

              "```elixir\n" <> code <> "\n```\n"
            else
              block
            end
          end)

        {"#{inspect(module)} #{name}", text}
      end

    guides ++ api
  end

  def build(sources, output) do
    names =
      Enum.reduce(sources, MapSet.new(), fn {path, source}, names ->
        markers =
          Regex.scan(
            ~r/<div class="smith-doc-preview" data-preview="([a-z0-9-]+)" data-model="([a-z_]+)" data-label="([^"]+)">/,
            source,
            return: :index
          )

        previews =
          Enum.map(markers, fn [{offset, _} | values] ->
            [id, variable, label] =
              Enum.map(values, fn {start, size} -> binary_part(source, start, size) end)

            {offset, {:preview, id, variable, label}}
          end)

        if previews == [] do
          names
        else
          last = previews |> List.last() |> elem(0)

          blocks =
            for [{offset, _}, {start, size}] <-
                  Regex.scan(~r/```elixir\n(.*?)\n```/s, source, return: :index),
                offset < last,
                do: {offset, {:code, binary_part(source, start, size)}}

          {_, _, names} =
            Enum.reduce(
              Enum.sort(blocks ++ previews),
              {[], Code.env_for_eval(file: path), names},
              fn
                {_, {:code, code}}, {bindings, env, names} ->
                  forms =
                    case Code.string_to_quoted!(code, file: path) do
                      {:__block__, _, forms} -> forms
                      form -> [form]
                    end

                  forms =
                    Enum.reject(forms, fn
                      {{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, _} -> true
                      _ -> false
                    end)

                  {_, bindings, env} =
                    Code.eval_quoted_with_env({:__block__, [], forms}, bindings, env)

                  {bindings, env, names}

                {_, {:preview, id, variable, label}}, {bindings, env, names} ->
                  if MapSet.member?(names, id),
                    do: raise("Duplicate documentation preview: #{id}")

                  {_, model} =
                    Enum.find(bindings, fn {name, _} -> Atom.to_string(name) == variable end) ||
                      raise("#{path}: unknown preview variable #{variable}")

                  data = snapshot(model, label)
                  File.write!(Path.join(output, id <> ".json"), JSON.encode!(data))
                  IO.puts("Built documentation preview: #{id}")
                  {bindings, env, MapSet.put(names, id)}
              end
            )

          names
        end
      end)

    # Removed examples must not leave stale assets in subsequent documentation builds.
    for file <- Path.wildcard(Path.join(output, "*.json")),
        not MapSet.member?(names, Path.basename(file, ".json")),
        do: File.rm!(file)
  end

  defp snapshot({:ok, model}, label), do: snapshot(model, label)

  defp snapshot(%Smith.Drawing{} = drawing, label) do
    {:ok, svg} = Smith.Drawing.svg(drawing, title: label)
    %{svg: svg, label: label, revision: drawing.source_revision}
  end

  defp snapshot(svg, label) when is_binary(svg) do
    true = String.starts_with?(svg, "<svg")
    %{svg: svg, label: label, revision: hash(svg)}
  end

  defp snapshot(%OCEx.Shape{} = shape, label) do
    {:ok, brep} = OCEx.to_brep(shape)
    snapshot(%{shape: shape, revision: hash(brep)}, label)
  end

  defp snapshot(shapes, label) when is_list(shapes) do
    {:ok, compound} =
      OCEx.compound(
        Enum.map(shapes, fn
          %{shape: shape} -> shape
          %OCEx.Shape{} = shape -> shape
        end)
      )

    snapshot(compound, label)
  end

  defp snapshot(%{vertices: vertices, triangles: triangles}, label) do
    data = %{
      vertices: Enum.map(vertices, &Tuple.to_list/1),
      triangles: Enum.map(triangles, &Tuple.to_list/1),
      lines: []
    }

    Map.merge(data, %{label: label, revision: hash(JSON.encode!(data))})
  end

  defp snapshot(%{shape: _, revision: _} = result, label) do
    {:ok, data} = Smith.Kino.Data.build(result, label: label)

    if data.triangles == [] and data.lines == [],
      do: raise("Empty documentation preview: #{label}")

    data
  end

  defp snapshot(recipe, label) do
    {:ok, result} = Smith.evaluate(recipe)
    snapshot(result, label)
  end

  defp hash(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end

root = Path.expand("..", __DIR__)
output = Keyword.get(binding(), :output, Path.join(root, ".doc-preview-assets")) |> Path.expand()
File.mkdir_p!(output)
work = Path.join(System.tmp_dir!(), "smith-doc-previews-#{System.unique_integer([:positive])}")
File.mkdir_p!(work)

try do
  File.cd!(work, fn -> Smith.DocPreviews.build(Smith.DocPreviews.sources(root), output) end)
after
  File.rm_rf!(work)
end
