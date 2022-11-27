defmodule Ngauge.Worker do
  @moduledoc """
  Utility functions for workers
  """

  @spec name(atom) :: binary
  def name(worker) when is_atom(worker) do
    worker
    |> Module.split()
    |> List.last()
    |> String.downcase(:ascii)
  end

  @spec worker?(atom) :: boolean
  def worker?(module) do
    if Code.ensure_loaded?(module) do
      prefix =
        module
        |> Module.split()
        |> Enum.take(2)
        |> Module.concat()

      # notes:
      # - this module has no run/1, so we won't be included
      # - we actually enforce a namespace here, but do we want/need to?
      #    module.__info__(:functions) -> [{:run, 1}, {:format, 1}]
      #    should be enough, no?
      #
      prefix == __MODULE__ and function_exported?(module, :run, 1)
    else
      false
    end
  end

  @spec all_available() :: [atom]
  def all_available() do
    {:ok, modules} = :application.get_key(:ngauge, :modules)
    Enum.filter(modules, &worker?/1)
  end
end
