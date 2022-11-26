defmodule Ngauge.Runner do
  alias Ngauge.{Job, Options, Queue, Progress}

  @doc """

  Asynchronously process a list of arguments using max N processes per worker.

  Usage:
    Runner.run([arg])
  """

  def run(args) do
    workers = Options.get(:workers)
    max = Options.get(:max)

    # TODO: start new queue's under a supervisor?
    Enum.map(workers, &Queue.new/1)
    Enum.map(workers, &Queue.enq(&1, args, clear: true))

    jobs =
      workers
      |> Enum.map(fn w -> {w, Queue.deq(w, max)} end)
      |> Enum.reduce([], fn {w, args}, acc -> [to_jobs(w, args) | acc] end)
      |> List.flatten()

    # clear previous progress stats
    Progress.update(jobs, clear: true)
    interval = Options.get(:interval) || 100

    do_run(jobs, interval, max)
  end

  defp to_jobs(worker, args),
    do: to_jobs(worker, args, [])

  defp to_jobs(_worker, [], acc),
    do: acc

  defp to_jobs(worker, [arg | tail], acc),
    do: to_jobs(worker, tail, [Job.new(worker, :run, arg) | acc])

  # not using do_run([],_,_) to appease Dialyzer, but why?
  @spec do_run([Job.t()], non_neg_integer, map) :: :ok
  defp do_run(jobs, interval, max) when length(jobs) == 0 do
    Process.sleep(1_000)
    workers = Options.get(:workers)

    jobs =
      workers
      |> Enum.map(fn w -> {w, Queue.deq(w, max)} end)
      |> Enum.reduce([], fn {w, args}, acc -> [to_jobs(w, args) | acc] end)
      |> List.flatten()

    if Enum.count(jobs) > 0,
      do: do_run(jobs, interval, max),
      else: :ok
  end

  defp do_run(jobs, interval, max) do
    workers = Options.get(:workers)

    {done, jobs} =
      jobs
      |> Enum.map(&Job.yield/1)
      |> Enum.split_with(&Job.done?/1)

    active = Enum.frequencies_by(jobs, & &1.mod)

    more =
      workers
      |> Enum.map(fn w -> {w, Queue.deq(w, Map.get(active, w, 0))} end)
      |> Enum.reduce([], fn {w, args}, acc -> [to_jobs(w, args) | acc] end)
      |> List.flatten()

    jobs = jobs ++ more
    Progress.update(jobs ++ done)

    Process.sleep(interval)
    do_run(jobs, interval, max)
  end
end
