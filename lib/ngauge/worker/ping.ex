defmodule Ngauge.Worker.Ping do
  @moduledoc """
  A fake ping worker (for now)
  """

  def run(arg) do
    min = :rand.uniform(100)
    max = min + :rand.uniform(50)
    avg = div(min + max, 2)

    # Chain will enqueue 1.1.1.4 for Ping, we raise immediately
    if arg == "1.1.1.4",
      do: raise("pinging to 1.1.1.4 is forbidden")

    Pfx.new(arg)

    # take some time
    (1_000 + :rand.uniform(1_500)) |> Process.sleep()

    %{"min" => min, "avg" => avg, "max" => max}
  end

  @spec to_str(map) :: binary
  def to_str(result) do
    keys = Map.keys(result) |> Enum.join("/")
    vals = Map.values(result) |> Enum.join("/")

    "#{keys} #{vals}"
  end

  @spec to_csv(map) :: binary
  def to_csv(result) do
    "#{result["min"]},#{result["avg"]},#{result["max"]}"
  end
end
