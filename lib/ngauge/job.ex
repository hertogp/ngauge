defmodule Ngauge.Job do
  @moduledoc ~S"""
  A `Job` is a struct with the following fields:

  :mod      module
  :fun      function
  :arg      any binary
  :task     a Task when job was started
  :status   show whether the job did `:ok`, `:exit` or had a `:timeout`
  :result   shows the jobs result when `:ok`, reason for `:exit` or nil when `:timeout` 
  :started  starteding time (a point in monotonic_time)
  :stopped  stoppedping time (by worker or runner, also monotonic_time)

  The `:mod, :fun` are required arguments and denote which function will handle
  this particular job.

  """

  alias Ngauge.{Worker, Options}

  @enforce_keys [:mod, :fun]
  defstruct [:mod, :fun, :name, :arg, :task, :status, :result, :started, :stopped]

  @type t() :: %__MODULE__{
          mod: atom,
          fun: atom,
          name: binary,
          arg: binary,
          task: Task.t() | nil,
          status: :done | :timeout | :exit | :run,
          result: any,
          started: integer,
          stopped: integer
        }

  defguard is_job(job) when is_struct(job, __MODULE__)

  @spec new(atom, atom, any) :: t()
  def new(mod, fun, arg) when is_atom(mod) and is_atom(fun) do
    task =
      Ngauge.TaskSupervisor
      |> Task.Supervisor.async_nolink(mod, fun, [arg])

    %__MODULE__{
      mod: mod,
      fun: fun,
      name: Worker.name(mod),
      arg: arg,
      task: task,
      status: :run,
      result: nil,
      started: timestamp(),
      stopped: 0
    }
  end

  @spec yield(t()) :: t()
  def yield(%__MODULE__{status: :run} = job) do
    case Task.yield(job.task, 1) do
      nil -> maybe_expire(job)
      {:exit, reason} -> %{job | status: :exit, result: reason, stopped: timestamp()}
      {:ok, result} -> %{job | status: :done, result: result, stopped: timestamp()}
    end
  end

  def yield(job),
    do: job

  defp maybe_expire(job) do
    case expired?(job) do
      false ->
        job

      true ->
        Task.shutdown(job.task, :brutal_kill)
        # TODO: maybe catch retun value of shutdown and use it?
        %{job | status: :timeout, stopped: timestamp()}
    end
  end

  @spec done?(t()) :: boolean
  def done?(%__MODULE__{status: :run} = job) when is_job(job),
    do: false

  def done?(_),
    do: true

  @doc """
  Returns a job's current age if still running or how long it lived otherwise.

  """
  @spec age(t()) :: pos_integer()
  def age(job) when is_job(job) do
    # current age is still running, period lived otherwhise
    case job.status do
      :run -> timestamp() - job.started
      _ -> job.stopped - job.started
    end
  end

  def alive?(job) do
    Process.alive?(job.task.pid)
  end

  @doc """
  Returns true if a job's `age/1` exceeds Options' `:timeout`, false otherwise.

  """
  @spec expired?(t()) :: boolean
  def expired?(job),
    do: age(job) > (Options.get(:timeout) || 5_000)

  @spec to_string(t()) :: binary
  def to_string(job) do
    result =
      case function_exported?(job.mod, :format, 1) do
        true -> apply(job.mod, :format, [job.result])
        _ -> "#{inspect(job.result)}"
      end

    # worker = Module.split(job.mod) |> List.last()
    "#{job.name}(#{job.arg}) #{job.status} #{age(job)}ms #{result}"
  end

  defp timestamp,
    do: System.monotonic_time(:millisecond)
end
