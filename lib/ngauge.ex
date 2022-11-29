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

  [x] workers are able to enqueue more tests for themselves
  [x] workers are able to enqueue more tests for other workers
  [x] enqueueing starts a new queue if it is nog already running
  [x] workers are dynamically loaded when tests are enqueued for them
  [x] progress just dumps an iolist to the screen
  [x] progress does not keep N jobs but their string representation instead
  [ ] add cli switches:
      [ ] take max window height from cli, default to 20 (total)
      [ ] take max window width from cli, default to 80 (total)
  [ ] add CsvSupervisor so Runner can log worker results to csv files
  [ ] add Terminator that will clear the Queue's and drain the workers & csv writers
  [ ] each run via Ngauge.CLI.main must have a tstamp
  [ ] each worker supports:
      [x] `run/1` to test a single destination
      [x] `to_string/1` to format their result as a string
      [ ] `to_csv/2` to format their result as a timestamped datapoint
           options :headers that says to include them or not (default false)
      [ ] `csv_version/1` so that when a worker changes its csv fields, it
          should yield another version and log to file: logs/<worker>-<version>.csv
  [ ] chain pulls the cert chain off of a host or IP address
  [ ] chain submits additional hostnames based on SAN names for itself
  [ ] chain submits additional A/AAAA checks based on SAN names
  [ ] cert checks validity of cert chain and days remaining
  [ ] ping actually pings (icmp)
  [ ] webping retrieves http(s) header and time last modified

  """
end
