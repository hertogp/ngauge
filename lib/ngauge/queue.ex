defmodule Ngauge.Queue do
  @moduledoc """
  A simple job queue from which N-jobs can be taken.

  The queue is initialized to an empty queue and arguments can be
  passed into the queue using `enqueue` and jobs are handed out
  via `dequeue/1`.

  """

  use Agent

  alias Ngauge.{Job, Worker}
  alias Pfx

  @state %{
    args: [],
    dq: 0,
    eq: 0,
    q: []
  }

  def new(module) do
    if Worker.worker?(module),
      do: start_link(module),
      else: {:error, {:noworker, module}}
  end

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(name) do
    # eq = total enqueued, dq = total dequeued
    # args = still to be mined for jobs
    # q = list of jobs that can be handed out
    state = %{q: [], args: [], eq: 0, dq: 0}
    Agent.start_link(fn -> state end, name: name)
  end

  @spec enq(atom, [binary], Keyword.t()) :: :ok
  def enq(name, args, opts \\ []),
    do: Agent.update(name, fn state -> do_enq(state, args, opts) end)

  defp do_enq(state, args, opts) do
    # update and return the new state
    state =
      if Keyword.get(opts, :clear, false),
        do: @state,
        else: state

    {size, args} = pfx_to_iters(args, 0, [])

    state
    |> Map.put(:eq, state.eq + size)
    |> Map.put(:args, state.args ++ args)
  end

  @spec deq(atom, integer) :: [Job.t()]
  def deq(name, demand) do
    Agent.get_and_update(name, fn state -> do_deq(state, demand) end)
  end

  def do_deq(state, demand) do
    {new, args} = take_args(state.args, demand)
    {new, q} = Enum.split(state.q ++ new, demand)

    state =
      state
      |> Map.put(:q, q)
      |> Map.put(:args, args)
      |> Map.put(:dq, state.dq + Enum.count(new))

    {new, state}
  end

  @spec state(atom) :: map
  def state(name) do
    Agent.get(name, & &1)
  end

  @spec progress(atom) :: {integer, integer}
  def progress(name) do
    state = Agent.get(name, & &1)
    {state.dq, state.eq}
  end

  defp pfx_to_iters([], size, acc),
    do: {size, acc}

  defp pfx_to_iters([str | tail], size, acc) do
    case Pfx.parse(str) do
      {:error, _} ->
        pfx_to_iters(tail, size + 1, [str | acc])

      {:ok, pfx} ->
        pfx_to_iters(tail, size + Pfx.size(pfx), [{Pfx.last(pfx), Pfx.size(pfx) - 1} | acc])
    end
  end

  # Given a list of arguments and wanted return wanted elements and remainder
  defp take_args(args, wanted) when wanted < 1,
    do: {[], args}

  defp take_args(args, wanted),
    do: take_args(args, wanted, [])

  defp take_args([], _wanted, acc),
    do: {Enum.reverse(acc), []}

  defp take_args(args, 0, acc),
    do: {Enum.reverse(acc), args}

  defp take_args([h | tail], wanted, acc) do
    case h do
      {pfx, 0} -> take_args(tail, wanted, ["#{pfx}" | acc])
      {pfx, n} -> take_args([{pfx, n - 1} | tail], wanted - 1, ["#{Pfx.sibling(pfx, -n)}" | acc])
      h -> take_args(tail, wanted, [h | acc])
    end
  end

  # @spec to_jobs([binary], atom) :: [Job.t()]
  # defp to_jobs(args, name) do
  #   for arg <- args, do: Job.new(name, :run, arg)
  # end
end
