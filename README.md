# Ngauge

## WIP

`ngauge` is a cli tool to run various types of connectivity tests to
remote hosts concurrently.

The idea is to have `X` types of tests, each running `Y` instances concurrently
to test `Z` destinations.  A destination can be either a hostname, an IP
address or an IP prefix.  The latter will be expanded to a range of individual
IP addresses.

## Usage

```
$ ngauge command [options] [arguments]
```
where options and arguments, depend on the command given as explained below.

### `ngauge init`

Initializes the current working directory by creating some
files and subdirectories:
- jobs.toml a file which holds predefined jobs to run
- hosts.csv a file which holds name/ip mappings to override DNS
- log       a directory where the log results go

This command has no options or targets.


### `ngauge job <jobname>`

Runs a predefined test as defined in jobs.toml and specified by `<jobname>`.

```
$ ngauge job my_test
```

### `ngauge show [<jobname>]`

Without an argument, this shows all available jobs to run.
With an `<jobname>`, shows the job definition corresponding to `<jobname>`.

### `ngauge diff <jobname> [-n <num>]`

Shows the difference (if any) between the last `<num>` run results of given
`<jobname>`.  If no num is given, shows the difference between the last two
runs.

### `ngauge test -t <test> [-t <test2>, ... ] `<argument(s)>`

Runs some test(s) against some targets given by `<argument(s)>`
This jobname will always be `anon` in the log files.  Beware
that diff'ing them is usually not really meaningful since they
are not always the same tests.

### `ngauge list tests`

Lists the tests currently available.

## Installation

Add `ngauge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ngauge, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with
[ExDoc](https://github.com/elixir-lang/ex_doc) and published on
[HexDocs](https://hexdocs.pm). Once published, the docs can be found at
<https://hexdocs.pm/ngauge>.

