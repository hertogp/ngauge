defmodule Ngauge.Queue do
  @moduledoc """
  A simple job queue from which N-jobs can be taken.

  The queue is initialized to an empty queue and arguments can be
  passed into the queue using `enq/2` and jobs are handed out
  via `deq/1`.

  Each worker has its own Queue instance referenced by worker name.

  """

  # [[ TODO: ]]
  # [ ] ignore repeat enqueue'ing of a target during a run
  # [x] add progress/0 which gives the overall counts for deq/enq
  # [x] turn this module into a GenServer

  use GenServer

  alias Ngauge.{Job, QueRegistry, QueSupervisor, Worker}

  # [[ STATE ]]
  # args is the list of arguments to be mined given a certain demand
  # dq/eq is the number of enqueued/dequeued arguments
  # q is overflow queue
  @state %{
    # last part of a worker's module name
    name: "",
    # the list of arguments from which demand is taken
    args: [],
    # count of dequeued arguments
    dq: 0,
    # count of enqueed arguments, prefix size is accounted for
    eq: 0,
    # overflow queue
    q: []
  }

  # [[ STARTUP API ]]

  @spec via(module) :: {:via, module, {module, name: module}}
  defp via(worker),
    do: {:via, Registry, {QueRegistry, name: worker}}

  @doc """
  Returns a child specification that:
  - ensures a child is only restarted if it terminated abnormally
  - allows children 20 sec to clean up (i.e. reset the queue)
  - names this module's `:start_link` to start the process
  - sets the `:id` to the worker module (1 per queue per worker type)
  """
  def child_spec(worker) do
    # called by the supervisor
    %{
      id: worker,
      start: {__MODULE__, :start_link, [worker]},
      restart: :transient,
      shutdown: 20_000
    }
  end

  @doc """
  Start up a new queue for given worker.

  """
  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(worker) do
    # DynamicSupervisor calls start_link/1 (as per child_spec/1),
    # GenServer.start_link/3 will call init/1
    # via(worker) ensures the process is registered in QueRegistry
    if Worker.worker?(worker),
      do: GenServer.start_link(__MODULE__, worker, name: via(worker)),
      else: {:error, {:noworker, worker}}
  end

  @doc """
  Create a new que for a worker by name.

  """
  @impl true
  @spec init(module) :: {:ok, map}
  def init(worker) do
    # GenServer calls init/1
    Process.flag(:trap_exit, true)
    name = Worker.name(worker)
    {:ok, Map.put(@state, :name, name)}
  end

  # [[ CLIENT API ]]

  @doc """
  Start a que for a given worker type `module`.

  """
  @spec start(module) :: DynamicSupervisor.on_start_child()
  def start(worker) do
    case DynamicSupervisor.start_child(QueSupervisor, {__MODULE__, worker}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Stop a queue for given worker type `module`.

  """
  def stop(worker) do
    case GenServer.whereis(via(worker)) do
      nil -> {:error, {:noproc, worker}}
      pid -> GenServer.stop(pid)
    end
  end

  @doc """
  List the active worker queues by module name.

  Used by Runner to check for fresh work to do.
  """
  def active() do
    # TODO: maybe return [{pid, Worker}] instead of just [Worker]
    # - perhaps based on include_pid: true keyword?
    QueSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> Registry.keys(QueRegistry, pid) end)
    |> List.flatten()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort()
  end

  @doc """
  Get up to `demand` arguments from given queue (worker) `name`.

  """
  @spec deq(atom, integer) :: [Job.t()]
  def deq(worker, demand) do
    name = via(worker)

    unless GenServer.whereis(name),
      do: start(worker)

    GenServer.call(name, {:deq, demand})
  end

  @doc """
  Put arguments in the queue of given (worker) name.

  """
  @spec enq(atom, [binary]) :: :ok
  def enq(worker, args) do
    name = via(worker)

    unless GenServer.whereis(name),
      do: start(worker)

    GenServer.cast(name, {:enq, args})
  end

  @doc """
  Clear a named queue.

  Used by `Ngauge.CLI.main/1`, so repeated calls from within iex sessions
  does not skew the statistics.

  """
  @spec clear(atom) :: :ok
  def clear(worker) do
    name = via(worker)

    if GenServer.whereis(name),
      do: GenServer.cast(name, {:clear})

    :ok
  end

  @spec state(atom | pid | {atom, any} | {:via, atom, any}) :: any
  def state(worker) do
    name = via(worker)

    if GenServer.whereis(name),
      do: GenServer.call(name, {:state})
  end

  @doc """
  Return the dequeued/enqueued counts for all workers.

  """
  @spec progress() :: {integer, integer}
  def progress() do
    active()
    |> Enum.map(&progress/1)
    |> Enum.reduce({0, 0}, fn {d, e}, {td, te} -> {td + d, te + e} end)
  end

  @doc """
  Returns the dequeued/enqueued items for a worker

  """
  @spec progress(atom) :: {integer, integer}
  def progress(worker) do
    name = via(worker)

    if GenServer.whereis(name) do
      GenServer.call(name, {:progress})
    else
      {0, 0}
    end
  end

  # [[ GENSERVER CALLBACKS ]]

  @impl true
  def handle_call({:deq, demand}, _from, state) do
    {deq, state} = do_deq(state, demand)
    {:reply, deq, state}
  end

  @impl true
  def handle_call({:state}, _, state),
    do: {:reply, state, state}

  @impl true
  def handle_call({:progress}, _, state),
    do: {:reply, {state.dq, state.eq}, state}

  @impl true
  def handle_cast({:enq, args}, state) do
    {:noreply, do_enq(state, args)}
  end

  @impl true
  def handle_cast({:clear}, state) do
    {:noreply, Map.put(@state, :name, state.name)}
  end

  # [[ QUE HELPERS ]]

  @spec do_enq(map, [binary]) :: map
  defp do_enq(state, args) do
    {size, args} = pfx_to_iters(args, 0, [])

    state
    |> Map.put(:eq, state.eq + size)
    |> Map.put(:args, state.args ++ args)
  end

  @spec do_deq(map, non_neg_integer) :: {[binary], map}
  defp do_deq(state, demand) do
    {new, args} = take_args(state.args, demand)
    {new, q} = Enum.split(state.q ++ new, demand)

    # vvv TODO: delme
    if length(q) > 0 do
      IO.inspect(demand, label: :demand)
      IO.inspect(new, label: :new)
      IO.inspect(q, label: :q)
      IO.inspect(args, label: :args)
      IO.inspect(state.args, label: :state_args)
    end

    # ^^^ TODO: delme

    state =
      state
      |> Map.put(:q, q)
      |> Map.put(:args, args)
      |> Map.put(:dq, state.dq + Enum.count(new))

    {new, state}
  end

  # When an argument is actually a prefix, turn it into an iterator {Pfx, n}
  # return {size, args}, where size accounts for the size of prefixes seen.
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

  # Take upto wanted arguments from the queue and return {found, remainder}
  # Note that `found` may be less than the `wanted` amount (remainder will be [])
  # `found` never exceeds `wanted`.
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
      {pfx, 0} -> take_args(tail, wanted - 1, ["#{pfx}" | acc])
      {pfx, n} -> take_args([{pfx, n - 1} | tail], wanted - 1, ["#{Pfx.sibling(pfx, -n)}" | acc])
      h -> take_args(tail, wanted - 1, [h | acc])
    end
  end
end
