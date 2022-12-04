defmodule Ngauge.Queue do
  @moduledoc """
  A simple job queue from which N-jobs can be taken.

  The queue is initialized to an empty queue and arguments can be
  passed into the queue using `enq/2` and jobs are handed out
  via `deq/1`.

  """

  use Agent

  alias Ngauge.{Job, Queue, QueueSupervisor, Worker}
  alias Pfx

  # args is the list of arguments to be mined given a certain demand
  # dq/eq is the number of enqueued/dequeued arguments
  # q is overflow queue 
  @state %{
    args: [],
    dq: 0,
    eq: 0,
    q: []
  }

  def new(module) do
    # TODO: register new worker queues so enq/2,3 can check if a queue
    # is already up or needs to be started.  Reason is that workers may
    # find new targets they would like to enqueue, either for themselves
    # of another worker they know of.
    DynamicSupervisor.start_child(QueueSupervisor, {Queue, module})
  end

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(name) do
    if Worker.worker?(name),
      do: Agent.start_link(fn -> @state end, name: name),
      else: {:error, {:noworker, name}}
  end

  @doc """
  Get upto `demand` arguments from given queue (worker) `name`.

  """
  @spec deq(atom, integer) :: [Job.t()]
  def deq(name, demand) do
    Agent.get_and_update(name, fn state -> do_deq(state, demand) end)
  end

  @doc """
  Put arguments in the queue of given (worker) name.

  """
  @spec enq(atom, [binary]) :: :ok
  def enq(name, args) do
    unless Process.whereis(name) do
      child_spec = %{id: name, start: {Queue, :start_link, [name]}}
      {:ok, _pid} = DynamicSupervisor.start_child(QueueSupervisor, child_spec)
    end

    Agent.update(name, fn state -> do_enq(state, args) end)
  end

  @doc """
  Clear a named queue.

  Used by `Ngauge.CLI.main/1`, so repeated calls from within iex sessions
  does not skew the statistics.

  """
  @spec clear(atom) :: :ok
  def clear(name) do
    Agent.update(name, fn _state -> @state end)
  end

  # Helpers

  @doc """
  Returns a list of running Queues

  Used by Runner to get more enqueued arguments
  """
  @spec active() :: [atom]
  def active() do
    # DynamicSupervisor.which_children(QueueSupervisor)
    # |> Enum.map(&elem(&1, 1))
    # |> Enum.map(&Process.info(&1, :registered_name))
    # |> Enum.map(&elem(&1, 1))
    DynamicSupervisor.which_children(QueueSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> Process.info(pid, :registered_name) |> elem(1) end)
  end

  @spec do_enq(map, [binary]) :: map
  defp do_enq(state, args) do
    {size, args} = pfx_to_iters(args, 0, [])

    state
    |> Map.put(:eq, state.eq + size)
    |> Map.put(:args, state.args ++ args)
  end

  @spec do_deq(map, non_neg_integer) :: {[binary], map}
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

  @spec state(atom | pid | {atom, any} | {:via, atom, any}) :: any
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
end
