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
  defstruct [:batch, :mod, :fun, :name, :arg, :task, :status, :result, :started, :stopped]

  @type t() :: %__MODULE__{
          batch: binary,
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

  @doc """
  Starts a new async task (not linked) and wraps it inside a `t:Job.t()` struct.

  """
  @spec new(atom, atom, any) :: t()
  def new(mod, fun, arg) when is_atom(mod) and is_atom(fun) do
    task =
      Ngauge.TaskSupervisor
      |> Task.Supervisor.async_nolink(mod, fun, [arg])

    %__MODULE__{
      batch: Options.get(:batch),
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

  @doc """
  Check a `job` for results, returning a possibly updated Job struct.

  After a yield, the `job`'s status may be one of:
  - `:run`, the job is still running and has not yet expired
  - `:done`, the job completed normally and has some valid `result`
  - `:exit`, the job crashed, `result` may indicate the reason
  - `:timeout`, the job expired and `result` will be nil

  """
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
        # TODO: maybe catch return value of shutdown and use it?
        %{job | status: :timeout, stopped: timestamp()}
    end
  end

  @doc """
  Returns true if the `job` is no longer running, false otherwise.

  """
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
    # current age is still running, period lived otherwise
    case job.status do
      :run -> timestamp() - job.started
      _ -> job.stopped - job.started
    end
  end

  @doc """
  Returns true if the `job`'s task is still alive and running.

  This differs from `done?/1` which only checks the `job`'s `status`,
  while this function actually checks the task's pid.

  """
  @spec alive?(t()) :: boolean
  def alive?(job),
    do: Process.alive?(job.task.pid)

  @doc """
  Returns true if a job's `age/1` exceeds Options' `:timeout`, false otherwise.

  """
  @spec expired?(t()) :: boolean
  def expired?(job),
    do: age(job) > (Options.get(:timeout) || 5_000)

  @doc """
  Returns a string representation of given `job`.

  Mainly useful for `Ngauge.Progress`.

    Uses job/worker module's `:to_str/1` if available for the job's result part
    of the string.

  """
  @spec to_str(t()) :: binary
  def to_str(job) do
    # result formatting differs per job status.
    result = to_str(job.status, job)
    status = String.pad_trailing("#{job.status}", 7)
    "#{status} > #{job.name}(#{job.arg}) #{age(job)}ms #{result}"
  end

  defp to_str(:done, job) do
    case function_exported?(job.mod, :to_str, 1) do
      true -> apply(job.mod, :to_str, [job.result])
      _ -> "missing to_str #{inspect(job.result)}"
    end
  end

  defp to_str(:exit, job) do
    # Notes:
    # - result is always a tuple
    # - 0th element may be an exception, or
    # - 0th element may be an atom in which case it is followed by a list of tuples
    case elem(job.result, 0) do
      x when is_exception(x) ->
        Exception.message(x)

      x when is_atom(x) ->
        # only get the first bits of the error information
        result =
          job.result
          |> elem(1)
          |> List.first()
          |> Tuple.to_list()
          |> List.flatten()

        "#{x} - #{inspect(result)}"

      _ ->
        "#{inspect(job.result)}"
    end
  end

  defp to_str(_, _),
    do: ""

  @doc """
  Returns a list of csv-lines representing given `job`'s results.

  Each line always starts with: `batch,name,argument,status,age`.
  When the `job` status is `:done`, the underlying worker yields
  the csv-representation of the `job.result`, which is appended.

  If the job crashed or timedout, a single file "n/a" is appended.

  """
  @spec to_csv(t()) :: [[binary]]
  def to_csv(job) do
    start =
      ["#{job.batch}", "#{job.name}", "#{job.arg}", "#{job.status}", "#{age(job)}"]
      |> Enum.intersperse(",")

    lines =
      case job.status do
        :done -> apply(job.mod, :to_csv, [job.result])
        _ -> [["n/a"]]
      end

    Enum.map(lines, fn line -> [start, ",", Enum.intersperse(line, ","), "\n"] end)
  end

  @doc """
  Returns the csv-headers for given `job`'s worker implementation.

  """
  @spec csv_headers(module) :: [binary]
  def csv_headers(module) do
    prefix = ~w(batch name argument status duration)
    fields = apply(module, :csv_headers, [])

    (prefix ++ fields)
    |> Enum.intersperse(",")
  end

  def timestamp,
    do: System.monotonic_time(:millisecond)
end
