defmodule Ngauge.CLI do
  alias Ngauge.{Options, Runner, Worker}

  # CLI Options
  @options [
    csv: :boolean,
    max: :integer,
    input: :string,
    job: :string,
    worker: :keep,
    timeout: :integer
  ]

  @aliases [
    c: :csv,
    m: :max,
    i: :input,
    j: :job,
    w: :worker,
    t: :timeout
  ]

  def main(argv) do
    Application.put_env(:elixir, :ansi_enabled, true)

    # silence SUPERVISOR / CRASH reports for workers that crash or are killed
    # - whenever that happens, the job is listed as :exit with its reason
    :logger.add_handler_filter(:default, Ngauge.Worker, {fn _, _ -> :stop end, :nostate})

    # TODO: raise on having invalid arguments
    {opts, args, _invalid} = OptionParser.parse(argv, strict: @options, aliases: @aliases)

    opts = %{
      :workers => Keyword.get_values(opts, :worker) |> to_modules([]),
      :max => Keyword.get(opts, :max, 20),
      :csv => Keyword.get(opts, false),
      :timeout => Keyword.get(opts, :timeout, 10_000),
      :interval => Keyword.get(opts, :interval, 100)
    }

    Options.set_state(opts)
    Runner.run(args)
  end

  defp to_modules([], acc),
    do: acc

  defp to_modules([head | tail], acc) do
    mod = Module.concat(Ngauge.Worker, String.capitalize(head))

    case Worker.worker?(mod) do
      true -> to_modules(tail, [mod | acc])
      _ -> to_modules(tail, acc)
    end
  end
end
