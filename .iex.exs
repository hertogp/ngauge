alias Ngauge.Runner
alias Ngauge.Targets

targets = [
  "hostname1.tld",
  "1.1.1.0/30",
  "hostname2.tld",
  "2.2.2.0/28",
  "hostname3.tld",
  "3.3.3.0/30"
]

# usage: Ngauge.main(cli_args)
cli_args = ["1.1.1.0/30", "-w", "chain"]
