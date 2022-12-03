defmodule Ngauge.Csv do
  use GenServer

  alias Ngauge.{Worker, CsvRegistry, CsvSupervisor, Job}

  # notes:
  # - caller code needs to start Csv writes as follows:
  ## DynamicSupervisor.start_child(Ngauge.CsvSupervisor, {Ngauge.Csv, Ngauge.Worker.Ping})

  # Client API

  @spec start(atom) :: :ignore | {:error, any} | {:ok, pid, any}
  def start(worker) do
    # starting through DynamicSupervisor & CsvSupervisor will trigger calls:
    # -> child_spec, start_link and init
    IO.puts("#{__MODULE__}.start(#{inspect(worker)}) was called by pid #{inspect(self())}")

    case GenServer.whereis(via(worker)) do
      nil -> DynamicSupervisor.start_child(CsvSupervisor, {__MODULE__, worker})
      pid -> {:ok, {:already_started, pid}}
    end
  end

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

  @spec write(Job.t()) :: :ok
  def write(job) do
    unless GenServer.whereis(via(job.mod)),
      do: start(job.mod)

    GenServer.cast(via(job.mod), {:write, job})
  end

  @spec start_link(module) :: :ignore | {:error, module} | {:ok, pid}
  def start_link(worker) do
    if Worker.worker?(worker) do
      nicname = Worker.name(worker)
      fpath = Path.expand("./logs/#{nicname}.csv")
      dpath = Path.dirname(fpath)
      :ok = File.mkdir_p(dpath)
      {:ok, fp} = File.open(fpath, [:append, :delayed_write])
      GenServer.start_link(__MODULE__, {fpath, fp}, name: via(worker))
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
  def child_spec(name) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [name]},
      restart: :transient
    }
  end

  # GenServer callbacks

  @impl true
  @spec init(any) :: {:ok, any}
  def init(state) do
    # trapping exits => GenServer's handle_info will call our terminate
    IO.puts("#{__MODULE__}.init(#{inspect(state)}) was called")
    Process.flag(:trap_exit, true)
    {:ok, state}
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
    lines =
      Job.to_csv(job)
      |> Enum.intersperse("\n")

    IO.write(fp, [lines, "\n"])
    {:noreply, state}
  end
end
