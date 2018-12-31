defmodule Ane do
  @moduledoc """
  Documentation for Ane.
  """

  def new(n, opts \\ []) do
    read = Keyword.get(opts, :read_concurrency, false)
    write = Keyword.get(opts, :write_concurrency, false)

    compressed =
      case Keyword.get(opts, :compressed, false) do
        true ->
          [:compressed]

        false ->
          []
      end

    table_opts = [
      :set,
      :public,
      {:read_concurrency, read},
      {:write_concurrency, write}
      | compressed
    ]

    case Keyword.get(opts, :mode, :ane) do
      :ane ->
        a1 = :atomics.new(n, signed: false)
        a2 = :atomics.new(n, signed: false)
        e = :ets.new(:ane, table_opts)

        {a1, a2, e, %{}}

      :ets ->
        e = :ets.new(:ets, table_opts)

        {n, e}
    end
  end

  defp lookup(a2, e, i, version) do
    case :ets.lookup(e, [i, version]) do
      [{_, value}] ->
        {version, value}

      [] ->
        lookup(a2, e, i, :atomics.get(a2, i))
    end
  end

  def get({a1, a2, e, cache} = ane, i) do
    i = i + 1

    case :atomics.get(a2, i) do
      0 ->
        {ane, nil}

      version ->
        case cache do
          # cache hit
          %{^i => {^version, value}} ->
            {ane, value}

          # cache miss
          _ ->
            {_, value} = updated = lookup(a2, e, i, version)
            {{a1, a2, e, Map.put(cache, i, updated)}, value}
        end
    end
  end

  def get({n, e} = ane, i) when is_integer(i) and i >= 0 and i < n do
    case :ets.lookup(e, i) do
      [{_, value}] ->
        {ane, value}

      [] ->
        {ane, nil}
    end
  end

  defp commit(a2, e, i, expected, desired) do
    case :atomics.compare_exchange(a2, i, expected, desired) do
      :ok ->
        :ets.delete(e, [i, expected])

      actual when actual < desired ->
        commit(a2, e, i, actual, desired)

      _ ->
        :ets.delete(e, [i, desired])
    end
  end

  def put({a1, a2, e, _} = ane, i, value) do
    i = i + 1

    new_version = :atomics.add_get(a1, i, 1)

    :ets.insert(e, {[i, new_version], value})

    commit(a2, e, i, new_version - 1, new_version)

    ane
  end

  def put({n, e} = ane, i, value) when is_integer(i) and i >= 0 and i < n do
    :ets.insert(e, {i, value})

    ane
  end

  defp clean_table(_, _, :"$end_of_table"), do: :ok

  defp clean_table(e, current_versions, [i, version] = key) do
    case current_versions do
      %{^i => current_version} when version < current_version ->
        :ets.delete(e, key)

      _ ->
        :ok
    end

    clean_table(e, current_versions, :ets.next(e, key))
  end

  def clean({_, a2, e, _} = ane) do
    size = get_size(ane)

    current_versions =
      1..size
      |> Enum.map(fn i -> {i, :atomics.get(a2, i)} end)
      |> Enum.into(%{})

    :ets.safe_fixtable(e, true)
    clean_table(e, current_versions, :ets.first(e))
    :ets.safe_fixtable(e, false)

    :ok
  end

  def clean({_, _}), do: :ok

  def get_mode({_, _, _, _}), do: :ane
  def get_mode({_, _}), do: :ets

  def get_size({_, a2, _, _}), do: :atomics.info(a2).size
  def get_size({n, _}), do: n

  def get_table({_, _, e, _}), do: e
  def get_table({_, e}), do: e
end
