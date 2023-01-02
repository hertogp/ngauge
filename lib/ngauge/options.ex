defmodule Ngauge.Options do
  @moduledoc """
  Key,value store for options given on the cli.
  """

  # Since everything else is a GenServer ...
  use GenServer

  # [[ STARTUP API ]]

  def child_spec(_) do
    # called by the supervisor
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [__MODULE__]},
      restart: :permanent,
      shutdown: 20_000
    }
  end

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_state) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  @spec init(any) :: {:ok, map}
  def init(state) do
    {:ok, state}
  end

  # [[ CLIENT API ]]

  @doc """
  Returns the Option's state
  """
  @spec get_state() :: map
  def get_state() do
    GenServer.call(__MODULE__, {:get})
  end

  @doc """
  Gets the value for given `key`, returns nil if it doesn't exist

  """
  @spec get(any) :: any
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Forcefully set the Option's state
  """
  @spec set_state(map) :: :ok
  def set_state(state) when is_map(state) do
    GenServer.cast(__MODULE__, {:set, state})
  end

  @doc """
  Set the `value` for given `key`.
  """
  @spec set(any, any) :: :ok
  def set(key, value) do
    GenServer.cast(__MODULE__, {:set, key, value})
  end

  # TODO: turn set/get state into state/0 and state/1

  # [[ GENSERVER CALLBACKS ]]

  @impl true
  def handle_call({:get}, _from, state),
    do: {:reply, state, state}

  @impl true
  def handle_call({:get, key}, _from, state),
    do: {:reply, Map.get(state, key), state}

  @impl true
  def handle_cast({:set, state}, _old_state),
    do: {:noreply, state}

  @impl true
  def handle_cast({:set, key, value}, state),
    do: {:noreply, Map.put(state, key, value)}
end
