defmodule Ane do
  @moduledoc """
  Documentation for Ane.
  """

  @type atomics_ref() :: :atomics.atomics_ref()

  @type tid() :: :ets.tid()

  @type t_for_ane_mode() :: {tid(), atomics_ref(), atomics_ref(), map()}

  @type t_for_ets_mode() :: {tid(), pos_integer()}

  @type t() :: t_for_ane_mode() | t_for_ets_mode()

  @spec new(pos_integer(), keyword()) :: t()

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

        {e, a1, a2, %{}}

      :ets ->
        e = :ets.new(:ets, table_opts)

        {e, n}
    end
  end

  @spec lookup(tid(), atomics_ref(), non_neg_integer(), non_neg_integer()) :: any()

  defp lookup(e, a2, i, version) do
    case :ets.lookup(e, [i, version]) do
      [{_, value}] ->
        value

      [] ->
        lookup(e, a2, i, :atomics.get(a2, i))
    end
  end

  @spec get(t(), non_neg_integer()) :: {t(), any()}

  def get({e, a1, a2, cache} = ane, i) do
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
            value = lookup(e, a2, i, version)
            {{e, a1, a2, Map.put(cache, i, {version, value})}, value}
        end
    end
  end

  def get({e, n} = ane, i) when is_integer(i) and i >= 0 and i < n do
    case :ets.lookup(e, i) do
      [{_, value}] ->
        {ane, value}

      [] ->
        {ane, nil}
    end
  end

  @spec commit(tid(), atomics_ref(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok

  defp commit(e, a2, i, expected, desired) do
    case :atomics.compare_exchange(a2, i, expected, desired) do
      :ok ->
        :ets.delete(e, [i, expected])
        :ok

      actual when actual < desired ->
        commit(e, a2, i, actual, desired)

      _ ->
        :ets.delete(e, [i, desired])
        :ok
    end
  end

  @spec put(t(), non_neg_integer(), any()) :: :ok

  def put({e, a1, a2, _}, i, value) do
    i = i + 1

    new_version = :atomics.add_get(a1, i, 1)

    :ets.insert(e, {[i, new_version], value})

    commit(e, a2, i, new_version - 1, new_version)
  end

  def put({e, n}, i, value) when is_integer(i) and i >= 0 and i < n do
    :ets.insert(e, {i, value})
    :ok
  end

  @spec clean_table(tid(), atomics_ref(), map(), any()) :: :ok

  defp clean_table(_, _, _, :"$end_of_table"), do: :ok

  defp clean_table(e, a2, cache, [i, version] = key) do
    {updated_cache, current_version} =
      case cache do
        %{^i => v} ->
          {cache, v}

        _ ->
          v = :atomics.get(a2, i)
          {Map.put(cache, i, v), v}
      end

    if version < current_version do
      :ets.delete(e, key)
    end

    clean_table(e, a2, updated_cache, :ets.next(e, key))
  end

  @spec clean(t()) :: :ok

  def clean({e, _, a2, _}) do
    :ets.safe_fixtable(e, true)
    clean_table(e, a2, %{}, :ets.first(e))
    :ets.safe_fixtable(e, false)
    :ok
  end

  def clean({_, _}), do: :ok

  @spec get_mode(t()) :: :ane | :ets

  def get_mode({_, _, _, _}), do: :ane
  def get_mode({_, _}), do: :ets

  @spec get_size(t()) :: pos_integer()

  def get_size({_, _, a2, _}), do: :atomics.info(a2).size
  def get_size({_, n}), do: n

  @spec get_table(t()) :: :ets.tid()

  def get_table({e, _, _, _}), do: e
  def get_table({e, _}), do: e
end
