defmodule Ngauge.Progress do
  @moduledoc """
  Shows progress of running workers on screen

  """

  # [[ TODO: ]]
  # [ ] refactor state so repeat calculations are not necessary
  # [ ] make sure to not overwrite any previous text on the screen
  # [c] turn this into a GenServer
  # [c] in summary, list each worker's tests/second
  # [c] list the ETA as a countdown
  # [c] list the job's name, even if anonymous
  # [x] add deq/enq (X%)
  # [x] in summary, list the time it took to complete the run
  # [x] list each worker's ok: x, crash: y, timeout: z
  # [x] summary: add a totals line

  use GenServer

  alias Ngauge.{Job, Queue, Worker, Options}

  # [[ ATTRIBUTES ]]

  @width min(elem(:io.columns(), 1), 120)
  # @home IO.ANSI.home()
  # @home IO.ANSI.cursor(1, 1)
  @reset IO.ANSI.reset()
  # @clear IO.ANSI.clear()
  @clearline IO.ANSI.clear_line()
  # @bright IO.ANSI.bright()
  @normal IO.ANSI.normal()
  @green IO.ANSI.green()
  @yellow IO.ANSI.color(3, 3, 0)
  @white IO.ANSI.white()
  @colors %{
    :done => IO.ANSI.normal(),
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

  @state %{
    # stats[module] -> {done, timeout, exit, run}
    stats: %{},
    # list of jobs that are not :run'ing
    jobs: [],
    # width for progress bar(s)
    width: 100,
    # start_time must be set by start_link/1 and clear/0
    start_time: nil
  }

  # [[ STARTUP API ]]

  def child_spec(arg) do
    IO.inspect(arg, label: :progress_childspec)
    # called by the supervisor
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [__MODULE__]},
      restart: :permanent,
      shutdown: 20_000
    }
  end

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_state) do
    state = Map.put(@state, :start_time, Job.timestamp())
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(any) :: {:ok, map}
  def init(arg) do
    IO.inspect(arg, label: :progress_init)
    {:ok, Map.put(@state, :start_time, Job.timestamp())}
  end

  # [[ CLIENT API ]]

  def state() do
    # TODO: remove me when peeking is no longer needed
    GenServer.call(__MODULE__, {:state})
  end

  @doc """
  Given a list of jobs that are running or are done, update the worker statistics.

  The list should be comprised of the currently running jobs and those that were
  completed during the last yield.

  An empty job list means there is no more work to be done.

  """
  @spec update([Job.t()], Keyword.t()) :: :ok
  def update(jobs, opts \\ []) do
    # TODO: mayby do
    # - GenServer.cast when we have jobs, and
    # - GenServer.call when we are done?
    # otherwise screen output is borked
    GenServer.call(__MODULE__, {:update, jobs, opts})
  end

  # {{ GENSERVER CALLBACKS ]]

  @impl true
  def handle_call({:state}, _from, state),
    do: {:reply, state, state}

  @impl true
  def handle_call({:update, jobs, opts}, _from, state) do
    state = update(state, jobs, opts)
    {:reply, :ok, state}
  end

  # [[ HELPERS ]]

  defp name(worker) do
    # simplified name for worker (i.e. the label of its module name)
    worker
    |> Worker.name()
    |> String.downcase()
  end

  def runtime(seconds) do
    # keeping it simple: <x>h <y> m <z>s
    hrs = div(seconds, 3600)
    min = div(seconds - hrs * 3600, 60)
    sec = seconds - hrs * 3600 - min * 60

    cond do
      hrs > 0 -> "#{hrs}h #{min}m #{sec}s"
      min > 0 -> "#{min}m #{sec}s"
      true -> "#{sec}s"
    end
  end

  # final result (empty job list)
  defp update(state, [], _opts) do
    c = @clearline

    # get results as columns where stats[k] -> {#done, #timeout, #exit, #run}
    # note: sorted by name
    results =
      Enum.map(state.stats, fn {k, v} ->
        {done, timeout, exit, _run} = v
        total = done + timeout + exit
        perc = perc(done, total)
        [name(k), "#{done}", "#{timeout}", "#{exit}", "#{total}", "#{perc}%"]
      end)
      |> Enum.sort()

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
    split = Enum.map(header, fn str -> String.duplicate(@box_h, String.length(str)) end)
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
    batch = Options.get(:batch)
    took = trunc((Job.timestamp() - state.start_time) / 1000) |> runtime()

    IO.write("#{c}\n#{c}Batch #{batch} took #{took}, summary:\n#{c}\n#{c}")

    results
    |> Enum.map(&Enum.zip(cw, &1))
    |> Enum.map(&Enum.map(&1, fn {w, s} -> String.pad_leading(s, w) end))
    |> Enum.intersperse("\n" <> @clearline)
    |> IO.write()

    # clear some space in case we are run on repeat ...
    IO.write(String.duplicate("\n", 2 + map_size(state.stats)))

    # return out new state to handle_cast.
    state
  end

  # intermediate update based on a list of jobs yielded
  defp update(state, jobs, opts) do
    # if requested, start afresh
    state =
      if Keyword.get(opts, :clear, false) do
        # clear some space.
        IO.write("\n\n\n")
        Map.put(@state, :start_time, Job.timestamp())
      else
        state
      end

    # running count is not cumulative, so reset those
    # stats[worker] -> {done, timeout, exit (crash), running}
    stats =
      state.stats
      |> Enum.reduce(%{}, fn {k, {d, t, e, _r}}, acc -> Map.put(acc, k, {d, t, e, 0}) end)

    # update stats based on list of jobs done/crashed/timedout/running
    stats = Enum.reduce(jobs, stats, &update_stats/2)

    # jobs that are no longer running, will have their results printed
    done = Enum.filter(jobs, fn job -> job.status != :run end)

    state =
      state
      |> Map.put(:stats, stats)
      |> Map.put(:jobs, done)
      |> then(&Map.put(&1, :width, min(@width, elem(:io.columns(), 1))))

    # update the screen
    state
    |> to_iolist()
    |> IO.write()

    # print job results only once
    %{state | jobs: []}
  end

  @spec to_iolist(map) :: iolist()
  defp to_iolist(state) do
    # progress bar at bottom, output above
    {:ok, last_row} = :io.rows()
    num_workers = map_size(state.stats)
    start = [IO.ANSI.cursor(-3 + last_row - num_workers, 1)]

    # since each line of output is *prepended*, go in reverse order
    # ensure the cursor ends up just above the status bars, on an *empty* line
    start
    |> bottom_line(state)
    |> bars(state)
    |> top_line(state)
    |> joblines(state)
    |> Enum.intersperse("\n")
    |> List.insert_at(0, start)
  end

  @spec perc(integer, integer) :: integer
  defp perc(x, y) do
    trunc(100 * x / y)
  end

  @spec top_line(list, map) :: nonempty_maybe_improper_list
  defp top_line(acc, state) do
    active = Enum.reduce(state.stats, 0, fn {_, {_, _, _, r}}, count -> count + r end)

    name = " nGauge "
    kids = String.pad_leading(" #{active}", 4, [@box_h]) <> " Active "
    time = trunc((Job.timestamp() - state.start_time) / 1000)
    runtime = " #{runtime(time)} "
    # " Time #{time} [s] "

    {deq, enq} = Queue.progress()
    overall = " #{deq - active}/#{enq} (#{perc(deq - active, enq)}%)"

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
    # calculate the longest name in order to align them with padding in bar/3
    # add bars always in same, alphabetical order by reducing a sorted worker list
    # TODO: also check max number of running jobs so it can be padded too
    workers = Map.keys(state.stats) |> Enum.sort() |> Enum.reverse()
    names = Enum.map(workers, &Worker.name/1)
    len = Enum.reduce(names, 0, &max(String.length(&1), &2))
    Enum.reduce(workers, acc, fn worker, acc -> [bar(worker, state, len) | acc] end)
  end

  defp bar(worker, state, len) do
    {done, timeout, exit, run} = Map.get(state.stats, worker, {0, 0, 0, 0})

    # NOTE: assumes max 9999 running jobs, see todo in bars/2
    name =
      worker
      |> Worker.name()
      |> String.pad_trailing(len, " ")
      |> Kernel.<>(String.pad_leading("#{run}", 4))

    {_dq, eq} = Queue.progress(worker)
    perc = perc(done + timeout + exit, eq)
    perc = " #{perc}% " |> String.pad_leading(6, " ")
    # TODO: remove magic numbers ...
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
    # prepend a single list for each job's result
    Enum.reduce(state.jobs, acc, fn job, acc ->
      [[@clearline, " ", @colors[job.status] || @normal, Job.to_str(job), @reset] | acc]
    end)
  end

  # rather than a string of a repeated char, return a list of the repeated char
  defp repeat(ch, max) when max > 0,
    do: repeat(ch, max - 1, [ch])

  defp repeat(_ch, _max),
    do: []

  defp repeat(_ch, 0, acc),
    do: acc

  defp repeat(ch, n, acc),
    do: repeat(ch, n - 1, [ch | acc])

  # [[ stats helpers ]]

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
