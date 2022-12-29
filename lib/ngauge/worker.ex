defmodule Ngauge.Worker do
  @moduledoc """
  Behaviour specification and Utility functions for workers

  """

  # [[ BEHAVIOUR ]]

  @callback run(arg :: binary) :: any
  @callback to_str(arg :: any) :: binary
  @callback to_csv(arg :: any) :: [[binary]]
  @callback csv_headers() :: [binary]

  # [[ UTILITIES for workers ]]

  @doc """
  Returns lowercased string of the last label in the `worker`'s module.

  """
  @spec name(atom) :: binary
  def name(worker) when is_atom(worker) do
    worker
    |> Module.split()
    |> List.last()
    |> String.downcase(:ascii)
  end

  @doc """
  Returns `treu` if given `module` is a valid Ngauge.Worker.<module> or not.

  """
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
