defmodule Ngauge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Ngauge.TaskSupervisor},
      Ngauge.Options,
      Ngauge.Progress,
      {Registry, keys: :unique, name: Ngauge.QueRegistry},
      {Registry, keys: :unique, name: Ngauge.CsvRegistry},
      {DynamicSupervisor, name: Ngauge.QueSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Ngauge.CsvSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ngauge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
