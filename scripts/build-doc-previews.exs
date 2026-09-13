# Evaluate marked guide examples in order, then save meshes for the static docs.
root = Path.expand("..", __DIR__)
output = Keyword.get(binding(), :output, Path.join(root, ".doc-preview-assets")) |> Path.expand()
File.mkdir_p!(output)
work = Path.join(System.tmp_dir!(), "smith-doc-previews-#{System.unique_integer([:positive])}")
File.mkdir_p!(work)

try do
  File.cd!(work, fn ->
    paths = [Path.join(root, "README.md") | Path.wildcard(Path.join(root, "guides/*.md"))]

    Enum.reduce(paths, MapSet.new(), fn path, names ->
      source = File.read!(path)

      markers =
        Regex.scan(
          ~r/<div class="smith-doc-preview" data-preview="([a-z0-9-]+)" data-model="([a-z_]+)" data-label="([^"]+)">/,
          source, return: :index)

      if markers == [] do
        names
      else
        previews =
          Enum.map(markers, fn [{offset, _}, id, variable, label] ->
            {offset,
             {:preview, binary_part(source, elem(id, 0), elem(id, 1)),
              binary_part(source, elem(variable, 0), elem(variable, 1)),
              binary_part(source, elem(label, 0), elem(label, 1))}}
          end)

        last = previews |> List.last() |> elem(0)

        blocks =
          for [{offset, _}, {start, size}] <-
                Regex.scan(~r/```elixir\n(.*?)\n```/s, source, return: :index),
              offset < last do
            {offset, {:code, binary_part(source, start, size)}}
          end

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
                if MapSet.member?(names, id), do: raise("Duplicate documentation preview: #{id}")

                {_, model} =
                  Enum.find(bindings, fn {name, _} -> Atom.to_string(name) == variable end) ||
                    raise("#{path}: unknown preview variable #{variable}")

                result =
                  case model do
                    {:ok, result} ->
                      result

                    %Smith.Result{} = result ->
                      result

                    %Smith.Assembly.Result{} = result ->
                      result

                    recipe ->
                      {:ok, result} = Smith.evaluate(recipe)
                      result
                  end

                {:ok, mesh} = OCEx.mesh(result.shape, 0.03, 0.5)

                data = %{
                  label: label,
                  revision: result.revision,
                  vertices: Enum.map(mesh.vertices, &Tuple.to_list/1),
                  triangles: Enum.map(mesh.triangles, &Tuple.to_list/1)
                }

                File.write!(Path.join(output, id <> ".json"), JSON.encode!(data))
                IO.puts("Built documentation preview: #{id}")
                {bindings, env, MapSet.put(names, id)}
            end
          )

        names
      end
    end)
  end)
after
  File.rm_rf!(work)
end
