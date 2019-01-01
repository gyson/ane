defmodule Ane do
  @moduledoc """

  A very efficient way to share mutable data with `:atomics` and `:ets`.

  [https://github.com/gyson/ane](https://github.com/gyson/ane) has detailed guides.
  """

  @type atomics_ref() :: :atomics.atomics_ref()

  @type tid() :: :ets.tid()

  @type t_for_ane_mode() :: {tid(), atomics_ref(), atomics_ref(), map()}

  @type t_for_ets_mode() :: {tid(), pos_integer()}

  @type t() :: t_for_ane_mode() | t_for_ets_mode()

  @doc """

  Create and return an Ane instance.

  ## Options

    * `:mode` (atom) - set mode of Ane instance. Default to `:ane`.
    * `:read_concurrency` (boolean) - set read_concurrency for underneath ETS table. Default to `false`.
    * `:write_concurrency` (boolean) - set write_concurrency for underneath ETS table. Default to `false`.
    * `:compressed` (boolean) - set compressed for underneath ETS table. Default to `false`.

  ## Example

      iex> a = Ane.new(1, read_concurrency: false, write_concurrency: false, compressed: false)
      iex> t = Ane.get_table(a)
      iex> :ets.info(t, :read_concurrency)
      false
      iex> :ets.info(t, :write_concurrency)
      false
      iex> :ets.info(t, :compressed)
      false

  """

  @spec new(pos_integer(), keyword()) :: t()

  def new(size, options \\ []) do
    read = Keyword.get(options, :read_concurrency, false)
    write = Keyword.get(options, :write_concurrency, false)

    compressed =
      case Keyword.get(options, :compressed, false) do
        true ->
          [:compressed]

        false ->
          []
      end

    table_options = [
      :set,
      :public,
      {:read_concurrency, read},
      {:write_concurrency, write}
      | compressed
    ]

    case Keyword.get(options, :mode, :ane) do
      :ane ->
        a1 = :atomics.new(size, signed: true)
        a2 = :atomics.new(size, signed: true)
        e = :ets.new(__MODULE__, table_options)

        {e, a1, a2, %{}}

      :ets ->
        e = :ets.new(__MODULE__, table_options)

        {e, size}
    end
  end

  @doc """

  Get value at one-based index in Ane instance.

  ## Example

      iex> a = Ane.new(1)
      iex> {a, value} = Ane.get(a, 1)
      iex> value
      nil
      iex> Ane.put(a, 1, "hello")
      :ok
      iex> {_, value} = Ane.get(a, 1)
      iex> value
      "hello"

  """

  @spec get(t(), pos_integer()) :: {t(), any()}

  def get({e, a1, a2, cache} = ane, i) do
    case :atomics.get(a2, i) do
      version when version > 0 ->
        case cache do
          # cache hit
          %{^i => {^version, value}} ->
            {ane, value}

          # cache miss
          _ ->
            value = lookup(e, a2, i, version)
            {{e, a1, a2, Map.put(cache, i, {version, value})}, value}
        end

      0 ->
        {ane, nil}

      _ ->
        raise ArgumentError, "Ane instance is destroyed"
    end
  end

  def get({e, size} = ane, i) when is_integer(i) and i > 0 and i <= size do
    case :ets.lookup(e, i) do
      [{_, value}] ->
        {ane, value}

      [] ->
        {ane, nil}
    end
  end

  defp lookup(e, a2, i, version) do
    case :ets.lookup(e, [i, version]) do
      [{_, value}] ->
        value

      [] ->
        lookup(e, a2, i, :atomics.get(a2, i))
    end
  end

  @doc """

  Put value at one-based index in Ane instance.

  ## Example

      iex> a = Ane.new(1)
      iex> {a, value} = Ane.get(a, 1)
      iex> value
      nil
      iex> Ane.put(a, 1, "world")
      :ok
      iex> {_, value} = Ane.get(a, 1)
      iex> value
      "world"

  """

  @spec put(t(), pos_integer(), any()) :: :ok

  def put({e, a1, a2, _} = _ane, i, value) do
    case :atomics.add_get(a1, i, 1) do
      new_version when new_version > 0 ->
        :ets.insert(e, {[i, new_version], value})
        commit(e, a2, i, new_version - 1, new_version)

      _ ->
        raise ArgumentError, "Ane instance is destroyed"
    end
  end

  def put({e, size} = _ane, i, value) when is_integer(i) and i > 0 and i <= size do
    :ets.insert(e, {i, value})
    :ok
  end

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

  @doc """

  Clear garbage data which could be generated when `Ane.put` is interrupted.

  ## Example

      iex> a = Ane.new(1)
      iex> Ane.clear(a)
      :ok

  """

  @spec clear(t()) :: :ok

  def clear({e, _, a2, _} = _ane) do
    :ets.safe_fixtable(e, true)
    clear_table(e, a2, %{}, :ets.first(e))
    :ets.safe_fixtable(e, false)
    :ok
  end

  def clear({_, _} = _ane), do: :ok

  defp clear_table(_, _, _, :"$end_of_table"), do: :ok

  defp clear_table(e, a2, cache, [i, version] = key) do
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

    clear_table(e, a2, updated_cache, :ets.next(e, key))
  end

  @doc """

  Destroy an Ane instance.


  ## Example

      iex> a = Ane.new(1)
      iex> Ane.destroyed?(a)
      false
      iex> Ane.destroy(a)
      :ok
      iex> Ane.destroyed?(a)
      true

  """

  @spec destroy(t()) :: :ok

  def destroy({e, a1, a2, _} = ane) do
    # min for 64 bits signed number
    min = -9_223_372_036_854_775_808

    1..get_size(ane)
    |> Enum.each(fn i ->
      :atomics.put(a1, i, min)
      :atomics.put(a2, i, min)
    end)

    :ets.delete(e)
    :ok
  end

  def destroy({e, _} = _ane) do
    :ets.delete(e)
    :ok
  end

  @doc """

  Check if Ane instance is destroyed.

  ## Example

      iex> a = Ane.new(1)
      iex> Ane.destroyed?(a)
      false
      iex> Ane.destroy(a)
      :ok
      iex> Ane.destroyed?(a)
      true

  """

  @spec destroyed?(t()) :: boolean()

  def destroyed?({e, _, _, _} = _ane), do: :ets.info(e, :type) == :undefined
  def destroyed?({e, _} = _ane), do: :ets.info(e, :type) == :undefined

  @doc """

  Get mode of Ane instance.

  ## Example

      iex> Ane.new(1) |> Ane.get_mode()
      :ane
      iex> Ane.new(1, mode: :ane) |> Ane.get_mode()
      :ane
      iex> Ane.new(1, mode: :ets) |> Ane.get_mode()
      :ets

  """

  @spec get_mode(t()) :: :ane | :ets

  def get_mode({_, _, _, _} = _ane), do: :ane
  def get_mode({_, _} = _ane), do: :ets

  @doc """

  Get size of Ane instance.

  ## Example

      iex> Ane.new(1) |> Ane.get_size()
      1
      iex> Ane.new(10) |> Ane.get_size()
      10

  """

  @spec get_size(t()) :: pos_integer()

  def get_size({_, _, a2, _} = _ane), do: :atomics.info(a2).size
  def get_size({_, size} = _ane), do: size

  @doc """

  Get ETS table of Ane instance.

  The returned ETS table could be used to

    * get more info via `:ets.info`
    * change ownership via `:ets.give_away`
    * change configuration via `:ets.setopts`

  ## Example

      iex> Ane.new(1) |> Ane.get_table() |> :ets.info(:type)
      :set

  """

  @spec get_table(t()) :: tid()

  def get_table({e, _, _, _} = _ane), do: e
  def get_table({e, _} = _ane), do: e
end
