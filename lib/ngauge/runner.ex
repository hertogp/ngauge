defmodule Ngauge.Runner do
  alias Ngauge.{Csv, Job, Options, Queue, Progress}

  @doc """
  Asynchronously process arguments using max N processes per worker type.

  Usage:
    Runner.run([arg])
  """

  def run(args) do
    # the initial set of workers to run, specified on the cli
    # note: workers may enqueue arguments for other workers, so
    # do_run/3 needs to check all active queues.
    workers = Options.get(:workers) |> Enum.uniq()
    max = Options.get(:max)

    # clear all active queues first, mainly for when main/1 is run
    # repeatedly inside iex (Queue's remain alive in that case and the stats
    # get skewed.
    Queue.active() |> Enum.map(&Queue.clear/1)

    Enum.map(workers, &Queue.enq(&1, args))

    jobs =
      workers
      |> Enum.map(fn w -> {w, Queue.deq(w, max)} end)
      |> Enum.reduce([], fn {w, args}, acc -> [to_jobs(w, args) | acc] end)
      |> List.flatten()

    # clear previous progress stats
    # Progress.clear_screen()
    Progress.update(jobs, clear: true)
    interval = Options.get(:interval) || 100

    do_run(jobs, interval, max)
  end

  # Helpers

  # not using do_run([],_,_) to appease Dialyzer, but why?
  @spec do_run([Job.t()], non_neg_integer, map) :: :ok
  defp do_run(jobs, _interval, _max) when length(jobs) == 0 do
    # stop the csv-writers and close their open file handles
    Csv.active()
    |> Enum.map(&Csv.stop/1)

    Progress.update(jobs, [])
    :ok
  end

  defp do_run(jobs, interval, max) do
    # workers = Options.get(:workers)
    {done, jobs} =
      jobs
      |> Enum.map(&Job.yield/1)
      |> Enum.split_with(&Job.done?/1)

    # count the number of jobs running by their module name
    # so we can get more (max - count) jobs up until max jobs
    active = Enum.frequencies_by(jobs, & &1.mod)

    more =
      Queue.active()
      |> Enum.map(fn w -> {w, Queue.deq(w, max - Map.get(active, w, 0))} end)
      |> Enum.reduce([], fn {w, args}, acc -> [to_jobs(w, args) | acc] end)
      |> List.flatten()

    jobs = jobs ++ more
    Progress.update(jobs ++ done)

    if Options.get(:csv),
      do: Enum.map(done, &Csv.write/1)

    Process.sleep(interval)
    do_run(jobs, interval, max)
  end

  defp to_jobs(worker, args),
    do: to_jobs(worker, args, [])

  defp to_jobs(_worker, [], acc),
    do: acc

  defp to_jobs(worker, [arg | tail], acc),
    do: to_jobs(worker, tail, [Job.new(worker, :run, arg) | acc])
end
