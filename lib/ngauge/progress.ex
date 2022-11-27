defmodule Ngauge.Progress do
  @moduledoc """
  Shows progress of running workers on screen
  """

  use Agent

  alias Ngauge.{Job, Queue, Worker}

  @width min(elem(:io.columns(), 1), 120)
  @home IO.ANSI.home()
  @reset IO.ANSI.reset()
  @clear IO.ANSI.clear()
  @bright IO.ANSI.bright()
  @normal IO.ANSI.normal()
  @green IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @colors %{
    :done => IO.ANSI.green(),
    :exit => IO.ANSI.red(),
    :timeout => IO.ANSI.bright() <> IO.ANSI.yellow(),
    :run => IO.ANSI.normal()
  }
  @bar_failed @reset <> @yellow
  @bar_succes @reset <> @green
  @bar_todos @reset <> IO.ANSI.light_black()
  # see https://en.wikipedia.org/wiki/List_of_Unicode_characters#Box_Drawing
  # or https://jrgraphix.net/r/Unicode/2500-257F
  @bar_on "\u25AE"
  @bar_off "\u25AF"
  @box_tl "\u250C"
  @box_tr "\u2510"
  @box_bl "\u2514"
  @box_br "\u2518"
  @box_ml "\u251C"
  @box_mr "\u2524"
  @box_h "\u2500"
  @box_v "\u2502"
  @box_vl "\u2524"
  @box_vr "\u251C"

  # state %{
  #   stats => %{job.name => {done, timeout, exit, run}},
  #   jobs  => [jobs_that_are_done]
  #   max => max jobs results to display
  #   max_rows => height of terminal
  #   max_cols => width of terminal
  # }
  @state %{
    stats: %{},
    jobs: [],
    width: 100,
    height: 25
  }

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_state) do
    Agent.start_link(fn -> @state end, name: __MODULE__)
  end

  def clear(),
    do: Agent.update(__MODULE__, fn _ -> @state end)

  def clear_screen(),
    do: IO.ANSI.clear() |> IO.write()

  def state(),
    do: Agent.get(__MODULE__, & &1)

  @doc """
  Given a list of jobs that are running or are done, update the worker statistics.

  The should be comprised of the currently running jobs and those that were
  completed during the last yield.

  """
  @spec update([Job.t()], Keyword.t()) :: :ok
  def update(jobs, opts \\ []) do
    Agent.update(__MODULE__, fn state -> update(state, jobs, opts) end)
  end

  defp update(state, jobs, opts) do
    state =
      if Keyword.get(opts, :clear, false),
        do: @state,
        else: state

    # reset the running count first
    stats =
      state.stats
      |> Enum.reduce(%{}, fn {k, {d, t, e, _r}}, acc -> Map.put(acc, k, {d, t, e, 0}) end)

    stats = Enum.reduce(jobs, stats, &update_stats/2)

    max = elem(:io.rows(), 1) - 8

    # TODO: donot keep actual jobs in state, just their string version
    done =
      Enum.filter(jobs, fn job -> job.status != :run end)
      |> Kernel.++(state.jobs)
      |> Enum.take(max)

    state =
      state
      |> Map.put(:stats, stats)
      |> Map.put(:jobs, done)
      |> then(&Map.put(&1, :width, min(@width, elem(:io.columns(), 1))))

    # update the screen
    state |> to_iolist() |> IO.write()
    state
  end

  @spec to_iolist(map) :: iolist()
  defp to_iolist(state) do
    ["\n"]
    |> bottom_line(state)
    |> joblines(state)
    |> separator(state)
    |> bars(state)
    |> top_line(state)
  end

  @spec top_line(any, map) :: nonempty_maybe_improper_list
  defp top_line(acc, state) do
    kids = Task.Supervisor.children(Ngauge.TaskSupervisor) |> Enum.count()
    name = " nGauge "
    kids = String.pad_leading(" #{kids}", 4, [@box_h]) <> " Running "
    pad = state.width - String.length(name) - String.length(kids) - 6

    [
      @clear,
      @home,
      @reset,
      @box_tl,
      @box_h,
      @box_vl,
      @bright,
      @green,
      name,
      @reset,
      @box_vr,
      @box_h,
      kids,
      repeat(@box_h, pad),
      @box_tr,
      "\n" | acc
    ]
  end

  defp bottom_line(acc, state),
    do: [@reset, @box_bl, repeat(@box_h, state.width - 2, []), @box_br | acc]

  defp bars(acc, state) do
    # calculate the longest name in order to align them with padding in bar/4
    # add bars always in same, alphabetical order by reducing a sorted worker list
    workers = Map.keys(state.stats) |> Enum.sort() |> Enum.reverse()
    names = Enum.map(workers, &Worker.name/1)
    len = Enum.reduce(names, 0, &max(String.length(&1), &2))
    Enum.reduce(workers, acc, fn worker, acc -> bar(acc, worker, state, len) end)
  end

  defp bar(acc, worker, state, len) do
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
      @bright,
      @green,
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
      @box_v,
      "\n" | acc
    ]
  end

  defp separator(acc, state) do
    width = Map.get(state, :width, @width)
    [@reset, @box_ml, repeat(@box_h, width - 2), @box_mr, "\n" | acc]
  end

  defp joblines(acc, state) do
    width = Map.get(state, :width, @width)

    Enum.reduce(state.jobs, acc, fn job, acc ->
      [@box_v, " ", jobline(job, width - 4), " ", @box_v, "\n" | acc]
    end)
  end

  defp jobline(job, max) do
    str = Job.to_string(job)
    pad = max - String.length(str)

    str =
      if pad < 0,
        do: String.slice(str, 0..(max - 1)),
        else: [str, repeat(" ", pad)]

    [Map.get(@colors, job.status, @normal), str, @reset]
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

  @spec clear_screen() :: :ok
end
