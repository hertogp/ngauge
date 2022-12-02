defmodule Ngauge.Csv do
  use GenServer

  alias Ngauge.{Worker, CsvRegistry, CsvSupervisor}

  # Notes
  # Caller code needs to start Csv writes as follows:
  # -  DynamicSupervisor.start_child(Ngauge.CsvSupervisor, {Ngauge.Csv, Ngauge.Worker.Ping})

  # Client API

  @spec start(atom) :: :ignore | {:error, any} | {:ok, pid, any}
  def start(worker) do
    # starting through DynamicSupervisor & CsvSupervisor will call:
    # - __MODULE__.child_spec
    # - __MODULE__.start_link
    # - __MODULE__.init
    IO.puts("#{__MODULE__}.start(#{inspect(worker)}) was called by pid #{inspect(self())}")

    case GenServer.whereis(via(worker)) do
      nil -> DynamicSupervisor.start_child(CsvSupervisor, {__MODULE__, worker})
      pid -> {:ok, {:already_started, pid}}
    end
  end

  def stop(worker) do
    IO.puts("#{__MODULE__}.stop(#{inspect(worker)} was called, pid #{inspect(self())}")
    # alternative (which only calls terminate/1 when we're trapping exists):
    # pid = GenServer.whereis(via(worker))
    # DynamicSupervisor.terminate_child(CsvSupervisor, pid)
    case GenServer.whereis(via(worker)) do
      nil -> {:error, {:noproc, worker}}
      pid -> GenServer.stop(pid)
    end
  end

  @spec start_link(atom) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(worker) do
    IO.puts("#{__MODULE__}.start_link(#{worker}) was called")

    if Worker.worker?(worker) do
      nicname = Worker.name(worker)
      fpath = Path.expand("./logs/#{nicname}.csv")
      dpath = Path.dirname(fpath)
      :ok = File.mkdir_p(dpath)
      {:ok, fp} = File.open(fpath, [:append])
      # fp is an io_device which is the pid of the process handling the file
      # `-> it is linked to us and when we exit, fp-process will close the file
      # see https://www.erlang.org/doc/man/file.html#open-2
      # -> :delayed_write seems to have no effect

      GenServer.start_link(__MODULE__, {nicname, fpath, fp}, name: via(worker))
    else
      {:error, {:noworker, worker}}
    end
  end

  def via(worker),
    do: {:via, Registry, {CsvRegistry, name: worker}}

  @doc """
  This function will be called by the supervisor to retrieve the specification 
  of the child process.The child process is configured to restart only if it 
  terminates abnormally.
  """
  def child_spec(name) do
    IO.puts("#{__MODULE__}.child_spec(#{name}) called with #{name}")

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [name]},
      restart: :transient
    }
  end

  def write(worker, str) do
    GenServer.cast(via(worker), {:write, str})
  end

  # Server (callbacks)

  @impl true
  def init({_nicname, _path, _fp} = state) do
    # trapping exits => GenServer's handle_info will call our terminate
    IO.puts("#{__MODULE__}.init(#{inspect(state)}) was called")
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl true
  def terminate(reason, {nicname, fpath, fp}) do
    # cleanup: maybe add empty line and close fp
    IO.puts("terminate #{nicname}, reason #{inspect(reason)}, closing -> #{fpath}")
    File.close(fp)
    :ok
  end

  @impl true
  def handle_cast({:write, str}, {nicname, path, fp} = state) do
    IO.puts("writing #{str} to #{path} for #{nicname}")
    # {"ok, fd} = File.open(path, [:raw, :append, {:delayed_write, 64_000, 10_000}])
    # :file.write(fd, "some binary << 64 KB")
    # `-> data is written every 64KB or every 10sec
    IO.write(fp, str)
    {:noreply, state}
  end
end
