defmodule AneTest do
  use ExUnit.Case
  doctest Ane

  for mode <- [:ane, :ets] do
    test "#{mode} should work" do
      x = Ane.new(1, mode: unquote(mode))

      {x, value} = Ane.get(x, 0)
      assert value == nil

      Ane.put(x, 0, "hello")

      {x, value} = Ane.get(x, 0)
      assert value == "hello"

      Ane.put(x, 0, "world")

      {_, value} = Ane.get(x, 0)
      assert value == "world"
    end
  end
end
