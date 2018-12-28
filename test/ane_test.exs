defmodule AneTest do
  use ExUnit.Case
  doctest Ane

  test "greets the world" do
    assert Ane.hello() == :world
  end
end
