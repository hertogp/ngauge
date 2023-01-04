defmodule Ngauge do
  # select TODO's and do :sort! to have completed tasks first.
  @moduledoc """

  # Supervision tree

      -----------------Supervisor-------------------------------------
     /         |           |               \               \          \
  Options  Progress  TaskSupervisor  QueueSupervisor  CsvSupervisor  Terminator
                     /      \         /        \         /       \
                Task1 ... Task<M>  Queue1 ... Queue<N>  Csv1 ... Csv<N>




  # TODO:

  [ ] add dynamic worker-type-kv stores (one for each worker type), so throws are not needed?
  [ ] add Logger with a file backend for csv?
  [ ] add Terminator that will clear the Queue's and drain the active workers & csv writers
  [ ] allow max workers per type, e.g. by -w worker1:20,worker2:10,worker3:5
  [ ] allow max workers per type, e.g. by workername:20 vs -m 10
  [x] enqueueing starts a new queue if it is not already running
  [x] progress does not keep N jobs but their string representation instead
  [x] progress just dumps an iolist to the screen
  [x] turn Options into a GenServer
  [x] turn Progress into a GenServer
  [x] turn Queue into a GenServer (like Csv)
  [x] workers are able to enqueue more tests for other workers
  [x] workers are able to enqueue more tests for themselves
  [x] workers are dynamically loaded when tests are enqueued for them
  [x] add CsvSupervisor so Runner can log worker results to csv files
      [x] start a writer for a worker
      [x] stop a writer for a worker
      [x] use delayed_write with 64KB buffer and 30s delay
          see https://www.erlang.org/doc/man/file.html#open-2
          - requires raw mode, which needs :file.write/2 (doesn't work?)
  [x] each run via Ngauge.CLI.main must have a tstamp
  [x] each worker supports:
      [x] `run/1` to test a single destination
      [x] `to_string/1` format a job's result as a string
      [x] `to_csv/1` format a job's result as lines of csv field values
      [x] `csv_headers/0` in case a new file is started

  # Ideas/Questions
  - howto specify jobs in yaml or toml
  - some jobs may need more than 1 argument (e.g. cert checks based on IP + SNI ?)
  - specific workers for reconnaissance that create target files?

  # Real workers

  [ ] chain pulls the cert chain off of a host or IP address
  [ ] chain submits additional hostnames based on SAN names for itself
  [ ] chain submits additional A/AAAA checks based on SAN names
  [ ] cert checks validity of cert chain and days remaining
  [ ] crtsh to retrieve all certs issued for some name
      Either use htpps://crt.sh/json?q=domain or connect to their database
  [ ] ping actually pings (icmp)
  [ ] httping retrieves http and/or https header and time last modified

  """

  @doc """
  Just to experiment, delete when done
  """
  @spec delme() :: any
  def delme() do
    if true,
      do: nil,
      else: nil
  end
end
