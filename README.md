# Ngauge

## WIP

`ngauge` is a cli tool to take snapshots of various types of connectivity to
remote hosts by testing them through different scenarios.

The idea is to have `X` types of tests, each running `Y` instances concurrently
to test `Z` destinations.  A destination can be either a hostname, an IP
address or an IP prefix.  The latter will be expanded to a range of individual
IP addresses.


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ngauge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ngauge, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ngauge>.

