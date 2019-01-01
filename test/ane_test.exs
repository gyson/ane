defmodule AneTest do
  use ExUnit.Case
  doctest Ane

  for mode <- [:ane, :ets] do
    test "#{mode} should work" do
      a = Ane.new(1, mode: unquote(mode))

      {a, value} = Ane.get(a, 1)
      assert value == nil

      Ane.put(a, 1, "hello")

      {a, value} = Ane.get(a, 1)
      assert value == "hello"

      Ane.put(a, 1, "world")

      {_, value} = Ane.get(a, 1)
      assert value == "world"
    end
  end

  test "successful Ane.put should not left any garbage" do
    a = Ane.new(1)

    1..64
    |> Enum.map(fn _ ->
      Task.async(fn ->
        loop_put(a, 1000)
        :ok
      end)
    end)
    |> Enum.each(fn t ->
      Task.await(t)
    end)

    assert get_table_size(a) == 1
  end

  def loop_put(a) do
    Ane.put(a, 1, :rand.uniform())
    loop_put(a)
  end

  def loop_put(a, n) do
    if n > 0 do
      Ane.put(a, 1, :rand.uniform())
      loop_put(a, n - 1)
    end
  end

  def get_table_size(a) do
    :ets.info(Ane.get_table(a), :size)
  end

  def generate_garbage(a) do
    pids =
      for _ <- 1..64 do
        spawn(fn ->
          loop_put(a)
        end)
      end

    Process.sleep(100)

    for pid <- pids do
      # interrupt `Ane.put` call
      :erlang.exit(pid, :kill)
    end

    Process.sleep(100)

    if get_table_size(a) <= 1 do
      generate_garbage(a)
    end
  end

  test "Ane.clear should be able to collect garbage" do
    a = Ane.new(1)

    generate_garbage(a)

    assert get_table_size(a) > 1

    Ane.clear(a)

    assert get_table_size(a) == 1
  end

  test "Ane.destroy should work" do
    a = Ane.new(1)

    assert Ane.destroyed?(a) == false

    assert Ane.destroy(a) == :ok

    assert Ane.destroyed?(a) == true

    assert_raise ArgumentError, "Ane instance is destroyed", fn ->
      Ane.get(a, 1)
    end

    assert_raise ArgumentError, "Ane instance is destroyed", fn ->
      Ane.put(a, 1, "hello")
    end
  end
end
