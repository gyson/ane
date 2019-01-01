# Ane

Ane (atomics and ets) is a library to share mutable data efficiently by utilizing atomics and ets modules.

## How it works ?

* It stores all data with versionstamp in ETS table.
* It keeps a cached copy with versionstamp locally.
* It uses atomics to save latest versionstamp and syncs data between ETS table and local cache.
* Read operation would use cached data if cache hits and fallback to ETS lookup if cache expires.
* Write operation would update ETS table and versionstamp in atomics array.

## Properties

Similar to atomics standalone,

* Ane's read/write operations guarantee atomicity.
* Ane's read/write operations are mutually ordered.
* Ane uses one-based index.

Compare to atomics standalone,

* Ane could save arbitrary term instead of 64 bits integer.

Compare to ETS standalone,

* Ane has much faster read operation when cache hit (this is common for read-heavy application).

  - It needs 1 Map operation and 1 atomics operation.
  - It does not need to copy data from ETS table.
  - It does not need to lookup from ETS table, which could make underneath ETS table's write operation faster.
  - Benchmarking showed that it's 2 ~ 10+ times faster.

* Ane could have slightly slower read operation when cache missed or expired.

  - It needs 2 Map operations, 1+ atomics operations and 1+ ETS operations.
  - Ane could be faster for "hot key" case.

* Ane could have slower write operation.

  - It needs to do 2 ETS operations and 2+ atomics operations.
  - Ane could be faster for "hot key" case.

* Ane has much faster read/write operations for "hot key" case.

  - ETS table performance degrades when a key is too hot due to internal locking.
  - Ane avoids "hot key" issue by distributing read/write operations to different keys in underneath ETS table.

* Ane only supports `:atomics`-like one-based index as key.

  - I feel it's possible to extend it to be `:ets`-like arbitrary key with some extra complexity. But I do not have that need at the moment.

## Installation

**Note**: it requires OTP 21.2 for `:atomics`, which was released on Dec 12, 2018.

It can be installed by adding Ane to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ane, "~> 0.1.0"}
  ]
end
```

API reference can be found at [https://hexdocs.pm/ane/Ane.html](https://hexdocs.pm/ane/Ane.html).

## Usage

```elixir
iex(1)> a = Ane.new(1)
{#Reference<0.376557974.4000972807.196270>,
 #Reference<0.376557974.4000972807.196268>,
 #Reference<0.376557974.4000972807.196269>, %{}}
iex(2)> Ane.put(a, 1, "hello")
:ok
iex(3)> {a, value} = Ane.get(a, 1)
{{#Reference<0.376557974.4000972807.196270>,
  #Reference<0.376557974.4000972807.196268>,
  #Reference<0.376557974.4000972807.196269>, %{1 => {1, "hello"}}}, "hello"}
iex(4)> value
"hello"
iex(5)> Ane.put(a, 1, "world")
:ok
iex(6)> {a, value} = Ane.get(a, 1)
{{#Reference<0.376557974.4000972807.196270>,
  #Reference<0.376557974.4000972807.196268>,
  #Reference<0.376557974.4000972807.196269>, %{1 => {2, "world"}}}, "world"}
iex(7)> value
"world"
```

## Compare Ane and ETS Standalone

Generally, Ane is faster for read-heavy case and ETS standalone is faster for write-heavy case. This library provide a way to switch between them seamlessly.

By specify `mode: :ets` as following, it will use ETS standalone instead:

```elixir
iex(1)> a = Ane.new(1, mode: :ets)
{#Reference<0.2878440188.2128478212.58871>, 1}
iex(2)> Ane.put(a, 1, "hello")
:ok
iex(3)> {a, value} = Ane.get(a, 1)
{{#Reference<0.2878440188.2128478212.58871>, 1}, "hello"}
iex(4)> value
"hello"
iex(5)> Ane.put(a, 1, "world")
:ok
iex(6)> {a, value} = Ane.get(a, 1)
{{#Reference<0.2878440188.2128478212.58871>, 1}, "world"}
iex(7)> value
"world"
```

This is useful for comparing performance between Ane and ETS standalone.

## Performance Tuning

The `read_concurrency` and `write_concurrency` from ETS table are important configurations for performance tuning. You can adjust it while creating Ane instance like following:

```elixir
ane = Ane.new(1, read_concurrency: true, write_concurrency: true)
```

These options would be passed to underneath ETS table. You can read more docs about `read_concurrency` and `write_concurrency` at [erlang ets docs](http://erlang.org/doc/man/ets.html#new-2).

## License

MIT
