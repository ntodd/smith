# Run from the Smith repository: mix run scripts/check-notebooks.exs
# Setup is supplied by Mix; remaining cells share bindings and lexical environment.
root = Path.expand("../examples", __DIR__)
work = Path.join(System.tmp_dir!(), "smith-notebooks-#{System.unique_integer([:positive])}")
File.mkdir_p!(work)
try do
  File.cd!(work, fn ->
    for path <- Path.wildcard(Path.join(root, "*.livemd")) do
      [_setup | cells] = Regex.scan(~r/```elixir\n(.*?)\n```/s, File.read!(path), capture: :all_but_first)
      Enum.reduce(cells, {[], Code.env_for_eval(file: path)}, fn [code], {binding, env} ->
        {_value, binding, env} = Code.eval_quoted_with_env(Code.string_to_quoted!(code), binding, env)
        {binding, env}
      end)
      IO.puts("Verified notebook: #{Path.basename(path)}")
    end
  end)
after
  File.rm_rf!(work)
end
