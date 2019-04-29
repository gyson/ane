# Ane

Ane (atomics and ets) is a library to share mutable data efficiently by
utilizing [atomics](http://erlang.org/doc/man/atomics.html) and
[ets](http://erlang.org/doc/man/ets.html) modules.

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

Compare to [persistent_term](http://erlang.org/doc/man/persistent_term.html),

* Like persistent_term, Ane's read operation with cache hit is lock-free and copying-free (no need to copy since data exists in local cache).

* Unlike persistent_term, Ane's read operation with cache miss/expire would require copy data from ETS table to the heap of current process.

* Unlike persistent_term, Ane's write operation is fast and won't trigger global GC.

## Installation

**Note**: it requires OTP 21.2 for `:atomics`, which was released on Dec 12, 2018.

It can be installed by adding `:ane` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ane, "~> 0.1.1"}
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

## Benchmarking

Benchmarking script is available at `bench/comparison.exs`.

Following is the benchmarking result for comparing Ane and ETS standalone with 90% read operations and 10% write operations:

```
$ mix run bench/comparison.exs
Operating System: macOS"
CPU Information: Intel(R) Core(TM) i7-3720QM CPU @ 2.60GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.7.4
Erlang 21.2

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 10 s
memory time: 0 μs
parallel: 16
inputs: none specified
Estimated total run time: 24 s


Benchmarking size=16, mode=ane, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100...
Benchmarking size=16, mode=ets, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100...

Name                                                                                                                   ips        average  deviation         median         99th %
size=16, mode=ane, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100         26.76       37.37 ms    ±37.32%       36.79 ms       72.50 ms
size=16, mode=ets, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100          9.66      103.55 ms    ±37.82%       98.66 ms      187.74 ms

Comparison:
size=16, mode=ane, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100         26.76
size=16, mode=ets, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100          9.66 - 2.77x slower
```

Following is the benchamrking result for comparing Ane and ETS standalone for "hot key" issue:

```
$ mix run bench/comparison.exs
Operating System: macOS"
CPU Information: Intel(R) Core(TM) i7-3720QM CPU @ 2.60GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.7.4
Erlang 21.2

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 10 s
memory time: 0 μs
parallel: 16
inputs: none specified
Estimated total run time: 24 s


Benchmarking size=1, mode=ane, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100...
Benchmarking size=1, mode=ets, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100...

Name                                                                                                                  ips        average  deviation         median         99th %
size=1, mode=ane, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100         27.03       37.00 ms    ±45.40%       36.15 ms       71.12 ms
size=1, mode=ets, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100          1.33      754.31 ms    ±25.91%      762.88 ms     1212.87 ms

Comparison:
size=1, mode=ane, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100         27.03
size=1, mode=ets, Ane.get=90%, Ane.put=10.0%,  read_concurrency=true, write_concurrency=true, info_size=100          1.33 - 20.39x slower
```

## Handling Garbabge Data in Underneath ETS table

Write operation (`Ane.put`) includes one `:ets.insert` operation and one `:ets.delete` operation.
When the process running `Ane.put` is interrupted (e.g. by `:erlang.exit(pid, :kill)`), garbage
data could be generated if it finished insert operation but did not start delete operation. These
garbabge data could be removed by calling `Ane.clear` (periodically if it needs to handle constantly interruptions).

## Development Note

```sh
# type check with dialyzer
mix dialyzer

# type check with ex_type
mix type
```

## License

MIT
