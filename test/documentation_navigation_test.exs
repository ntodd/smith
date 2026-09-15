defmodule Smith.DocumentationNavigationTest do
  use ExUnit.Case, async: true

  test "release notebooks are discoverable, use Hex, and have distinct guide pages" do
    root = Path.expand("..", __DIR__)
    docs = Mix.Project.config()[:docs]

    extras =
      for extra <- docs[:extras] do
        case extra do
          {path, opts} ->
            {path, Keyword.get(opts, :filename, Path.basename(path, Path.extname(path)))}

          path ->
            {path, Path.basename(path, Path.extname(path))}
        end
      end

    ids = Enum.map(extras, &elem(&1, 1))

    assert length(ids) == length(Enum.uniq(ids)),
           "guide and notebook pages must not overwrite each other"

    catalog = File.read!(Path.join(root, "guides/livebook.md"))
    version = Mix.Project.config()[:version]

    for notebook <- Path.wildcard(Path.join(root, "examples/*.livemd")) do
      path = Path.relative_to(notebook, root)
      assert Enum.any?(extras, fn {source, _} -> source == path end), path
      assert catalog =~ Path.basename(notebook), path
      source = File.read!(notebook)
      [_, setup] = Regex.run(~r/```elixir\n(.*?)\n```/s, source)
      {{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, [deps]} = Code.string_to_quoted!(setup)
      requirement = Keyword.fetch!(deps, :smith)
      assert is_binary(requirement), "release setup must use Hex: #{path}"
      assert Version.match?(version, requirement), path
      refute source =~ ~r/^## Section\s*$/m, "unfinished notebook section: #{path}"
    end
  end
end
