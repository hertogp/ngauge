defmodule Ngauge.Progress do
  @moduledoc """
  Shows progress of running workers on screen

  """

  # [[ TODO: ]]
  # [ ] refactor state so repeat calculations are not necesary
  # [ ] turn this into a GenServer
  # [c] in summary, list each worker's tests/second
  # [c] list the ETA as a countdown
  # [c] list the job's name, even if anonymous
  # [x] add deq/enq (X%)
  # [x] in summary, list the time it took to complete the run
  # [x] list each worker's ok: x, crash: y, timeout: z
  # [x] summary: add a totals line

  use Agent

  alias Ngauge.{Job, Queue, Worker}

  # [[ ATTRIBUTES ]]

  @width min(elem(:io.columns(), 1), 120)
  # @home IO.ANSI.home()
  # @home IO.ANSI.cursor(1, 1)
  @reset IO.ANSI.reset()
  @clear IO.ANSI.clear()
  @clearline IO.ANSI.clear_line()
  # @bright IO.ANSI.bright()
  @normal IO.ANSI.normal()
  @green IO.ANSI.green()
  @yellow IO.ANSI.color(3, 3, 0)
  @white IO.ANSI.white()
  @colors %{
    :done => IO.ANSI.green(),
    :exit => IO.ANSI.red(),
    :timeout => IO.ANSI.bright() <> IO.ANSI.yellow(),
    :run => IO.ANSI.normal()
  }
  @bar_failed @yellow
  @bar_succes @green
  @bar_todos IO.ANSI.light_black()
  # see https://en.wikipedia.org/wiki/List_of_Unicode_characters#Box_Drawing
  # or https://jrgraphix.net/r/Unicode/2500-257F
  @bar_on "\u25AE"
  @bar_off "\u25AF"
  @box_tl "\u250C"
  @box_tr "\u2510"
  @box_bl "\u2514"
  @box_br "\u2518"
  # @box_ml "\u251C"
  # @box_mr "\u2524"
  @box_h "\u2500"
  @box_v "\u2502"
  @box_vl "\u2524"
  @box_vr "\u251C"

  # [[ STATE ]]
  # state %{
  #   stats => %{job.name => {done, timeout, exit, run}},
  #   jobs  => [jobs_that_are_done]
  #   width => width of progress screen
  #   height => height of progress screen
  # }
  @state %{
    stats: %{},
    jobs: [],
    width: 100,
    height: 25
    # start_time is added by start_link/1 and clear/0
  }

  # [[ CALLBACKS ]]

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_state) do
    state =
      Map.put(@state, :start_time, Job.timestamp())
      |> IO.inspect(label: :state)

    Agent.start_link(fn -> state end, name: __MODULE__)
  end

  # [[ API ]]

  def clear() do
    state = Map.put(@state, :start_time, Job.timestamp())
    Agent.update(__MODULE__, fn _ -> state end)
  end

  @spec clear_screen() :: :ok
  def clear_screen() do
    IO.write(@clear)
  end

  def state(),
    do: Agent.get(__MODULE__, & &1)

  @doc """
  Given a list of jobs that are running or are done, update the worker statistics.

  The list should be comprised of the currently running jobs and those that were
  completed during the last yield.

  An empty list signals that all work is finished and the worker statistics are
  printed instead.

  """
  @spec update([Job.t()], Keyword.t()) :: :ok
  def update(jobs, opts \\ []) do
    Agent.update(__MODULE__, fn state -> update(state, jobs, opts) end)
  end

  # [[ HELPERS ]]

  # update progressbar
  defp update(state, [], _opts) do
    c = @clearline

    # Elixir.Ngauge.Worker.Name -> name
    name = fn mod ->
      mod
      |> to_string()
      |> String.split(".")
      |> List.last()
      |> String.downcase()
    end

    # get results as columns where stats[k] -> {#done, #timeout, #exit, #run}
    results =
      Enum.map(state.stats, fn {k, v} ->
        {done, timeout, exit, _run} = v
        total = done + timeout + exit
        perc = trunc(100 * done / total)
        [name.(k), "#{done}", "#{timeout}", "#{exit}", "#{total}", "#{perc}%"]
      end)

    totals =
      Enum.reduce(state.stats, [0, 0, 0, 0], fn {_k, v}, [a, b, c, d] ->
        {done, timeout, exit, _run} = v
        [a + done, b + timeout, c + exit, d + done + timeout + exit]
      end)

    p = perc(List.first(totals), List.last(totals))

    totals =
      totals
      |> Enum.map(&"#{&1}")
      |> List.insert_at(0, "totals")
      |> List.insert_at(-1, "#{p}%")

    header = ["WORKER", "DONE", "TIMEOUT", "EXIT", "TOTAL", "SUCCESS"]
    split = Enum.map(header, fn str -> String.duplicate("-", String.length(str)) end)
    results = [header, split] ++ results ++ [split, totals]

    # get column widths required, adding 2 for spacing
    cw =
      Enum.map(results, fn row ->
        Enum.map(row, fn col -> String.length(col) end)
      end)
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(&Enum.max/1)
      |> Enum.map(&(&1 + 2))

    # Write it all out, assumes cursor is just above the progressbars
    #
    took = trunc((Job.timestamp() - state.start_time) / 1000)

    IO.write("#{c}\n#{c}Took #{took} seconds, summary:\n#{c}\n#{c}")

    results
    |> Enum.map(&Enum.zip(cw, &1))
    |> Enum.map(&Enum.map(&1, fn {w, s} -> String.pad_leading(s, w) end))
    |> Enum.intersperse("\n" <> @clearline)
    |> IO.write()

    IO.write("\n\n")

    state
  end

  defp update(state, jobs, opts) do
    # if requested, start afresh
    state =
      if Keyword.get(opts, :clear, false),
        do: Map.put(@state, :start_time, Job.timestamp()),
        else: state

    # running count is not cumulative, so reset those
    # stats[worker] -> {done, timeout, exit (crash), running}
    stats =
      state.stats
      |> Enum.reduce(%{}, fn {k, {d, t, e, _r}}, acc -> Map.put(acc, k, {d, t, e, 0}) end)

    # update stats based on list of jobs done/crashed/timedout/running
    stats = Enum.reduce(jobs, stats, &update_stats/2)

    done = Enum.filter(jobs, fn job -> job.status != :run end)

    state =
      state
      |> Map.put(:stats, stats)
      |> Map.put(:jobs, done)
      |> then(&Map.put(&1, :width, min(@width, elem(:io.columns(), 1))))

    # update the screen
    state |> to_iolist() |> IO.write()
    # don't keep printing the same stuff
    Map.put(state, :jobs, [])
  end

  @spec to_iolist(map) :: iolist()
  defp to_iolist(state) do
    # progress bar at bottom, output above
    {:ok, last_row} = :io.rows()
    num_workers = Map.keys(state.stats) |> Enum.count()

    [IO.ANSI.cursor(-3 + last_row - num_workers, 1)]
    |> bottom_line(state)
    |> bars(state)
    |> top_line(state)
    |> joblines(state)
    |> Enum.intersperse("\n")
  end

  defp perc(x, y) do
    trunc(100 * x / y)
  end

  @spec top_line(any, map) :: nonempty_maybe_improper_list
  defp top_line(acc, state) do
    # TODO: count the number of jobs with status :run, since asking the
    # TaskSupervisor directly, some jobs may have terminated already which
    # we'll see only on the next update cycle.  This way, the total in the
    # topline sometimes differs from the total running counts for each worker
    # in their bar(s).
    active = Task.Supervisor.children(Ngauge.TaskSupervisor) |> Enum.count()

    name = " nGauge "
    kids = String.pad_leading(" #{active}", 4, [@box_h]) <> " Active "
    time = trunc((Job.timestamp() - state.start_time) / 1000)
    runtime = " Time #{time} [s] "

    {deq, enq} = Queue.progress()
    overall = " #{deq - active}/#{enq} #{perc(deq - active, enq)}% "

    pad =
      state.width - String.length(name) - String.length(kids) - String.length(runtime) -
        String.length(overall) - 10

    [
      [
        @clearline,
        "\n",
        @reset,
        @box_tl,
        @box_h,
        @box_vl,
        # @bright,
        @white,
        name,
        @reset,
        @box_vr,
        @box_h,
        kids,
        repeat(@box_h, 2),
        runtime,
        repeat(@box_h, 2),
        overall,
        repeat(@box_h, pad),
        @box_tr
      ]
      | acc
    ]
  end

  defp bottom_line(acc, state),
    do: [[@reset, @box_bl, repeat(@box_h, state.width - 2, []), @box_br] | acc]

  defp bars(acc, state) do
    # calculate the longest name in order to align them with padding in bar/4
    # add bars always in same, alphabetical order by reducing a sorted worker list
    workers = Map.keys(state.stats) |> Enum.sort() |> Enum.reverse()
    names = Enum.map(workers, &Worker.name/1)
    len = Enum.reduce(names, 0, &max(String.length(&1), &2))
    # Enum.reduce(workers, acc, fn worker, acc -> bar(acc, worker, state, len) end)
    Enum.reduce(workers, acc, fn worker, acc -> [bar(worker, state, len) | acc] end)
  end

  defp bar(worker, state, len) do
    {done, timeout, exit, run} = Map.get(state.stats, worker, {0, 0, 0, 0})

    name =
      worker
      |> Worker.name()
      |> String.pad_trailing(len, " ")
      |> Kernel.<>(String.pad_leading("#{run}", 4))

    {_dq, eq} = Queue.progress(worker)
    perc = (done + timeout + exit) / eq
    perc = " #{(100 * perc) |> trunc()}% " |> String.pad_leading(6, " ")
    width = Map.get(state, :width, @width) - len - 14

    # avoid the one-off trap when calculating failed percentage
    ok = trunc(width * (done / eq))
    fail = trunc(width * ((done + timeout + exit) / eq)) - ok
    off = width - ok - fail

    [
      @box_v,
      " ",
      @normal,
      name,
      @reset,
      " ",
      @bar_failed,
      repeat(@bar_on, fail),
      @bar_succes,
      repeat(@bar_on, ok),
      @bar_todos,
      repeat(@bar_off, off),
      @reset,
      perc,
      @box_v
    ]
  end

  defp joblines(acc, state) do
    Enum.reduce(state.jobs, acc, fn job, acc ->
      [[@clearline, " ", @colors[job.status] || @normal, Job.to_str(job), @reset] | acc]
    end)
  end

  defp repeat(ch, max) when max > 0,
    do: repeat(ch, max - 1, [ch])

  defp repeat(_ch, _max),
    do: []

  defp repeat(_ch, 0, acc),
    do: acc

  defp repeat(ch, n, acc),
    do: repeat(ch, n - 1, [ch | acc])

  defp update_stats(job, stats) do
    {done, timeout, exit, run} = Map.get(stats, job.mod, {0, 0, 0, 0})

    new_stats =
      case(job.status) do
        :done -> {done + 1, timeout, exit, run}
        :timeout -> {done, timeout + 1, exit, run}
        :exit -> {done, timeout, exit + 1, run}
        :run -> {done, timeout, exit, run + 1}
      end

    Map.put(stats, job.mod, new_stats)
  end
end
