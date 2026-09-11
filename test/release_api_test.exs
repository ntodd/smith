defmodule Smith.ReleaseAPITest do
  use ExUnit.Case, async: true

  test "invalid recipes return tagged errors, including nested feature recipes" do
    assert {:error, :invalid_recipe} = Smith.evaluate(nil)

    assert {:error, %Smith.Error{step: 1, operation: :compound, reason: :invalid_recipe}} =
             Smith.compound([Smith.box(1, 2, 3), nil]) |> Smith.evaluate()
  end
end
