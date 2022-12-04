defmodule Ngauge.Csv do
  use GenServer

  alias Ngauge.{Worker, CsvRegistry, CsvSupervisor, Job}

  # Client API

  @doc """
  Lists the active CSV-writers by name.
  """
  @spec active() :: [atom]
  def active() do
    # - CsvRegistry has unique keys and registers csv-writers by worker module name
    CsvSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> Registry.keys(CsvRegistry, pid) end)
    |> List.flatten()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort()
  end

  @doc """
  Start a CSV-writer process for given worker module

  """
  @spec start(atom) :: :ignore | {:error, any} | {:ok, pid, any}
  def start(worker) do
    # starting through DynamicSupervisor & CsvSupervisor will trigger calls:
    # -> child_spec, start_link and init
    case GenServer.whereis(via(worker)) do
      nil -> DynamicSupervisor.start_child(CsvSupervisor, {__MODULE__, worker})
      pid -> {:ok, {:already_started, pid}}
    end
  end

  @doc """
  Stop a CSV-writer process for given worker module

  """
  @spec stop(module) :: :ok | {:error, {:noproc, module}}
  def stop(worker) do
    # alternative (which only calls terminate/1 when we're trapping exists):
    ## pid = GenServer.whereis(via(worker))
    ## DynamicSupervisor.terminate_child(CsvSupervisor, pid)
    case GenServer.whereis(via(worker)) do
      nil -> {:error, {:noproc, worker}}
      pid -> GenServer.stop(pid)
    end
  end

  @doc """
  Write to csv-file for given `job`.

  """
  @spec write(Job.t()) :: :ok
  def write(job) do
    name = via(job.mod)

    # alternatively use:
    ## Registry.lookup(Ngauge.CsvRegistry, [name: job.mod])
    unless GenServer.whereis(name),
      do: start(job.mod)

    GenServer.cast(name, {:write, job})
  end

  # GenServer callbacks

  @spec start_link(module) :: :ignore | {:error, module} | {:ok, pid}
  def start_link(worker) do
    if Worker.worker?(worker) do
      GenServer.start_link(__MODULE__, worker, name: via(worker))
    else
      {:error, {:noworker, worker}}
    end
  end

  @spec via(module) :: {:via, module, {module, name: module}}
  def via(worker),
    do: {:via, Registry, {CsvRegistry, name: worker}}

  @doc """
  This function will be called by the supervisor to retrieve the specification 
  of the child process.The child process is configured to restart only if it 
  terminates abnormally.
  """
  def child_spec(worker) do
    %{
      id: worker,
      start: {__MODULE__, :start_link, [worker]},
      restart: :transient
    }
  end

  @impl true
  @spec init(module) :: {:ok, nil, {:continue, module}}
  def init(worker) do
    # trapping exits => the {:EXIT, _} message is handled by GenServer's handle_info
    # will call our terminate *iff* we're trapping exits.
    Process.flag(:trap_exit, true)
    {:ok, nil, {:continue, worker}}
  end

  @impl true
  @spec handle_continue(module, nil) :: {:noreply, {binary, File.t()}}
  def handle_continue(worker, nil) do
    name = Worker.name(worker)
    fpath = Path.expand("./logs/#{name}.csv")
    dpath = Path.dirname(fpath)
    :ok = File.mkdir_p(dpath)
    {:ok, fp} = File.open(fpath, [:append, :delayed_write])
    {:ok, fstat} = File.stat(fpath)

    if fstat.size == 0 do
      headers = Job.csv_headers(worker)
      IO.inspect(headers, label: :headers)
      IO.write(fp, [headers, "\n"])
    end

    {:noreply, {fpath, fp}}
  end

  @impl true
  @spec terminate(any, any) :: :ok
  def terminate(_reason, {_fpath, fp}) do
    # cleanup: maybe add empty line and close fp
    File.close(fp)
    :ok
  end

  @impl true
  def handle_cast({:write, job}, {_path, fp} = state) do
    # {"ok, fd} = File.open(path, [:raw, :append, {:delayed_write, 64_000, 10_000}])
    # :file.write(fd, "some binary << 64 KB")
    # `-> data is written every 64KB or every 10sec
    IO.write(fp, Job.to_csv(job))
    {:noreply, state}
  end
end
