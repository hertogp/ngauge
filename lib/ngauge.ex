defmodule Ngauge do
  # select TODO's and do :sort! to have completed tasks first.
  @moduledoc """


  # Supervision tree

                 -----------------Supervisor--------------------------
                /         |           |               \               \
             Options  Progress  TaskSupervisor  QueueSupervisor  Terminator
                                /      \         /        \
                           Task1 ..... TaskN  Queue1 ... QueueN


    or do

                ------------------Supervisor-----
               /       /              |          \
           Options  Progress  WorkSupervisor  Terminator
                             /          \
              -- Worker1Supervisor     Worker2Supervisor
             /        \                   |           \
     Worker1Queue  Worker1Supervisor   Worker2Queue  Worker2Supervisor
                     /         \                      /     \
                  Task1       Task2                 Task1  Task2


  # TODO:
  [x] workers are able to enqueue more tests for themselves
  [x] progress just dumps an iolist to the screen
  [ ] enqueue'ing args for a worker, starts a worker queue if missing
      so that workers can also add hosts to be tested by another worker
      that was not initially requested on the cli. Use Process.whereis/1
      to see if the queue is running, or 
  [ ] add ability to log worker results to their specific csv files
  [ ] each worker supports:
      [x] `run/1` to test a single destination
      [x] `to_string/1` to format their result as a string
      [ ] `to_csv/2` to format their result as a timestamped datapoint
           options :headers that says to include them or not (default false)
      [ ] `csv_version/1` so that when a worker changes its csv fields, it
          should yield another version and log to file: logs/<worker>-<version>.csv
  [ ] workers are dynamically loaded when tests are enqueued for them
  [ ] workers are able to enqueue more tests for other workers
  [ ] take width/height hints from the CLI
  [ ] chain pulls the cert chain off of a host or IP address
  [ ] chain submits additional hostnames based on SAN names for itself
  [ ] chain submits additional A/AAAA checks based on SAN names
  [ ] cert checks validity of cert chain and days remaining
  [ ] ping actually pings (icmp)
  [ ] webping retrieves http(s) header and time last modified

  """
end
