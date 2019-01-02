defmodule Ane.Bench.Comparison do
  def run(read_percent, parallel) do
    write_percent = Float.round(100.0 - read_percent, 2)
    read_ratio = read_percent / 100

    for mode <- [:ane, :ets],
        size <- [16],
        read <- [true],
        write <- [true],
        info_size <- [100] do
      a = Ane.new(size, mode: mode, read_concurrency: read, write_concurrency: write)

      for i <- 1..size do
        Ane.put(a, i, :rand.uniform())
      end

      operations =
        Enum.map(1..10_000, fn _ ->
          if :rand.uniform() < read_ratio do
            {:get, :rand.uniform(size)}
          else
            {:put, :rand.uniform(size), 1..info_size |> Enum.map(fn _ -> :rand.uniform(1000) end)}
          end
        end)

      {"size=#{size}, mode=#{mode}, Ane.get=#{read_percent}%, Ane.put=#{write_percent}%,  " <>
         "read_concurrency=#{read}, write_concurrency=#{write}, info_size=#{info_size}",
       {fn ops ->
          Enum.reduce(ops, a, fn
            {:get, i}, a ->
              {a, _} = Ane.get(a, i)
              a

            {:put, i, v}, a ->
              Ane.put(a, i, v)
              a
          end)
        end,
        before_each: fn _ ->
          operations
        end}}
    end
    |> Enum.into(%{})
    |> Benchee.run(parallel: parallel, time: 10)
  end
end

Ane.Bench.Comparison.run(95, 16)

# for read_percent <- [0, 50, 80, 90, 95, 99, 99.9, 99.99, 100],
#     parallel <- [1, 4, 16] do
#   Ane.Bench.Comparison.run(read_percent, parallel)
# end
