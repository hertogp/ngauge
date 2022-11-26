defmodule Ngauge do
  @moduledoc """
  Parses the cli options, runs the command(s)

  Options include:
  -c --csv      boolean flag that says to produce csv output to a workers log file
  -m --max N    sets the concurrency level for each test to run
  -i --input F  read JSON encoded job definitions from file F
  -j --job X    name a job to run (requires -i as well)
  -r --run Y    run the tests for Y seconds
  -t --test T   specifies which test to run (repeatable)
  -v --verbose  verbose level (repeatable, -vvvv being the max)

  Commandline options override a job's definition where possible.

  A job definition file is simply:
  { jobname: [
    max: 10,
    run: 15,
    csv: true,
    tests: [ssl, http, ping, certs],
    destinations: [
     127.0.0.0/24,
     some.host.name,
     192.168.1.0/25
     ]
    ],

  }

  """
end
