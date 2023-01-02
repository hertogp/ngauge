# usage: Ngauge.CLI.main(cli_args<x>)
cli_args1 = ["1.1.1.0/28", "-w", "chain"]

cli_args2 = [
  "1.1.1.0/25",
  "-w",
  "chain",
  "-w",
  "ping",
  "-w",
  "pong",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5"
]

r1 = fn -> Ngauge.CLI.main(cli_args1) end
r2 = fn -> Ngauge.CLI.main(cli_args2) end
