defmodule Smith.InspectionWorkflowTest do
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  test "standalone text-only workflow catches and repairs a misplaced hole", %{tmp_dir: dir} do
    file = Path.expand("../examples/inspection.exs", __DIR__)
    {:__block__, _, [_setup | forms]} = Code.string_to_quoted!(File.read!(file))

    binding =
      File.cd!(dir, fn ->
        {_, binding} = Code.eval_quoted({:__block__, [], forms}, [], file: file)
        binding
      end)

    failed = Keyword.fetch!(binding, :failed)
    passed = Keyword.fetch!(binding, :passed)
    assert failed.status == :failed and passed.status == :passed
    assert_in_delta hd(failed.checks).measured, 18, 1.0e-7
    assert_in_delta List.last(passed.checks).measured, 20, 1.0e-7
    artifacts = Keyword.fetch!(binding, :artifacts)
    report = artifacts.report |> File.read!() |> JSON.decode!()
    assert report["status"] == "passed"
    assert length(report["artifacts"]) == 4

    for artifact <- report["artifacts"] do
      assert artifact["source_revision"] == report["models"]["plate"]["revision"]
      png = File.read!(Path.join(artifacts.directory, artifact["path"]))
      assert png =~ artifact["geometry_revision"]
    end

    assert File.read!(Path.join(artifacts.directory, "dimensions.svg")) =~ "20.00 mm"
    assert File.exists?(Keyword.fetch!(binding, :files).three_mf)
  end
end
