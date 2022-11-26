defmodule Ngauge.Options do
  @moduledoc """
  An agent that holds the Ngauge options given on the cli.

  Used by `Ngauge.CLI` to set the stage so to speak.

  """
  use Agent

  @doc """
  Starts the Options holder
  """
  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_state) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Gets a value from the `bucket` by `key`.
  """
  @spec get(atom) :: any
  def get(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  @doc """
  Puts the `value` for the given `key` in the `bucket`.
  """
  @spec set(atom, any) :: :ok
  def set(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  @doc """
  Forcefully set the Option's state
  """
  @spec set_state(map) :: :ok
  def set_state(state) when is_map(state),
    do: Agent.update(__MODULE__, fn _ -> state end)

  @doc """
  Returns the Option's state
  """
  @spec get_state() :: map
  def get_state(),
    do: Agent.get(__MODULE__, & &1)
end
